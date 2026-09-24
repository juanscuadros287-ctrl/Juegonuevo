class_name LogisticsSim
extends RefCounted
## Fase 6 — recursos por región, yacimientos, recetas de producción, transporte interno (a pie / caballos), carreteras y rutas manuales/automáticas.
## (Esqueleto de integración: el estado vive en GameState.logistics y se guarda automáticamente.)


static func init_state(gs) -> void:
	if gs.logistics.is_empty():
		gs.logistics = {}


static func daily(_gs) -> void:
	pass


static func monthly(_gs) -> void:
	pass
