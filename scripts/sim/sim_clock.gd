class_name SimClock
extends RefCounted
## The sim's two clocks, both driven by one tick count. Vehicles move in
## vehicle seconds (20 ticks each); the calendar (ship schedules, crane work,
## later dwell and contracts) runs in game minutes, one game hour per 60 s at 1x.

const TICKS_PER_SECOND := 20
const TICK_SECONDS := 1.0 / TICKS_PER_SECOND
const CALENDAR_MINUTES_PER_TICK := 0.05
const MINUTES_PER_DAY := 1440
const TICKS_PER_DAY := 28800  # MINUTES_PER_DAY / CALENDAR_MINUTES_PER_TICK

var ticks := 0


func tick() -> void:
	ticks += 1


## Derived from the tick count so it never drifts.
func calendar_minutes() -> float:
	return ticks * CALENDAR_MINUTES_PER_TICK


func game_day() -> int:
	return floori(calendar_minutes() / MINUTES_PER_DAY)


func game_hour() -> int:
	return floori(calendar_minutes() / 60.0) % 24


## Whole ticks in `accumulated` seconds of play, at most `max_ticks`. The caller
## carries the remainder into the next frame and drops time beyond the cap.
static func ticks_for(accumulated: float, max_ticks: int) -> int:
	return mini(floori(accumulated / TICK_SECONDS), max_ticks)
