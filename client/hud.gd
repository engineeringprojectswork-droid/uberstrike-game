extends CanvasLayer
## In-match HUD: crosshair, health, ammo, score, kill feed, damage flash,
## respawn overlay. Reads SIM state; never writes it.

const SimWeapons := preload("res://sim/sim_weapons.gd")

var sim: Node3D
var local_id := ""

var _health: Label
var _ammo: Label
var _score: Label
var _feed: VBoxContainer
var _flash: ColorRect
var _respawn: Label
var _poll_t := 0.0


func _ready() -> void:
	var cross := CrosshairControl.new()
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cross)

	_flash = ColorRect.new()
	_flash.color = Color(0.9, 0.1, 0.1, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_health = _label(24, HORIZONTAL_ALIGNMENT_LEFT)
	_health.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_health.position = Vector2(24, -60)
	_health.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_health)

	_ammo = _label(24, HORIZONTAL_ALIGNMENT_RIGHT)
	_ammo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo.position = Vector2(-260, -60)
	_ammo.custom_minimum_size = Vector2(236, 0)
	_ammo.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_ammo)

	_score = _label(20, HORIZONTAL_ALIGNMENT_LEFT)
	_score.position = Vector2(24, 18)
	add_child(_score)

	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.position = Vector2(-340, 18)
	_feed.custom_minimum_size = Vector2(316, 0)
	add_child(_feed)

	_respawn = _label(40, HORIZONTAL_ALIGNMENT_CENTER)
	_respawn.text = "RESPAWNING..."
	_respawn.set_anchors_preset(Control.PRESET_CENTER)
	_respawn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_respawn.visible = false
	add_child(_respawn)


func handle(ev: Dictionary) -> void:
	match ev["type"]:
		"damage":
			if ev["id"] == local_id:
				_flash.color.a = minf(0.05 + ev["amount"] * 0.006, 0.45)
		"kill":
			var line := _label(18, HORIZONTAL_ALIGNMENT_RIGHT)
			if ev["suicide"]:
				line.text = "%s self-destructed" % ev["victim_name"]
			else:
				line.text = "%s  >  %s" % [ev["attacker_name"], ev["victim_name"]]
			line.add_theme_color_override("font_color",
				Color("ff7a1a") if ev["attacker"] == local_id else Color("c7cdf2"))
			_feed.add_child(line)
			if _feed.get_child_count() > 4:
				_feed.get_child(0).queue_free()
			var tw := line.create_tween()
			tw.tween_interval(4.0)
			tw.tween_property(line, "modulate:a", 0.0, 0.8)
			tw.tween_callback(line.queue_free)
		"death":
			if ev["id"] == local_id:
				_respawn.visible = true
		"spawn":
			if ev["id"] == local_id:
				_respawn.visible = false


func _process(dt: float) -> void:
	_flash.color.a = maxf(_flash.color.a - dt * 1.2, 0.0)
	if sim == null:
		return
	_poll_t -= dt
	if _poll_t > 0.0:
		return
	_poll_t = 0.25
	var p: RefCounted = sim.get_player(local_id)
	if p == null:
		return
	_health.text = "HP  %d" % p.health
	_health.add_theme_color_override("font_color",
		Color("e05656") if p.health <= 30 else Color("e8ecff"))
	var wname: String = SimWeapons.DEFS[p.weapon]["name"]
	_ammo.text = "%s  |  %d" % [wname, p.ammo[p.weapon]]
	var rows: Array = sim.get_scores()
	if rows.is_empty():
		return
	var me_frags := 0
	for row: Dictionary in rows:
		if row["id"] == local_id:
			me_frags = row["frags"]
	_score.text = "You %d   |   %s %d   |   first to %d wins" % [
		me_frags, rows[0]["name"], rows[0]["frags"], sim.frag_limit]


func _label(size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color("e8ecff"))
	l.add_theme_color_override("font_outline_color", Color("14172a"))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = align
	return l


class CrosshairControl:
	extends Control

	func _draw() -> void:
		var c := size * 0.5
		var col := Color("e8ecff", 0.9)
		var gap := 5.0
		var len := 9.0
		draw_line(c + Vector2(gap, 0), c + Vector2(gap + len, 0), col, 2.0)
		draw_line(c - Vector2(gap, 0), c - Vector2(gap + len, 0), col, 2.0)
		draw_line(c + Vector2(0, gap), c + Vector2(0, gap + len), col, 2.0)
		draw_line(c - Vector2(0, gap), c - Vector2(0, gap + len), col, 2.0)
		draw_circle(c, 1.5, col)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()
