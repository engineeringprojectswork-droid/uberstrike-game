extends Node3D
## The authoritative simulation. Fixed 60 Hz tick (physics tick). Owns ALL game
## state: players, movement resolution, jump pads — and from later milestones
## weapons, damage, spawns, scoring, bot brains. No input polling, no rendering.
##
## Offline, this runs in-process as the local "server". Phase 2 exposes exactly
## this node over ENet: intents arrive as dictionaries, state/events go out.

const SimPlayer := preload("res://sim/sim_player.gd")
const SimMovement := preload("res://sim/sim_movement.gd")

const PLAYER_LAYER := 2
const WORLD_LAYER := 1

var players: Dictionary = {}          # id -> SimPlayer
var running := false

var _arena: Node3D
var _spawns: Array = []
var _jump_pads: Array = []
var _events: Array = []               # drained by the presentation layer / future net layer
var _spawn_cursor := 0

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


func _physics_process(dt: float) -> void:
	if not running:
		return
	for p: RefCounted in players.values():
		if p.alive:
			_move_player(p, dt)
			_check_jump_pads(p)


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
