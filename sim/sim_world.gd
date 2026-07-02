extends Node3D
## The authoritative simulation. Fixed 60 Hz tick (physics tick). Owns ALL game
## state: players, movement resolution, jump pads — and from later milestones
## weapons, damage, spawns, scoring, bot brains. No input polling, no rendering.
##
## Offline, this runs in-process as the local "server". Phase 2 exposes exactly
## this node over ENet: intents arrive as dictionaries, state/events go out.

const SimPlayer := preload("res://sim/sim_player.gd")
const SimMovement := preload("res://sim/sim_movement.gd")
const SimWeapons := preload("res://sim/sim_weapons.gd")

const PLAYER_LAYER := 2
const WORLD_LAYER := 1
const KNOCKBACK_PER_DMG := 0.1        # m/s of impulse per point of (pre-halving) damage

var players: Dictionary = {}          # id -> SimPlayer
var running := false

var _arena: Node3D
var _spawns: Array = []
var _jump_pads: Array = []
var _events: Array = []               # drained by the presentation layer / future net layer
var _spawn_cursor := 0
var _projectiles: Dictionary = {}     # id -> {owner, weapon, pos, vel, ttl}
var _next_proj_id := 0
var _rng := RandomNumberGenerator.new()

# SIM runs its tick after intents are submitted (client priority < 0 < ours).
func _ready() -> void:
	process_physics_priority = 10


func setup(arena: Node3D) -> void:
	_arena = arena
	_spawns = arena.get_spawn_points()
	_jump_pads = arena.get_jump_pads()
	running = true


func add_player(id: String, display_name: String, is_bot: bool) -> void:
	var p: RefCounted = SimPlayer.new()
	p.id = id
	p.display_name = display_name
	p.is_bot = is_bot
	p.body = _make_body(id)
	p.ammo = SimWeapons.full_ammo()
	add_child(p.body)
	players[id] = p
	_spawn(p)


## The ONLY way anything (human client or bot brain) influences the SIM.
func set_intent(id: String, intent: Dictionary) -> void:
	if players.has(id):
		players[id].intent = intent


func get_player(id: String) -> RefCounted:
	return players.get(id)


func drain_events() -> Array:
	var out := _events
	_events = []
	return out


## Presentation mirror of in-flight projectiles.
func get_projectiles() -> Array:
	var out := []
	for id in _projectiles:
		var pr: Dictionary = _projectiles[id]
		out.append({"id": id, "pos": pr["pos"], "vel": pr["vel"], "weapon": pr["weapon"]})
	return out


func _physics_process(dt: float) -> void:
	if not running:
		return
	for p: RefCounted in players.values():
		if p.alive:
			_move_player(p, dt)
			_check_jump_pads(p)
			_tick_weapon(p, dt)
	_tick_projectiles(dt)


func _move_player(p: RefCounted, dt: float) -> void:
	var intent: Dictionary = p.intent
	p.yaw = intent["yaw"]
	p.pitch = clampf(intent["pitch"], -PI / 2 + 0.01, PI / 2 - 0.01)
	_set_crouch(p, intent["crouch"])

	var wishdir: Vector3 = SimMovement.wish_dir(p.yaw, intent["move"])
	var on_floor: bool = p.body.is_on_floor()
	var vel: Vector3 = p.velocity

	if on_floor:
		if intent["jump"]:
			# no friction on the jump tick — preserves bunny-hop speed
			vel = SimMovement.ground_move(vel, wishdir, p.crouching, dt)
			vel.y = SimMovement.JUMP_VEL
			_events.append({"type": "jump", "id": p.id})
		else:
			vel = SimMovement.apply_friction(vel, dt)
			vel = SimMovement.ground_move(vel, wishdir, p.crouching, dt)
			vel.y = minf(vel.y, 0.0)
	else:
		vel = SimMovement.air_move(vel, wishdir, dt)

	p.body.velocity = vel
	p.body.move_and_slide()
	p.velocity = p.body.velocity


func _check_jump_pads(p: RefCounted) -> void:
	var feet: Vector3 = p.feet_pos()
	for pad in _jump_pads:
		var pos: Vector3 = pad[0]
		var launch: Vector3 = pad[1]
		var radius: float = pad[2]
		var horiz := Vector2(feet.x - pos.x, feet.z - pos.z)
		if horiz.length() <= radius and absf(feet.y - pos.y) < 0.8:
			if p.velocity.y <= launch.y * 0.9:  # don't re-trigger mid-launch
				p.velocity = launch
				p.body.velocity = launch
				_events.append({"type": "jump_pad", "id": p.id, "pos": pos})


## --- combat -----------------------------------------------------------------


func _tick_weapon(p: RefCounted, dt: float) -> void:
	p.cooldown = maxf(p.cooldown - dt, 0.0)
	var want: int = p.intent["weapon"]
	if want >= 0 and want < SimWeapons.COUNT and want != p.weapon:
		p.weapon = want
		p.cooldown = maxf(p.cooldown, SimWeapons.SWITCH_LOCK)
		_events.append({"type": "weapon_switch", "id": p.id, "weapon": want})
	if p.intent["fire"] and p.cooldown <= 0.0 and p.ammo[p.weapon] > 0:
		_fire(p)


func _fire(p: RefCounted) -> void:
	var def: Dictionary = SimWeapons.DEFS[p.weapon]
	p.cooldown = def["cooldown"]
	p.ammo[p.weapon] -= 1
	var origin: Vector3 = p.eye_pos()
	var aim: Vector3 = SimWeapons.view_dir(p.yaw, p.pitch)

	if def["hitscan"]:
		var impacts := []
		for i: int in def["pellets"]:
			var dir: Vector3 = SimWeapons.spread_dir(aim, def["spread"], _rng)
			var hit := _raycast(origin, origin + dir * def["range"], p.body)
			if hit.is_empty():
				impacts.append({"pos": origin + dir * def["range"], "normal": Vector3.UP, "hit_id": ""})
			else:
				var hit_id := ""
				if hit["collider"].has_meta("player_id"):
					hit_id = hit["collider"].get_meta("player_id")
					_damage(players[hit_id], p.id, def["damage"], dir, def["damage"] * KNOCKBACK_PER_DMG * 0.3)
				impacts.append({"pos": hit["position"], "normal": hit["normal"], "hit_id": hit_id})
		_events.append({"type": "fire", "id": p.id, "weapon": p.weapon,
			"origin": origin, "impacts": impacts})
	else:
		var pid := _next_proj_id
		_next_proj_id += 1
		_projectiles[pid] = {"owner": p.id, "weapon": p.weapon,
			"pos": origin + aim * 0.8, "vel": aim * def["speed"], "ttl": def["ttl"]}
		_events.append({"type": "fire", "id": p.id, "weapon": p.weapon,
			"origin": origin, "impacts": []})


func _tick_projectiles(dt: float) -> void:
	for pid in _projectiles.keys():
		var pr: Dictionary = _projectiles[pid]
		pr["ttl"] -= dt
		if pr["ttl"] <= 0.0:
			_explode(pr["pos"], pr["owner"], SimWeapons.DEFS[pr["weapon"]], "")
			_projectiles.erase(pid)
			continue
		var to: Vector3 = pr["pos"] + pr["vel"] * dt
		var owner_body: CharacterBody3D = players[pr["owner"]].body if players.has(pr["owner"]) else null
		var hit := _raycast(pr["pos"], to, owner_body)
		if hit.is_empty():
			pr["pos"] = to
			continue
		var def: Dictionary = SimWeapons.DEFS[pr["weapon"]]
		var direct_id := ""
		if hit["collider"].has_meta("player_id"):
			direct_id = hit["collider"].get_meta("player_id")
			var dir: Vector3 = pr["vel"].normalized()
			_damage(players[direct_id], pr["owner"], def["damage"], dir, def["damage"] * KNOCKBACK_PER_DMG)
		# nudge off the surface so the splash LOS ray doesn't start inside the wall
		_explode(hit["position"] + hit["normal"] * 0.05, pr["owner"], def, direct_id)
		_projectiles.erase(pid)


func _explode(pos: Vector3, owner_id: String, def: Dictionary, skip_id: String) -> void:
	_events.append({"type": "explosion", "pos": pos})
	for p: RefCounted in players.values():
		if not p.alive or p.id == skip_id:
			continue
		var center: Vector3 = p.body.global_position
		var dist: float = maxf(center.distance_to(pos) - 0.4, 0.0)  # capsule allowance
		if dist >= def["splash_radius"]:
			continue
		# explosions don't reach through walls
		var block := _raycast_world(pos, center)
		if not block.is_empty():
			continue
		var falloff: float = 1.0 - dist / def["splash_radius"]
		var raw: int = int(round(def["splash_damage"] * falloff))
		var dmg := raw
		if p.id == owner_id:
			dmg = int(raw / 2.0)  # half self-damage, full knockback: rocket jumps stay strong
		var dir: Vector3 = (center - pos)
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.UP
		_damage(p, owner_id, dmg, dir, raw * KNOCKBACK_PER_DMG)


func _damage(target: RefCounted, attacker_id: String, amount: int, knock_dir: Vector3, knock: float) -> void:
	if not target.alive or target.invuln_t > 0.0:
		return
	if knock > 0.0:
		target.velocity += knock_dir * knock
		target.body.velocity = target.velocity
	target.health -= amount
	_events.append({"type": "damage", "id": target.id, "attacker": attacker_id, "amount": amount})
	if target.health <= 0:
		_kill(target, attacker_id)


## Minimal death (milestone 5 adds respawn, scoring, kill feed plumbing).
func _kill(target: RefCounted, attacker_id: String) -> void:
	target.alive = false
	target.health = 0
	target.body.collision_layer = 0  # corpses don't block shots
	_events.append({"type": "death", "id": target.id, "attacker": attacker_id,
		"pos": target.body.global_position})


func _raycast(from: Vector3, to: Vector3, exclude_body: CharacterBody3D) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, WORLD_LAYER | PLAYER_LAYER)
	if exclude_body != null:
		q.exclude = [exclude_body.get_rid()]
	return space.intersect_ray(q)


func _raycast_world(from: Vector3, to: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, WORLD_LAYER)
	return space.intersect_ray(q)


func _spawn(p: RefCounted) -> void:
	var spot: Vector3 = _spawns[_spawn_cursor % _spawns.size()]
	_spawn_cursor += 1
	p.velocity = Vector3.ZERO
	p.body.velocity = Vector3.ZERO
	p.body.global_position = spot + Vector3(0, p.capsule_half_height() + 0.1, 0)
	# face arena center: forward (-Z rotated by yaw) must point at the origin
	p.yaw = atan2(spot.x, spot.z)
	p.pitch = 0.0
	p.body.reset_physics_interpolation()
	_events.append({"type": "spawn", "id": p.id, "pos": p.body.global_position})


func _set_crouch(p: RefCounted, want: bool) -> void:
	if p.crouching == want:
		return
	# standing up needs headroom
	if not want and _head_blocked(p):
		return
	p.crouching = want
	var capsule: CapsuleShape3D = p.body.get_child(0).shape
	capsule.height = 1.2 if want else 1.8
	var col: CollisionShape3D = p.body.get_child(0)
	col.position.y = 0.0


func _head_blocked(p: RefCounted) -> bool:
	var space: PhysicsDirectSpaceState3D = p.body.get_world_3d().direct_space_state
	var from: Vector3 = p.body.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 1.0, 0), WORLD_LAYER)
	q.exclude = [p.body.get_rid()]
	return not space.intersect_ray(q).is_empty()


func _make_body(id: String) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = "body_" + id
	body.set_meta("player_id", id)
	body.collision_layer = PLAYER_LAYER
	body.collision_mask = WORLD_LAYER | PLAYER_LAYER
	body.floor_snap_length = 0.3
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	col.shape = capsule
	body.add_child(col)
	return body
