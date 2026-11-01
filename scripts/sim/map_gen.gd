class_name MapGen
extends RefCounted
## Coastlines drawn from a seed, in the same form as the maps in the data
## (see Content's "maps"): the sea down the west side with a curving coast,
## a bay and a headland, a river winding in from the north or south edge,
## clear of the highway's row, and up to two islands. The same seed always
## gives the same map.

## How a generated map is named in a save and as PortSim.map.
const PREFIX := "generated:"
## Metres between the coastline's points, down the site.
const STEP := 80.0


## The map for `seed_value` on a site of `site`'s size.
static func make(seed_value: int, site: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var width: float = site.width
	var height: float = site.height
	var base := rng.randf_range(0.18, 0.26) * width
	var bay := Vector2(rng.randf_range(0.2, 0.8) * height, rng.randf_range(80.0, 160.0))
	var cape := Vector2(rng.randf_range(0.2, 0.8) * height, rng.randf_range(80.0, 140.0))
	var waves: Array[Vector3] = []  # amplitude, wavelength, phase
	for i in 3:
		waves.append(Vector3(rng.randf_range(15.0, 45.0), rng.randf_range(300.0, 900.0), rng.randf_range(0.0, TAU)))
	var coast: Array = []
	var y := height
	while y >= 0.0:
		var x := base
		for wave in waves:
			x += wave.x * sin(y / wave.y * TAU + wave.z)
		x += bay.y * exp(-pow((y - bay.x) / 220.0, 2.0))
		x -= cape.y * exp(-pow((y - cape.x) / 160.0, 2.0))
		coast.append([snappedf(clampf(x, 120.0, width * 0.4), 1.0), snappedf(y, 1.0)])
		y -= STEP
	var land: Array = [[width, height]]
	land.append_array(coast)
	land.append([width, 0.0])
	return {
		"name": "Generated %d" % seed_value,
		"land": land,
		"islands": _islands(rng, coast),
		"rivers": [_river(rng, coast, width, height)],
		"depth": {"shore": snappedf(rng.randf_range(10.5, 11.5), 0.1), "per_metre": 0.03, "max": 24.0},
	}


## The map `key` names: a key of rules.maps, or PREFIX and a seed.
static func of(rules: Dictionary, key: String) -> Dictionary:
	if key.begins_with(PREFIX):
		return make(int(key.trim_prefix(PREFIX)), rules.site)
	return rules.maps[key]


## A river from a point on the north or south edge, a third to two thirds
## across, winding to the coast in the same half, so the highway's row in
## the middle stays dry.
static func _river(rng: RandomNumberGenerator, coast: Array, width: float, height: float) -> Dictionary:
	var north := rng.randf() < 0.5
	var start := Vector2(rng.randf_range(0.45, 0.7) * width, 0.0 if north else height)
	var mouth_y := rng.randf_range(0.12, 0.32) * height if north else rng.randf_range(0.68, 0.88) * height
	var mouth := Vector2(_coast_x(coast, mouth_y) - 60.0, mouth_y)
	var points: Array = [[start.x, start.y]]
	for i in range(1, 4):
		var t := i / 4.0
		var at := start.lerp(mouth, t) + Vector2(0.0, rng.randf_range(-60.0, 60.0))
		at.y = clampf(at.y, 0.0, height * 0.42) if north else clampf(at.y, height * 0.58, height)
		points.append([snappedf(at.x, 1.0), snappedf(at.y, 1.0)])
	points.append([snappedf(mouth.x, 1.0), snappedf(mouth.y, 1.0)])
	return {"points": points, "width": snappedf(rng.randf_range(100.0, 150.0), 1.0), "depth": 7.0}


## Up to two islands well out from the coast.
static func _islands(rng: RandomNumberGenerator, coast: Array) -> Array:
	var islands: Array = []
	for i in rng.randi_range(0, 2):
		var y := rng.randf_range(300.0, 2100.0)
		var x := _coast_x(coast, y) - rng.randf_range(160.0, 260.0)
		if x < 120.0:
			continue
		var radius := rng.randf_range(40.0, 75.0)
		var points: Array = []
		for k in 7:
			var angle := k / 7.0 * TAU
			var r := radius * rng.randf_range(0.7, 1.0)
			points.append([snappedf(x + cos(angle) * r, 1.0), snappedf(y + sin(angle) * r, 1.0)])
		islands.append(points)
	return islands


## The coast's x at height `y`, between its points.
static func _coast_x(coast: Array, y: float) -> float:
	for i in range(1, coast.size()):
		var a: Array = coast[i - 1]
		var b: Array = coast[i]
		if (a[1] - y) * (b[1] - y) <= 0.0:
			return lerpf(a[0], b[0], (y - a[1]) / (b[1] - a[1]) if b[1] != a[1] else 0.0)
	return coast[0][0]
