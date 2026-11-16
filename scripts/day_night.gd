class_name DayNight
extends Node3D
## The sky over the port through the game's day (M11): the sun rises at
## 06:00 and sets at 18:00 by the calendar, warm at dawn and dusk, the sky
## and its light dark blue at night. It reads the sim and changes nothing in
## it; the view asks darkness() for how lit the port's lights should be.

## Hours of the calendar day the sun is up between.
const SUNRISE := 6.0
const SUNSET := 18.0
const NOON_SKY := Color(0.38, 0.55, 0.85)
const NOON_HORIZON := Color(0.68, 0.78, 0.9)
const DUSK_SKY := Color(0.3, 0.3, 0.5)
const DUSK_HORIZON := Color(0.95, 0.55, 0.3)
const NIGHT_SKY := Color(0.02, 0.03, 0.08)
const NIGHT_HORIZON := Color(0.06, 0.08, 0.16)
const MOONLIGHT := Color(0.3, 0.36, 0.52)

var sim: PortSim
var _sun := DirectionalLight3D.new()
var _sky := ProceduralSkyMaterial.new()
var _env := Environment.new()


func _ready() -> void:
	_sun.shadow_enabled = true
	add_child(_sun)
	# Below the horizon is land, so the view past the map's edge reads as countryside.
	_sky.ground_horizon_color = Color(0.42, 0.5, 0.36)
	_sky.ground_bottom_color = Color(0.36, 0.42, 0.3)
	var sky := Sky.new()
	sky.sky_material = _sky
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_color = MOONLIGHT
	var world := WorldEnvironment.new()
	world.environment = _env
	add_child(world)


func _process(_dt: float) -> void:
	if sim == null:
		return
	var hour := fmod(sim.clock.calendar_minutes() / 60.0, 24.0)
	var height := sun_height(hour)
	var dark := darkness(hour)
	# The sun crosses from east to west, its elevation following the day.
	_sun.rotation_degrees = Vector3(-maxf(height, 0.05) * 70.0 - 5.0, -30.0 - (hour - 12.0) * 12.0, 0.0)
	var warm := clampf(1.0 - absf(height) * 4.0, 0.0, 1.0)
	_sun.light_color = Color(1.0, 0.97, 0.9).lerp(Color(1.0, 0.6, 0.35), warm)
	_sun.light_energy = lerpf(1.0, 0.0, dark)
	_sun.shadow_enabled = dark < 0.9
	_sky.sky_top_color = NOON_SKY.lerp(DUSK_SKY, warm).lerp(NIGHT_SKY, dark)
	_sky.sky_horizon_color = NOON_HORIZON.lerp(DUSK_HORIZON, warm).lerp(NIGHT_HORIZON, dark)
	# The ground below the horizon too: it lights the port from below as ambient light.
	_sky.ground_horizon_color = Color(0.42, 0.5, 0.36).lerp(Color(0.04, 0.05, 0.05), dark)
	_sky.ground_bottom_color = Color(0.36, 0.42, 0.3).lerp(Color(0.02, 0.03, 0.03), dark)
	# By night the ambient light is mostly moonlight, so the port still reads in the dark.
	_env.ambient_light_sky_contribution = lerpf(1.0, 0.2, dark)
	_env.ambient_light_energy = lerpf(1.0, 0.7, dark)


## The sun's height at hour `hour` of the day: 1 at noon, 0 at sunrise and
## sunset, below 0 at night down to -1 at midnight.
static func sun_height(hour: float) -> float:
	return sin(PI * (hour - SUNRISE) / (SUNSET - SUNRISE)) if hour >= SUNRISE and hour <= SUNSET else -sin(PI * fposmod(hour - SUNSET, 24.0) / (24.0 - SUNSET + SUNRISE))


## How dark it is at hour `hour`: 0 by day, rising through dusk to 1 an hour
## after sunset, falling again through dawn.
static func darkness(hour: float) -> float:
	return clampf(-sun_height(hour) * 4.0 + 0.15, 0.0, 1.0)
