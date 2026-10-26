#include "lane_cells.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>

using namespace godot;

static LocalVector<Vector2i> to_cells(const Array &p_cells) {
	LocalVector<Vector2i> cells;
	cells.reserve(p_cells.size());
	for (int64_t k = 0; k < p_cells.size(); k++) {
		cells.push_back(p_cells[k]);
	}
	return cells;
}

static bool contains(const LocalVector<Vector2i> &p_cells, const Vector2i &p_cell) {
	for (const Vector2i &cell : p_cells) {
		if (cell == p_cell) {
			return true;
		}
	}
	return false;
}

// Takes all of `cells` for `id` if each is free or already theirs, else none.
bool LaneCells::take_cells(int64_t p_id, const LocalVector<Vector2i> &p_cells) {
	for (const Vector2i &cell : p_cells) {
		const int64_t *who = holders.getptr(cell);
		if (who && *who != p_id) {
			return false;
		}
	}
	if (!held.has(p_id)) {
		held.insert(p_id, LocalVector<Vector2i>());
	}
	LocalVector<Vector2i> &mine = held[p_id];
	for (const Vector2i &cell : p_cells) {
		if (!contains(mine, cell)) {
			mine.push_back(cell);
		}
		holders[cell] = p_id;
	}
	return true;
}

// Keeps only `cells` of what `id` holds, in the order held, letting go of the rest.
static void keep_only(HashMap<Vector2i, int64_t> &r_holders, LocalVector<Vector2i> &r_mine, const LocalVector<Vector2i> &p_cells) {
	LocalVector<Vector2i> kept;
	for (const Vector2i &other : r_mine) {
		if (contains(p_cells, other)) {
			kept.push_back(other);
		} else {
			r_holders.erase(other);
		}
	}
	r_mine = kept;
}

// Takes path[i], and if it is a junction cell, every junction cell after it
// and the first cell past them too; then lets go of every other cell.
bool LaneCells::enter(int64_t p_id, const Array &p_path, int64_t p_i, const Dictionary &p_junctions) {
	const Vector2i cell = p_path[p_i];
	const int64_t *who = holders.getptr(cell);
	if (who && *who != p_id) {
		return false;
	}
	if (!p_junctions.has(cell)) {
		// A plain lane cell: hold just it, as the general case below would.
		LocalVector<Vector2i> &mine = held[p_id];
		for (const Vector2i &other : mine) {
			if (other != cell) {
				holders.erase(other);
			}
		}
		mine.clear();
		mine.push_back(cell);
		holders[cell] = p_id;
		return true;
	}
	LocalVector<Vector2i> want;
	want.push_back(cell);
	int64_t j = p_i;
	while (p_junctions.has(p_path[j]) && j + 1 < p_path.size()) {
		j += 1;
		want.push_back(p_path[j]);
	}
	if (!take_cells(p_id, want)) {
		return false;
	}
	keep_only(holders, held[p_id], want);
	return true;
}

bool LaneCells::take(int64_t p_id, const Array &p_cells) {
	return take_cells(p_id, to_cells(p_cells));
}

// Books exactly `cells`, letting go of the rest, if each is free or theirs.
bool LaneCells::rebook(int64_t p_id, const Array &p_cells) {
	const LocalVector<Vector2i> cells = to_cells(p_cells);
	if (!take_cells(p_id, cells)) {
		return false;
	}
	keep_only(holders, held[p_id], cells);
	return true;
}

void LaneCells::release(int64_t p_id) {
	LocalVector<Vector2i> *mine = held.getptr(p_id);
	if (!mine) {
		return;
	}
	for (const Vector2i &cell : *mine) {
		holders.erase(cell);
	}
	held.erase(p_id);
}

int64_t LaneCells::holder(const Vector2i &p_cell) const {
	const int64_t *who = holders.getptr(p_cell);
	return who ? *who : 0;
}

Array LaneCells::held_by(int64_t p_id) const {
	Array cells;
	const LocalVector<Vector2i> *mine = held.getptr(p_id);
	if (mine) {
		for (const Vector2i &cell : *mine) {
			cells.push_back(cell);
		}
	}
	return cells;
}

// One tick of a vehicle moving up to `step` cells along `path` from `t`,
// entering each cell in turn: returns [t, waited, 1 if at the route's end].
PackedFloat64Array LaneCells::advance(int64_t p_id, const Array &p_path, double p_t, double p_step, int64_t p_waited, const Dictionary &p_junctions) {
	const double last = double(p_path.size() - 1);
	const double target = std::min(p_t + p_step, last);
	const int64_t start = int64_t(p_t);
	double t = p_t;
	PackedFloat64Array result;
	result.resize(3);
	while (int64_t(target) > int64_t(t)) {
		const int64_t i = int64_t(t);
		if (!enter(p_id, p_path, i + 1, p_junctions)) {
			result[0] = std::max(t, double(i) + 0.95);
			// Waiting counts only ticks it entered no cell at all.
			result[1] = double(i == start ? p_waited + 1 : 0);
			result[2] = 0.0;
			return result;
		}
		t = double(i + 1);
	}
	result[0] = target;
	result[1] = 0.0;
	result[2] = target >= last ? 1.0 : 0.0;
	return result;
}

Dictionary LaneCells::to_dict() const {
	Dictionary d;
	for (const KeyValue<int64_t, LocalVector<Vector2i>> &entry : held) {
		Array cells;
		for (const Vector2i &cell : entry.value) {
			cells.push_back(cell);
		}
		d[entry.key] = cells;
	}
	return d;
}

void LaneCells::load(const Dictionary &p_held) {
	holders.clear();
	held.clear();
	const Array ids = p_held.keys();
	for (int64_t k = 0; k < ids.size(); k++) {
		const int64_t id = ids[k];
		const LocalVector<Vector2i> cells = to_cells(p_held[ids[k]]);
		held.insert(id, cells);
		for (const Vector2i &cell : cells) {
			holders[cell] = id;
		}
	}
}

void LaneCells::_bind_methods() {
	ClassDB::bind_method(D_METHOD("take", "id", "cells"), &LaneCells::take);
	ClassDB::bind_method(D_METHOD("rebook", "id", "cells"), &LaneCells::rebook);
	ClassDB::bind_method(D_METHOD("release", "id"), &LaneCells::release);
	ClassDB::bind_method(D_METHOD("holder", "cell"), &LaneCells::holder);
	ClassDB::bind_method(D_METHOD("held_by", "id"), &LaneCells::held_by);
	ClassDB::bind_method(D_METHOD("advance", "id", "path", "t", "step", "waited", "junctions"), &LaneCells::advance);
	ClassDB::bind_method(D_METHOD("to_dict"), &LaneCells::to_dict);
	ClassDB::bind_method(D_METHOD("load", "held"), &LaneCells::load);
}
