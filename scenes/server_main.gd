extends Node3D
## Headless SIM entry point — the dedicated-server seam. No rendering, no
## input: bots-only match under identical SIM rules. Run with:
##   godot --headless res://scenes/server_main.tscn -- --server --bots=5 --difficulty=1
## Phase 2 replaces "bots only" with ENet peers feeding the same intents.

const SimWorld := preload("res://sim/sim_world.gd")

@onready var arena: Node3D = $Arena

var sim: Node3D
var _report_t := 5.0


func _ready() -> void:
	var bots := 5
	var difficulty := 1
	var frag_limit := 15
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bots="):
			bots = maxi(int(arg.get_slice("=", 1)), 2)
		elif arg.begins_with("--difficulty="):
			difficulty = clampi(int(arg.get_slice("=", 1)), 0, 2)
		elif arg.begins_with("--fraglimit="):
			frag_limit = maxi(int(arg.get_slice("=", 1)), 1)
	if not arena.baked:
		await arena.ready_for_match
	sim = SimWorld.new()
	add_child(sim)
	sim.setup(arena, {"frag_limit": frag_limit})
	for i in bots:
		sim.add_bot(difficulty)
	print("[server] match started: %d bots, difficulty %d, frag limit %d" % [bots, difficulty, frag_limit])


func _process(dt: float) -> void:
	if sim == null:
		return
	for ev: Dictionary in sim.drain_events():
		match ev["type"]:
			"kill":
				print("[server] %s fragged %s" % [ev["attacker_name"], ev["victim_name"]])
			"match_end":
				print("[server] match over. final scores:")
				for row: Dictionary in ev["scores"]:
					print("[server]   %-8s %3d frags / %d deaths" % [row["name"], row["frags"], row["deaths"]])
				get_tree().quit(0)
	_report_t -= dt
	if _report_t <= 0.0:
		_report_t = 5.0
		var top: Dictionary = sim.get_scores()[0]
		print("[server] leader: %s with %d frags" % [top["name"], top["frags"]])
