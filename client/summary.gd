extends CanvasLayer
## End-of-match summary: winner banner, score table, play again / menu.

var local_id := ""


func _ready() -> void:
	layer = 12
	visible = false


func show_results(scores: Array) -> void:
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var panel := ColorRect.new()
	panel.color = Color(0.05, 0.06, 0.12, 0.88)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var won: bool = not scores.is_empty() and scores[0]["id"] == local_id
	var banner := Label.new()
	banner.text = "VICTORY" if won else "DEFEAT — %s wins" % scores[0]["name"]
	banner.add_theme_font_size_override("font_size", 52)
	banner.add_theme_color_override("font_color",
		Color("62d47a") if won else Color("e05656"))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(banner)

	box.add_child(_row("PLAYER", "FRAGS", "DEATHS", Color("8a93c4")))
	for s: Dictionary in scores:
		var color := Color("ff7a1a") if s["id"] == local_id else Color("e8ecff")
		box.add_child(_row(s["name"], str(s["frags"]), str(s["deaths"]), color))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	box.add_child(spacer)

	var again := Button.new()
	again.text = "  Play again  "
	again.add_theme_font_size_override("font_size", 24)
	again.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/match.tscn"))
	box.add_child(again)

	var menu := Button.new()
	menu.text = "Main menu"
	menu.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	box.add_child(menu)


func _row(a: String, b: String, c: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for pair: Array in [[a, 260], [b, 110], [c, 110]]:
		var l := Label.new()
		l.text = pair[0]
		l.custom_minimum_size = Vector2(pair[1], 0)
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_color", color)
		row.add_child(l)
	return row
