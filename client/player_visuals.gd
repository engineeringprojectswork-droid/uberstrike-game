extends Node3D
## Presentation mirrors for every non-local player: colored capsule + gun +
## name label, invuln flicker, corpse tip-over on death. Reads SIM state only.

var sim: Node3D
var local_id := ""

var _rigs: Dictionary = {}  # player id -> Node3D

const BODY_COLORS := [
	Color("e05656"), Color("56aee0"), Color("62d47a"), Color("d4b542"),
	Color("b062d4"), Color("d47f42"), Color("42d4c3"), Color("d4629e"),
]


func _ready() -> void:
	process_physics_priority = 30


func _physics_process(_dt: float) -> void:
	if sim == null:
		return
	for p: RefCounted in sim.players.values():
		if p.id == local_id:
			continue
		var rig: Node3D = _rigs.get(p.id)
		if rig == null:
			rig = _make_rig(p)
			_rigs[p.id] = rig
		rig.visible = p.alive
		if p.alive:
			rig.global_position = p.body.global_position
			rig.rotation = Vector3(0, p.yaw, 0)
			var mesh: MeshInstance3D = rig.get_node("Body")
			if p.invuln_t > 0.0:
				mesh.transparency = 0.65 if int(p.invuln_t * 12.0) % 2 == 0 else 0.15
			else:
				mesh.transparency = 0.0


func handle(ev: Dictionary) -> void:
	if ev["type"] == "death" and ev["id"] != local_id:
		_corpse(ev["pos"], ev["id"])
	elif ev["type"] == "spawn" and _rigs.has(ev["id"]):
		_rigs[ev["id"]].reset_physics_interpolation()


func _make_rig(p: RefCounted) -> Node3D:
	var rig := Node3D.new()
	add_child(rig)

	var body := MeshInstance3D.new()
	body.name = "Body"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	body.mesh = capsule
	body.material_override = _color_mat(_color_for(p.id))
	rig.add_child(body)

	var gun := MeshInstance3D.new()
	var gun_mesh := BoxMesh.new()
	gun_mesh.size = Vector3(0.08, 0.08, 0.5)
	gun.mesh = gun_mesh
	gun.position = Vector3(0.3, 0.35, -0.4)
	gun.material_override = _color_mat(Color("2b3048"))
	rig.add_child(gun)

	var label := Label3D.new()
	label.text = p.display_name
	label.position = Vector3(0, 1.35, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.outline_size = 8
	label.pixel_size = 0.004
	rig.add_child(label)

	rig.global_position = p.body.global_position
	rig.reset_physics_interpolation()
	return rig


func _corpse(pos: Vector3, id: String) -> void:
	var corpse := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	corpse.mesh = capsule
	corpse.material_override = _color_mat(_color_for(id).darkened(0.3))
	add_child(corpse)
	corpse.global_position = pos
	var tw := corpse.create_tween()
	tw.set_parallel(true)
	tw.tween_property(corpse, "rotation:z", PI / 2, 0.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(corpse, "position:y", pos.y - 0.55, 0.4)
	tw.chain().tween_interval(1.2)
	tw.chain().tween_property(corpse, "transparency", 1.0, 0.6)
	tw.chain().tween_callback(corpse.queue_free)


func _color_for(id: String) -> Color:
	return BODY_COLORS[absi(id.hash()) % BODY_COLORS.size()]


func _color_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	return m
