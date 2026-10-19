class_name Handovers
extends RefCounted
## Who is at each area's handover slots, who waits in its buffer strip, and
## who queues on the road outside. A vehicle arriving takes the first free
## slot; with none free it waits in the buffer, which holds one vehicle per
## bay; with the buffer full it queues on the road. A freed slot goes to the
## first vehicle in the buffer, whose place goes to the first on the road.

var _areas: Areas
var _at := {}  # area id -> {"slots": vehicle id or 0 per slot, "buffer": ids, "road": ids}


func _init(areas: Areas) -> void:
	_areas = areas


## Books vehicle `id` into area `area`: "slot", "buffer" or "road".
func arrive(area: int, id: int) -> String:
	var at := _state(area)
	var free: int = at.slots.find(0)
	if free >= 0:
		at.slots[free] = id
		return "slot"
	if at.buffer.size() < _buffer_room(area):
		at.buffer.append(id)
		return "buffer"
	at.road.append(id)
	return "road"


## Frees vehicle `id`'s slot in `area` and moves the queues up.
func leave(area: int, id: int) -> void:
	var at := _state(area)
	var slot: int = at.slots.find(id)
	assert(slot >= 0, "vehicle %d leaves area %d without a slot" % [id, area])
	at.slots[slot] = at.buffer.pop_front() if not at.buffer.is_empty() else 0
	if not at.road.is_empty():
		at.buffer.append(at.road.pop_front())


## The slot vehicle `id` holds in `area`, or -1.
func slot_of(area: int, id: int) -> int:
	return _state(area).slots.find(id)


func waiting(area: int) -> Dictionary:
	var at := _state(area)
	return {"buffer": at.buffer.duplicate(), "road": at.road.duplicate()}


## Every holder of slot `slot` per area: {area id: [vehicle id or 0 per slot]}.
func slots() -> Dictionary:
	var found := {}
	for area: int in _at:
		found[area] = _at[area].slots.duplicate()
	return found


## Lets go of everything at an area that's gone.
func forget(area: int) -> void:
	_at.erase(area)


func to_dict() -> Dictionary:
	return _at.duplicate(true)


static func from_dict(d: Dictionary, areas: Areas) -> Handovers:
	var handovers := Handovers.new(areas)
	handovers._at = d.duplicate(true)
	return handovers


func _state(area: int) -> Dictionary:
	if area not in _at:
		var slots := []
		slots.resize(_areas.layout(area).slots.size())
		slots.fill(0)
		_at[area] = {"slots": slots, "buffer": [], "road": []}
	return _at[area]


## How many vehicles fit in `area`'s buffer strip: one per bay.
func _buffer_room(area: int) -> int:
	return _areas.layout(area).buffer.size() / AreaLayout.BAY
