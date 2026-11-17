class_name Services
extends RefCounted
## Ship services: bunkers, provisions and waste taken off. A ship wants each
## with its class's chance when it calls; service boats from a services
## jetty see to them while it lies at berth or at anchor, for a fee. Serving
## never delays a ship.


## The services a ship of `kind` wants this call, each with its class's chance.
static func wants(sim: PortSim, kind: String) -> Array[String]:
	var found: Array[String] = []
	var services: Dictionary = sim.rules.ship_classes[kind].services
	for service: String in services:
		if sim.rng.randf() < services[service].chance:
			found.append(service)
	return found


## Sends a free boat to each need of each ship it can serve now, finishes
## services whose time is up (the fee paid, the need met), and calls home a
## boat whose ship has sailed or moved on.
static func tick(sim: PortSim) -> void:
	var now := sim.clock.calendar_minutes()
	var by_id := {}
	for ship: PortSim.Ship in sim.ships:
		by_id[ship.id] = ship
	var busy := {}  # [ship id, service] -> a boat is on it
	for id: int in sim.boats.list:
		var boat: Dictionary = sim.boats.list[id]
		if boat.kind not in sim.rules.water.services.boats or boat.job not in ["out", "serve"]:
			continue
		var ship: PortSim.Ship = by_id.get(boat.ship)
		if ship == null or not _servable(ship) or boat.kind not in ship.needs:
			sim.boats.go_home(sim.areas, id, sim.marine_base_cell(boat.base), 0)
		elif boat.job == "serve" and now >= boat.until:
			sim.ledger.post("services", sim.rules.ship_classes[ship.kind].services[boat.kind].fee)
			ship.needs.erase(boat.kind)
			sim.boats.go_home(sim.areas, id, sim.marine_base_cell(boat.base), 0)
		else:
			busy[[ship.id, boat.kind]] = true
	for ship: PortSim.Ship in sim.ships:
		if not _servable(ship):
			continue
		for need: String in ship.needs:
			if [ship.id, need] in busy:
				continue
			var to := _where(sim, ship)
			var boat := _nearest_ready(sim, need, to)
			if boat == 0:
				continue
			var path := sim.boats.way(sim.areas, sim.boats.list[boat].at, to)
			if not path.is_empty():
				sim.boats.send(boat, path, "out", ship.id)


## A ship sailing: each need still unmet that the port offers (some jetty
## has a boat for it) costs its line unserved_reputation.
static func sailed(sim: PortSim, ship: PortSim.Ship) -> void:
	var offered := {}
	for id: int in sim.boats.list:
		if sim.boats.list[id].base in sim.service_jetties:
			offered[sim.boats.list[id].kind] = true
	for need: String in ship.needs:
		if need in offered:
			sim._event_if(sim.contracts.penalise(ship.line, -sim.rules.water.services.unserved_reputation))
			sim._event("%s's %s sailed without its %s" % [sim.contracts.name_of(ship.line), ship.kind, need])
	ship.needs.clear()


## Whether `ship` can be served now: alongside and working, or waiting at an
## anchorage.
static func _servable(ship: PortSim.Ship) -> bool:
	return ship.state == PortSim.Ship.State.WORKING or (ship.state == PortSim.Ship.State.ANCHORED and ship.anchorage != 0)


## Where a boat serving `ship` comes alongside it, in cells.
static func _where(sim: PortSim, ship: PortSim.Ship) -> Vector2:
	if ship.state == PortSim.Ship.State.WORKING:
		return Marine.alongside(sim, ship)
	return Marine.spots(sim, ship.anchorage)[ship.spot]


## The boat for `service` home at a services jetty nearest `to`, or 0.
static func _nearest_ready(sim: PortSim, service: String, to: Vector2) -> int:
	var best := 0
	for jetty: int in sim.service_jetties:
		for id: int in sim.boats.ready_at(jetty):
			if sim.boats.list[id].kind == service and (best == 0 or sim.boats.list[id].at.distance_to(to) < sim.boats.list[best].at.distance_to(to)):
				best = id
	return best
