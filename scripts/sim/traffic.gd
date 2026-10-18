class_name Traffic
extends RefCounted
## Which vehicle holds each lane. A road tile has one lane per direction of
## travel, so traffic passes both ways on a one-tile road. A junction (a road
## tile with three or more road neighbours) is one shared spot, so crossing
## traffic never meets in it. A vehicle enters a tile only once it holds the
## lane, so no two vehicles are ever in the same lane.

const JUNCTION := 4
## Held by vehicles off the road: under a crane or in a yard block's bay.
const NO_LANE := Vector3i(-1, -1, -1)

var _holders := {}


## The lane a vehicle on `path[i]` uses, heading to `path[i + 1]` (or, at the
## end of the path, still heading the way it came).
static func lane(map: PortMap, path: Array[Vector2i], i: int) -> Vector3i:
	var cell := path[i]
	if _is_junction(map, cell):
		return Vector3i(cell.x, cell.y, JUNCTION)
	var heading := Vector2i.RIGHT
	if i + 1 < path.size():
		heading = path[i + 1] - cell
	elif i > 0:
		heading = cell - path[i - 1]
	return Vector3i(cell.x, cell.y, PortMap.SIDES.find(heading))


static func _is_junction(map: PortMap, cell: Vector2i) -> bool:
	var roads := 0
	for side: Vector2i in PortMap.SIDES:
		if map.tile(cell + side) == PortMap.Tile.ROAD:
			roads += 1
	return roads >= 3


## Takes `lane` for `id` if it is free (or already theirs).
func claim(lane_key: Vector3i, id: int) -> bool:
	if _holders.get(lane_key, id) != id:
		return false
	_holders[lane_key] = id
	return true


func release(lane_key: Vector3i, id: int) -> void:
	if _holders.get(lane_key) == id:
		_holders.erase(lane_key)


func holder(lane_key: Vector3i) -> int:
	return _holders.get(lane_key, 0)
