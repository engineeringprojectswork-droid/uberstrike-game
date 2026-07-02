# Polyblast Arena

An **original**, offline, single-player-vs-bots arena FPS for Windows, built in
**Godot 4.7 (GDScript)**. Stylized low-poly deathmatch in the spirit of classic
arena shooters. Every asset is generated in code (primitive meshes + procedural
materials) — no third-party or copyrighted game assets anywhere.

## Play

- **Exported build:** run `export/polyblast_arena.exe` (build it once — see
  Export below; binaries are not committed).
- **From the editor:** open the project in Godot 4.7 and press Play.

Pick bot count (1–8) and difficulty (Easy/Normal/Hard) in the menu. First to
20 frags wins.

### Controls

| Input | Action |
|---|---|
| WASD + mouse | Move / look (Quake-3 style: air-strafe & bunny-hop work — hold Space) |
| Space | Jump (hold for auto bunny-hop) |
| Ctrl | Crouch |
| Mouse 1 | Fire |
| 1 / 2 / 3 | Pulse Rifle / Thumper (rockets — rocket jumps work) / Scattergun |
| Esc | Pause |

## Architecture — server-authoritative from day 1

Two layers that never bleed together:

- **`/sim` — SIM (authoritative):** all game state, movement resolution, hit
  detection, damage, spawns, scoring; `/bots` brains run inside the SIM tick.
  Fixed 60 Hz tick. No input polling, no rendering.
- **`/client` — CLIENT (presentation):** input capture, camera, visuals/FX,
  HUD, menus, interpolation. Sends *intent dictionaries* to the SIM; reads
  state and a per-tick event queue back.

The offline game runs the SIM in-process as a local "server"; the human and
all bots are SIM entities under identical rules (bots literally submit the
same intent schema the human client does). Players are identified by ID
strings, never IPs.

### Headless SIM (dedicated-server seam)

```
# from the project (or the exported exe):
polyblast_arena.exe --headless -- --server --bots=5 --difficulty=1 --fraglimit=15
godot --headless --path . res://scenes/server_main.tscn -- --server --bots=5
```

Runs a bots-only match with zero rendering, prints the kill log, exits when
the match ends.

### Where Phase 2 (online) plugs in

`sim/sim_world.gd` is the entire authority surface:

1. **Intents in:** `SimWorld.set_intent(id, dict)` — today called directly by
   `client/client_main.gd` and `bots/bot_brain.gd`. Online: an ENet
   listen-server receives the same dicts as RPCs and calls the same method.
2. **State out:** clients render from `SimWorld.players` / `get_projectiles()`
   / `drain_events()`. Online: serialize those into snapshot/event packets.
3. `scenes/server_main.tscn` already boots the SIM with no rendering — a
   dedicated server is that scene + an ENet peer.

No SIM rewrite is needed: replace the in-process calls with networked ones.

## Folders

| Path | Contents |
|---|---|
| `/sim` | Authoritative simulation (tick, movement, weapons, combat, nav wrapper) |
| `/bots` | Bot FSM brains (produce SIM intents) |
| `/client` | Presentation: input, camera, FX, HUD, menus, materials |
| `/scenes` | menu / match / arena / headless server scenes |
| `/dev` | Headless verification harness (see below) |
| `/export` | Windows export target (gitignored binaries) |

## Verification

```
powershell -File dev\run_smoke.ps1 [-Godot <path to godot console exe>]
```

~60 headless checks: arena geometry ray-tests, navmesh coverage, movement
(speed cap / jump / bunny-hop / jump pads), weapons (hitscan, rocket flight,
splash, knockback, rocket jump), combat loop (kill/score/respawn/invuln/match
end), bot roaming + fighting, scene wiring. The runner fails on any GDScript
error even when Godot's exit code misses it.

## Export

Windows preset is committed (`export_presets.cfg`, embedded PCK). One-time:
install export templates for Godot 4.7, then:

```
godot --headless --path . --export-release "Windows Desktop" export/polyblast_arena.exe
```

## Assets & licenses

Everything is generated at runtime by project code: procedural grid textures
(`client/materials.gd`), primitive meshes (Box/Capsule/Cylinder/Sphere),
procedural sky. **No external assets, no UberStrike content, names, maps, or
logos.** Nothing to attribute; the project is safe to license as a whole.

## Status

Phase 1 complete (offline + bots): see commit history — one commit per
milestone. Phase 2 (Godot ENet online play) deliberately deferred.
