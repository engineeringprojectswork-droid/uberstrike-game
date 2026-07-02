extends NavigationRegion3D
## Original arena blockout — all geometry built from a compact data table at load.
## Shared world: SIM uses its colliders/navmesh/spawn data, CLIENT sees its visuals.

signal ready_for_match

const ArenaMaterials := preload("res://client/materials.gd")
const WORLD_LAYER := 1

## True once the navmesh bake completed (check before awaiting ready_for_match —
## the bake can finish before listeners connect).
var baked := false

## Static boxes: [center, size, material_id, rotation_degrees]
## material_id: 0 floor, 1 wall, 2 block, 3 accent
const BOXES: Array = [
	# floor slab (top at y=0)
	[Vector3(0, -0.5, 0), Vector3(48, 1, 48), 0],
	# perimeter walls, 8 m tall
	[Vector3(0, 4, -24.5), Vector3(50, 8, 1), 1],
	[Vector3(0, 4, 24.5), Vector3(50, 8, 1), 1],
	[Vector3(24.5, 4, 0), Vector3(1, 8, 48), 1],
	[Vector3(-24.5, 4, 0), Vector3(1, 8, 48), 1],
	# central crown — solid raised platform, top at y=3
	[Vector3(0, 1.5, 0), Vector3(12, 3, 12), 2],
	# side decks, tops at y=4
	[Vector3(19, 3.75, 5), Vector3(10, 0.5, 30), 2],    # E deck, z -10..20
	[Vector3(-19, 3.75, -5), Vector3(10, 0.5, 30), 2],  # W deck, z -20..10
	# cover blocks
	[Vector3(7, 1, -14), Vector3(3, 2, 3), 2],
	[Vector3(-7, 1, 14), Vector3(3, 2, 3), 2],
	[Vector3(12, 0.75, -3), Vector3(2, 1.5, 4), 2],
	[Vector3(-12, 0.75, 3), Vector3(2, 1.5, 4), 2],
	[Vector3(3, 1.25, 16), Vector3(4, 2.5, 2), 2],
	[Vector3(-3, 1.25, -16), Vector3(4, 2.5, 2), 2],
	[Vector3(20, 2, -20), Vector3(2, 4, 2), 2],
	[Vector3(-20, 2, 20), Vector3(2, 4, 2), 2],
]

## Ramps: [bottom_edge_center(ground), top_edge_center, width]
const RAMPS: Array = [
	[Vector3(0, 0, -12), Vector3(0, 3, -6), 4.0],     # crown N
	[Vector3(0, 0, 12), Vector3(0, 3, 6), 4.0],       # crown S
	[Vector3(19, 0, -20), Vector3(19, 4, -10), 8.0],  # E deck, north end
	[Vector3(-19, 0, 20), Vector3(-19, 4, 10), 8.0],  # W deck, south end
]

## Jump pads: [pos(ground), launch_velocity, radius]
const JUMP_PADS: Array = [
	[Vector3(11, 0, 8), Vector3(6, 14, 0), 1.5],    # to E deck
	[Vector3(-11, 0, -8), Vector3(-6, 14, 0), 1.5], # to W deck
	[Vector3(0, 3, 0), Vector3(0, 16, 0), 1.5],     # crown vertical boost
]

## Spawn floor positions (feet); SIM faces them toward arena center.
const SPAWNS: Array = [
	Vector3(20, 0, 20), Vector3(-20, 0, 20), Vector3(14, 0, -18), Vector3(-20, 0, -18),
	Vector3(19, 4, 14), Vector3(-19, 4, -14), Vector3(0, 3, 3), Vector3(0, 0, -18),
]


func _ready() -> void:
	_build_geometry()
	_build_environment()
	_bake_navmesh()


func get_spawn_points() -> Array:
	return SPAWNS


func get_jump_pads() -> Array:
	return JUMP_PADS


func _build_geometry() -> void:
	var mats: Array = [
		ArenaMaterials.floor_mat(), ArenaMaterials.wall_mat(),
		ArenaMaterials.block_mat(), ArenaMaterials.accent_mat(),
	]
	for b in BOXES:
		var rot: Vector3 = b[3] if b.size() > 3 else Vector3.ZERO
		_add_box(b[0], b[1], mats[b[2]], rot)
	for r in RAMPS:
		_add_ramp(r[0], r[1], r[2], mats[2])
	for p in JUMP_PADS:
		_add_pad_visual(p[0])


func _add_box(center: Vector3, size: Vector3, mat: Material, rot_deg := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.position = center
	body.rotation_degrees = rot_deg
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)


## Ramp surface runs exactly through the two edge centers; slightly overlong to seal seams.
func _add_ramp(bottom: Vector3, top: Vector3, width: float, mat: Material) -> void:
	var d := top - bottom
	var horiz := Vector3(d.x, 0, d.z)
	var yaw := atan2(horiz.x, horiz.z)
	var pitch := atan2(d.y, horiz.length())
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch)
	var thickness := 0.5
	var length := d.length() + 0.6
	var center := (bottom + top) * 0.5 - basis.y * (thickness * 0.5)

	var body := StaticBody3D.new()
	body.transform = Transform3D(basis, center)
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, thickness, length)
	col.shape = shape
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, thickness, length)
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)


func _add_pad_visual(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.5
	mesh.bottom_radius = 1.5
	mesh.height = 0.15
	mi.mesh = mesh
	mi.material_override = ArenaMaterials.accent_mat()
	mi.position = pos + Vector3(0, 0.075, 0)
	add_child(mi)


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("1a2038")
	sky_mat.sky_horizon_color = Color("46507a")
	sky_mat.ground_bottom_color = Color("14172a")
	sky_mat.ground_horizon_color = Color("46507a")
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled = true
	env.ssao_intensity = 1.5
	env.glow_enabled = true
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _bake_navmesh() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.agent_radius = 0.5
	nm.agent_height = 1.8
	nm.agent_max_slope = 40.0
	navigation_mesh = nm
	bake_finished.connect(func() -> void:
		baked = true
		ready_for_match.emit(), CONNECT_ONE_SHOT)
	bake_navigation_mesh(true)
