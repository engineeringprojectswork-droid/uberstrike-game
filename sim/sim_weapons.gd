## Weapon definitions + aim math. Data only — firing is resolved by the SIM.
## All names and stats are original.

const DEFS := [
	{
		"name": "Pulse Rifle", "hitscan": true, "damage": 10, "cooldown": 0.1,
		"spread": 0.015, "pellets": 1, "ammo_max": 100, "range": 100.0,
	},
	{
		"name": "Thumper", "hitscan": false, "damage": 90, "cooldown": 0.8,
		"spread": 0.0, "pellets": 1, "ammo_max": 20, "speed": 25.0,
		"splash_radius": 3.5, "splash_damage": 80, "ttl": 6.0,
	},
	{
		"name": "Scattergun", "hitscan": true, "damage": 9, "cooldown": 0.9,
		"spread": 0.06, "pellets": 8, "ammo_max": 30, "range": 40.0,
	},
]

const COUNT := 3
const SWITCH_LOCK := 0.25  # seconds of cooldown applied on weapon swap


static func full_ammo() -> Dictionary:
	var out := {}
	for i in DEFS.size():
		out[i] = DEFS[i]["ammo_max"]
	return out


static func view_dir(yaw: float, pitch: float) -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0)) * Vector3.FORWARD


## Uniform jitter inside a cone; `spread` is the cone half-angle in radians.
static func spread_dir(dir: Vector3, spread: float, rng: RandomNumberGenerator) -> Vector3:
	if spread <= 0.0:
		return dir
	var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	var angle := rng.randf() * TAU
	var radius := sqrt(rng.randf()) * spread
	var offset := (basis.x * cos(angle) + basis.y * sin(angle)) * radius
	return (dir + offset).normalized()
