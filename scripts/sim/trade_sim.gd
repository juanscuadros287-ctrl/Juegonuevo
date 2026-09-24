class_name TradeSim
extends RefCounted
## Fase 7 — otros pueblos, rutas comerciales pagadas por pueblo, exportación/importación, inmigración y evolución del transporte.
## (Esqueleto de integración: el estado vive en GameState.trade y se guarda automáticamente.)


static func init_state(gs) -> void:
	if gs.trade.is_empty():
		gs.trade = {}


static func daily(_gs) -> void:
	pass


static func monthly(_gs) -> void:
	pass


## Pueblos conectados por ruta comercial: Array de Dictionary {"town_id", ...}.
## Contrato para otras fases: gs.trade["connections"].
static func connected_towns(gs) -> Array:
	return gs.trade.get("connections", [])


static func is_connected_any(gs) -> bool:
	return not connected_towns(gs).is_empty()
