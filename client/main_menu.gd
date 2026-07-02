extends Control
## Main menu: Play, bot count, difficulty, quit. All controls built in code.

const DIFFICULTIES := ["Easy", "Normal", "Hard"]

var _bot_label: Label


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color("14172a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 18)
	add_child(box)

	var title := Label.new()
	title.text = "POLYBLAST ARENA"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color("ff7a1a"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "offline arena deathmatch vs bots"
	subtitle.add_theme_color_override("font_color", Color("8a93c4"))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	box.add_child(_spacer(10))

	_bot_label = Label.new()
	_bot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_bot_label)

	var bots := HSlider.new()
	bots.min_value = 1
	bots.max_value = 8
	bots.step = 1
	bots.value = GameConfig.bot_count
	bots.custom_minimum_size = Vector2(320, 24)
	bots.value_changed.connect(func(v: float) -> void:
		GameConfig.bot_count = int(v)
		_update_bot_label())
	box.add_child(bots)
	_update_bot_label()

	var diff_row := HBoxContainer.new()
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_row.add_theme_constant_override("separation", 12)
	var diff_label := Label.new()
	diff_label.text = "Difficulty"
	diff_row.add_child(diff_label)
	var diff := OptionButton.new()
	for d in DIFFICULTIES:
		diff.add_item(d)
	diff.selected = GameConfig.difficulty
	diff.item_selected.connect(func(i: int) -> void: GameConfig.difficulty = i)
	diff_row.add_child(diff)
	box.add_child(diff_row)

	box.add_child(_spacer(10))

	var play := Button.new()
	play.name = "PlayButton"
	play.text = "  PLAY  "
	play.add_theme_font_size_override("font_size", 32)
	play.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/match.tscn"))
	box.add_child(play)

	var quit := Button.new()
	quit.name = "QuitButton"
	quit.text = "Quit"
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)


func _update_bot_label() -> void:
	_bot_label.text = "Bots: %d" % GameConfig.bot_count


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
