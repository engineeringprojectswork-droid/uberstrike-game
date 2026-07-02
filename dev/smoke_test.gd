extends SceneTree
## Headless verification harness. Run with:
##   godot --headless --path . --script res://dev/smoke_test.gd
## Exits 0 on pass, 1 on any failure. Grows with each milestone.

var _fails := 0


func _initialize() -> void:
	await _run()
	quit(1 if _fails > 0 else 0)


func _run() -> void:
	print("=== smoke: arena ===")
	var arena_scene: PackedScene = load("res://scenes/arena.tscn")
	var arena: Node3D = arena_scene.instantiate()
	root.add_child(arena)

	# let physics register the static bodies
	for i in 5:
		await physics_frame

	# --- geometry height checks via downward rays ---
	_check_height(arena, Vector3(8, 0, -2), 0.0, "open floor")
	_check_height(arena, Vector3(0, 0, 0), 3.0, "crown top")
	_check_height(arena, Vector3(19, 0, 14), 4.0, "E deck top")
	_check_height(arena, Vector3(-19, 0, -14), 4.0, "W deck top")
	_check_height(arena, Vector3(0, 0, -9), 1.5, "crown N ramp midpoint")
	_check_height(arena, Vector3(19, 0, -15), 2.0, "E deck ramp midpoint")
	# ramp monotonicity: heights rise walking up the crown N ramp
	var prev := -1.0
	var mono := true
	for t in [0.1, 0.3, 0.5, 0.7, 0.9]:
		var p := Vector3(0, 0, -12).lerp(Vector3(0, 3, -6), t)
		var h := _sample_height(arena, Vector3(p.x, 0, p.z))
		if h < prev:
			mono = false
		prev = h
	_expect(mono, "crown ramp heights monotonic")

	# --- navmesh bake ---
	if not arena.baked:  # wait only if the bake is still running
		await arena.ready_for_match
	var nm: NavigationMesh = arena.navigation_mesh
	_expect(nm != null and nm.get_polygon_count() > 20,
		"navmesh baked (%d polys)" % (nm.get_polygon_count() if nm else 0))

	# navmesh must cover every spawn point
	await physics_frame  # let region sync to the nav map
	await physics_frame
	var map: RID = arena.get_navigation_map()
	for s: Vector3 in arena.get_spawn_points():
		var closest := NavigationServer3D.map_get_closest_point(map, s)
		_expect(closest.distance_to(s) < 1.0,
			"spawn %s on navmesh (dist %.2f)" % [s, closest.distance_to(s)])

	# a cross-arena path exists (ground corner -> E deck)
	var path := NavigationServer3D.map_get_path(map, Vector3(-20, 0, -18), Vector3(19, 4, 14), true)
	_expect(path.size() >= 2 and path[path.size() - 1].distance_to(Vector3(19, 4, 14)) < 2.0,
		"path ground->E deck (%d points)" % path.size())

	await _movement_checks(arena)

	arena.queue_free()
	await process_frame
	await process_frame
	await _match_scene_check()

	print("=== smoke: %s ===" % ("FAIL (%d)" % _fails if _fails > 0 else "PASS"))


func _match_scene_check() -> void:
	print("=== smoke: match scene ===")
	var m: Node = (load("res://scenes/match.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 60:
		await physics_frame
	var sim: Node = m.get_node("SimWorld")
	_expect(sim.running, "match scene: sim running")
	_expect(sim.get_player("p1") != null, "match scene: local player present")
	m.queue_free()


func _movement_checks(arena: Node3D) -> void:
	print("=== smoke: movement ===")
	var sim: Node3D = (load("res://sim/sim_world.gd") as GDScript).new()
	root.add_child(sim)
	sim.setup(arena)
	sim.add_player("t1", "Tester", true)
	var p: RefCounted = sim.get_player("t1")

	# ground run: teleport to open floor, face -Z, hold forward 120 ticks
	p.body.global_position = Vector3(10, 1.0, -2)
	var intent := {"move": Vector2(0, 1), "yaw": 0.0, "pitch": 0.0,
		"jump": false, "crouch": false, "fire": false, "weapon": -1}
	sim.set_intent("t1", intent)
	for i in 120:
		await physics_frame
	var pos: Vector3 = p.body.global_position
	_expect(pos.z < -13.0, "ground run covered %.1f m in 2 s" % (-2.0 - pos.z))
	_expect(absf(pos.x - 10.0) < 0.5, "ground run stayed on line (x drift %.2f)" % absf(pos.x - 10.0))
	var ground_speed: float = Vector2(p.velocity.x, p.velocity.z).length()
	_expect(absf(ground_speed - 8.13) < 0.5, "ground speed %.2f ~ 8.13 m/s cap" % ground_speed)

	# jump: apex must clear ~1.1 m
	sim.set_intent("t1", {"move": Vector2.ZERO, "yaw": 0.0, "pitch": 0.0,
		"jump": true, "crouch": false, "fire": false, "weapon": -1})
	var start_y: float = p.feet_pos().y
	var apex := start_y
	for i in 45:
		await physics_frame
		apex = maxf(apex, p.feet_pos().y)
	_expect(apex - start_y > 0.9, "jump apex +%.2f m" % (apex - start_y))

	# auto bunny-hop: hold jump+forward, speed must stay at/above the ground cap
	p.body.global_position = Vector3(10, 1.0, 18)
	p.velocity = Vector3.ZERO
	p.body.velocity = Vector3.ZERO
	sim.set_intent("t1", {"move": Vector2(0, 1), "yaw": 0.0, "pitch": 0.0,
		"jump": true, "crouch": false, "fire": false, "weapon": -1})
	var hops := 0
	var last_floor := true
	for i in 200:
		await physics_frame
		var on_floor: bool = p.body.is_on_floor()
		if on_floor and not last_floor:
			hops += 1
		last_floor = on_floor
	var hop_speed: float = Vector2(p.velocity.x, p.velocity.z).length()
	_expect(hops >= 3, "bunny-hopped %d times" % hops)
	_expect(hop_speed >= 7.7, "bunny-hop kept speed %.2f m/s" % hop_speed)

	# jump pad: stand on the crown pad, expect a big vertical launch
	p.body.global_position = Vector3(0, 3.0 + 1.0, 0)
	p.velocity = Vector3.ZERO
	p.body.velocity = Vector3.ZERO
	sim.set_intent("t1", SimPlayerIntent())
	var pad_apex := 0.0
	var saw_pad_event := false
	for i in 90:
		await physics_frame
		pad_apex = maxf(pad_apex, p.feet_pos().y)
		for ev: Dictionary in sim.drain_events():
			if ev["type"] == "jump_pad":
				saw_pad_event = true
	_expect(saw_pad_event, "jump pad event fired")
	_expect(pad_apex > 7.5, "jump pad apex %.1f m" % pad_apex)

	sim.queue_free()


func SimPlayerIntent() -> Dictionary:
	return {"move": Vector2.ZERO, "yaw": 0.0, "pitch": 0.0,
		"jump": false, "crouch": false, "fire": false, "weapon": -1}


func _sample_height(arena: Node3D, at: Vector3) -> float:
	var space := arena.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 50, 0), at + Vector3(0, -5, 0), 1)
	var hit := space.intersect_ray(q)
	return hit.position.y if hit else -999.0


func _check_height(arena: Node3D, at: Vector3, expected: float, label: String) -> void:
	var h := _sample_height(arena, at)
	_expect(absf(h - expected) < 0.35, "%s height %.2f ~ %.2f" % [label, h, expected])


func _expect(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  ", label)
	else:
		_fails += 1
		printerr("  FAIL  ", label)
