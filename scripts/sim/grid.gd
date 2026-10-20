class_name Grid
extends RefCounted
## The 4 m grid the road and area model works on: one cell is about one lane
## wide. Sizes in the data are in metres and must be whole cells; the view
## places things in metres from a cell's centre.

const CELL := 4
## No cell: where a vehicle has nowhere set to go.
const NONE := Vector2i(-1, -1)


static func cells(metres: int) -> int:
	return metres / CELL


static func metres(cell_count: int) -> int:
	return cell_count * CELL


## The site's size in cells, from the data's "site" record.
static func size(site: Dictionary) -> Vector2i:
	return Vector2i(cells(site.width), cells(site.height))


## Where `cell`'s centre is in the world, in metres.
static func centre(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * CELL, 0.0, (cell.y + 0.5) * CELL)
