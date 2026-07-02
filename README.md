# Polyblast Arena

An **original**, offline, single-player-vs-bots arena FPS for Windows, built in
**Godot 4.7 (GDScript)**. Stylized low-poly deathmatch in the spirit of classic
arena shooters — all assets are generated (primitives + procedural materials);
no third-party game assets are used.

## Architecture — server-authoritative from day 1

Two layers that never bleed together:

- **`/sim` — SIM (authoritative):** all game state, movement resolution, hit
  detection, damage, spawns, scoring, bot AI. Fixed 60 Hz tick. No input
  polling, no rendering.
- **`/client` — CLIENT (presentation):** input capture, camera, rendering, HUD,
  audio, interpolation. Sends *intents* to SIM; reads state from SIM.

The offline build runs SIM in-process as a local "server"; the human player and
all bots are just SIM entities under identical rules. Phase 2 (online) exposes
the same SIM over Godot ENet high-level multiplayer — no rewrite. Players are
identified by ID strings, never IPs.

## Folders

| Path | Contents |
|---|---|
| `/sim` | Authoritative simulation (tick, movement, weapons, combat, nav wrapper) |
| `/client` | Presentation: input, camera, visuals, HUD, menus |
| `/bots` | Bot brains (FSM producing SIM intents) |
| `/scenes` | Scene files (menu, match, arena, headless server) |
| `/assets` | Generated assets |
| `/export` | Windows export output (binaries are gitignored) |

## Run

- **Play:** open the project in Godot 4.7 and run, or launch the exported exe
  from `/export`.
- **Headless SIM (dedicated-server seam):**
  `godot --headless res://scenes/server_main.tscn -- --server`

## Status

Phase 1 (offline + bots) — built milestone by milestone; see commit history.
