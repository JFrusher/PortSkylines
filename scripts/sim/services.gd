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
