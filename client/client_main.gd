extends Node
## CLIENT orchestration: captures input, sends intents to the SIM, owns the
## first-person camera. Reads SIM state; never writes it.

const CameraRig := preload("res://client/camera_rig.gd")

const LOCAL_ID := "p1"

@onready var arena: Node3D = get_node("../Arena")
@onready var sim: Node3D = get_node("../SimWorld")

var rig: Node3D
var camera: Camera3D
var yaw := 0.0
var pitch := 0.0


func _ready() -> void:
	process_physics_priority = -10  # intents land before the SIM tick
	if not arena.baked:
		await arena.ready_for_match
	sim.setup(arena)
	sim.add_player(LOCAL_ID, "You", false)
	var p: RefCounted = sim.get_player(LOCAL_ID)
	yaw = p.yaw
	pitch = p.pitch
	_build_camera()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _build_camera() -> void:
	rig = CameraRig.new()
	rig.sim = sim
	rig.player_id = LOCAL_ID
	camera = Camera3D.new()
	camera.fov = 90.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	rig.add_child(camera)
	get_parent().add_child.call_deferred(rig)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw = wrapf(yaw - event.relative.x * GameConfig.mouse_sensitivity, -PI, PI)
		pitch = clampf(pitch - event.relative.y * GameConfig.mouse_sensitivity, -PI / 2 + 0.01, PI / 2 - 0.01)
	elif event.is_action_pressed("pause"):
		# temporary until the milestone-7 pause menu
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED)


func _process(_dt: float) -> void:
	if camera != null:
		camera.rotation = Vector3(pitch, 0, 0)
		rig.rotation = Vector3(0, yaw, 0)
	for ev: Dictionary in sim.drain_events():
		_on_sim_event(ev)


func _physics_process(_dt: float) -> void:
	if not sim.running:
		return
	var move := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_back", "move_forward"),
	)
	sim.set_intent(LOCAL_ID, {
		"move": move,
		"yaw": yaw,
		"pitch": pitch,
		"jump": Input.is_action_pressed("jump"),  # held = auto bunny-hop
		"crouch": Input.is_action_pressed("crouch"),
		"fire": Input.is_action_pressed("fire"),
		"weapon": _weapon_choice(),
	})


func _weapon_choice() -> int:
	for i in 3:
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			return i
	return -1


func _on_sim_event(ev: Dictionary) -> void:
	match ev["type"]:
		"spawn":
			if ev["id"] == LOCAL_ID and rig != null:
				rig.reset_physics_interpolation()
