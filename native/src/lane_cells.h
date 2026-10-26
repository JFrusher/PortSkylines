#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace godot {

// Who holds each lane cell, and the cells each vehicle holds, for
// LaneTraffic (scripts/sim/lane_traffic.gd), which keeps the rules in its
// comments. The maps keep insertion order, as GDScript dictionaries do, so
// to_dict() and with it the sim's state hash come out exactly as before.
class LaneCells : public RefCounted {
	GDCLASS(LaneCells, RefCounted)

	HashMap<Vector2i, int64_t> holders;
	HashMap<int64_t, LocalVector<Vector2i>> held;

	bool take_cells(int64_t p_id, const LocalVector<Vector2i> &p_cells);
	bool enter(int64_t p_id, const Array &p_path, int64_t p_i, const Dictionary &p_junctions);

protected:
	static void _bind_methods();

public:
	bool take(int64_t p_id, const Array &p_cells);
	bool rebook(int64_t p_id, const Array &p_cells);
	void release(int64_t p_id);
	int64_t holder(const Vector2i &p_cell) const;
	Array held_by(int64_t p_id) const;
	PackedFloat64Array advance(int64_t p_id, const Array &p_path, double p_t, double p_step, int64_t p_waited, const Dictionary &p_junctions);
	Dictionary to_dict() const;
	void load(const Dictionary &p_held);
};

} // namespace godot
