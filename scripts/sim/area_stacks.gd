class_name AreaStacks
extends RefCounted
## The boxes stacked in one yard area. Each stack position (a row and bay
## from its layout) holds tiers from the ground up; a tier is one 40 ft box
## or up to two 20 ft boxes side by side. A 40 ft box never rests on a tier
## with 20s. Taking out a buried box first moves every box above it to other
## stacks: rehandles, each a machine move. In quiet periods housekeeping moves
## boxes so the ones leaving sooner end up on top.

## Stack position -> tiers from the ground up, each an array of box ids.
var stacks: Array = []
var _tiers: int
var _teu := {}  # box id -> 1 or 2
var _where := {}  # box id -> stack position


## `positions` stack positions, `tiers` high.
func _init(positions: int, tiers: int) -> void:
	_tiers = tiers
	for i in positions:
		stacks.append([])


## Puts box `id` of `teu` on the first stack that takes it, in layout order.
## Returns the position, or -1 when the area is full for it.
func place(id: int, teu: int) -> int:
	for position in stacks.size():
		if fits(position, teu):
			place_at(position, id, teu)
			return position
	return -1


## Whether a box of `teu` can go on top of `position`.
func fits(position: int, teu: int) -> bool:
	var tiers: Array = stacks[position]
	if teu == 1 and not tiers.is_empty() and tiers[-1].size() == 1 and _teu[tiers[-1][0]] == 1:
		return true  # beside a lone 20 ft box
	if tiers.size() >= _tiers:
		return false
	return teu == 1 or tiers.is_empty() or _teu[tiers[-1][0]] == 2


## The first stack position a box of `teu` fits on, in layout order, or -1.
func place_spot(teu: int) -> int:
	for position in stacks.size():
		if fits(position, teu):
			return position
	return -1


func place_at(position: int, id: int, teu: int) -> void:
	assert(fits(position, teu), "box %d doesn't fit on stack %d" % [id, position])
	_teu[id] = teu
	_where[id] = position
	var tiers: Array = stacks[position]
	if teu == 1 and not tiers.is_empty() and tiers[-1].size() == 1 and _teu[tiers[-1][0]] == 1:
		tiers[-1].append(id)
	else:
		tiers.append([id])


## How many boxes sit above box `id`: the rehandles taking it out costs.
func above(id: int) -> int:
	var tiers: Array = stacks[_where[id]]
	var level := tiers.find_custom(func(t: Array) -> bool: return id in t)
	var count := 0
	for tier in range(level + 1, tiers.size()):
		count += tiers[tier].size()
	return count


## Takes box `id` out, first moving each box above it to another stack.
## Returns the rehandles made, or -1 if a box above had nowhere to go.
func take(id: int) -> int:
	var position: int = _where[id]
	var moved := 0
	while above(id) > 0:
		var top: int = stacks[position][-1][-1]
		var teu: int = _teu[top]
		var to := _other_stack(position, teu)
		if to < 0:
			return -1
		_remove_top(position)
		place_at(to, top, teu)
		moved += 1
	# Nothing is above its tier now; a 20 ft box beside it stays.
	var tiers: Array = stacks[position]
	tiers[-1].erase(id)
	if tiers[-1].is_empty():
		tiers.pop_back()
	_teu.erase(id)
	_where.erase(id)
	return moved


## One housekeeping move: the top box of the first stack where it buries a
## box leaving sooner (by `due`, box id -> minute) moves to a stack where it
## buries nothing due before it. Returns whether a box moved.
func housekeep(due: Dictionary) -> bool:
	for position in stacks.size():
		var tiers: Array = stacks[position]
		if tiers.size() < 2:
			continue
		var top: int = tiers[-1][-1]
		var below := _boxes(position).filter(func(b: int) -> bool: return b != top)
		if not below.any(func(b: int) -> bool: return due[b] < due[top]):
			continue
		for to in stacks.size():
			if to != position and fits(to, _teu[top]) and not _boxes(to).any(func(b: int) -> bool: return due[b] < due[top]):
				var teu: int = _teu[top]
				_remove_top(position)
				place_at(to, top, teu)
				return true
	return false


func to_dict() -> Dictionary:
	return {"stacks": stacks.duplicate(true), "tiers": _tiers, "teu": _teu.duplicate(), "where": _where.duplicate()}


static func from_dict(d: Dictionary) -> AreaStacks:
	var area := AreaStacks.new(0, d.tiers)
	area.stacks = d.stacks.duplicate(true)
	area._teu = d.teu.duplicate()
	area._where = d.where.duplicate()
	return area


## How many more boxes fit, counting 40 ft places: a rough room check before
## a tractor is sent, not a promise of a spot.
func room() -> int:
	var free := 0
	for position in stacks.size():
		free += _tiers - stacks[position].size()
	return free


## Every box in the area.
func boxes() -> Array:
	return _where.keys()


func _boxes(position: int) -> Array:
	var found := []
	for tier: Array in stacks[position]:
		found.append_array(tier)
	return found


func _other_stack(position: int, teu: int) -> int:
	for to in stacks.size():
		if to != position and fits(to, teu):
			return to
	return -1


func _remove_top(position: int) -> void:
	var tiers: Array = stacks[position]
	var top: int = tiers[-1].pop_back()
	_where.erase(top)
	if tiers[-1].is_empty():
		tiers.pop_back()
