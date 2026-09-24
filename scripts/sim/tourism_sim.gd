class_name TourismSim
extends RefCounted
## Fase 8 — turismo (atracciones con entrada, turistas por las conexiones).
## (Esqueleto de integración: el estado vive en GameState.tourism y se guarda automáticamente.)


static func init_state(gs) -> void:
	if gs.tourism.is_empty():
		gs.tourism = {}


static func daily(_gs) -> void:
	pass


static func monthly(_gs) -> void:
	pass
