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

	print("=== smoke: %s ===" % ("FAIL (%d)" % _fails if _fails > 0 else "PASS"))


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
