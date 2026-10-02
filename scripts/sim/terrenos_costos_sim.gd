class_name TerrenosCostosSim
extends RefCounted
## Orquesta los sistemas de docs/TERRENOS_COSTOS.md (un solo gancho en GameState):
##   LandPortfolioSim (Mis terrenos), TransportDivSim (división o empresa de transporte), CostSim (costeo por
##   fábrica), PriceHistorySim (historial de precios), NegotiationSim y AgencySim (inmobiliaria, sección H).
## Estado nuevo (con valores por defecto, partidas viejas incluidas): map.land_pf, economy.transport,
## economy.price_hist, economy.costing_goods y claves por edificio (costing, cost_hist, transport_org…).


static func init_state(gs) -> void:
	LandPortfolioSim.init_state(gs)
	TransportDivSim.st(gs)
	PriceHistorySim.st(gs)
	if not (gs.economy.get("costing_goods") is Dictionary):
		gs.economy["costing_goods"] = {}


## Al final del día (después de producir, despachar envíos y vender).
static func daily(gs) -> void:
	TransportDivSim.daily(gs)
	CostSim.daily(gs)
	LandPortfolioSim.daily(gs)


## Cierre mensual (después de BusinessSim.monthly y EconomySim.monthly).
static func monthly(gs) -> void:
	TransportDivSim.monthly(gs)
	CostSim.monthly(gs)
	LandPortfolioSim.monthly(gs)
	PriceHistorySim.monthly(gs)
