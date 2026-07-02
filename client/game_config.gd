extends Node
## Autoload: match configuration + input action registration.
## CLIENT-owned convenience; SIM never reads Input, only the intents it is fed.

const FRAG_LIMIT_DEFAULT := 20

var bot_count: int = 5
var difficulty: int = 1  # 0 = Easy, 1 = Normal, 2 = Hard
var frag_limit: int = FRAG_LIMIT_DEFAULT
var mouse_sensitivity: float = 0.0025

## Result of the last finished match, read by the summary screen.
var last_match_result: Dictionary = {}


func _init() -> void:
	_register_actions()


func is_server_mode() -> bool:
	return "--server" in OS.get_cmdline_user_args()


func _register_actions() -> void:
	_key_action("move_forward", KEY_W)
	_key_action("move_back", KEY_S)
	_key_action("move_left", KEY_A)
	_key_action("move_right", KEY_D)
	_key_action("jump", KEY_SPACE)
	_key_action("crouch", KEY_CTRL)
	_key_action("weapon_1", KEY_1)
	_key_action("weapon_2", KEY_2)
	_key_action("weapon_3", KEY_3)
	_key_action("pause", KEY_ESCAPE)
	_mouse_action("fire", MOUSE_BUTTON_LEFT)


func _key_action(action: String, keycode: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)


func _mouse_action(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
