class_name ScenarioSim
extends RefCounted
## Escenarios de inicio (docs/MISIONES_ESCENARIOS.md). Se eligen al crear la partida
## (settings["scenario"]); las partidas viejas quedan en "normal". Datos en data/progreso.json → scenarios.
##   normal      la partida de siempre (no cambia nada: misma semilla, mismo pueblo).
##   pobre       15 % del capital y puntaje de crédito 590.
##   quebrada    heredas una granja y un préstamo del banco externo en mora (2 cuotas atrasadas), que se
##               negocia con CreditSim (plazo, rebaja, dación o gracia). La deuda es de antes de empezar:
##               se registra el préstamo sin mover dinero (nadie gana ni pierde nada al crearlo).
##   otro_pais   emigras al país elegido en el mapa mundial: 70 % de tus ahorros, sin historial local.
##   industrial  1830, época 2, con todas las tecnologías de la época colonial.
##   moderna     1950, época 3, con las tecnologías colonial e industrial.
## El capital inicial es parte del estado de partida (como hasta ahora), no un pago.

const INHERITED_PURPOSE := "herencia_quiebra"


static func defs() -> Dictionary:
	return ProgressSim.cfg().get("scenarios", {})


static func ids() -> Array:
	return GameData.sorted_ids(defs())


static func def(id: String) -> Dictionary:
	return defs().get(id, {})


static func current(gs) -> String:
	return str(gs.settings.get("scenario", "normal"))


static func label(id: String) -> String:
	return str(def(id).get("label", id))


## Antes de crear población y gobierno: año de inicio, época y tecnologías base.
static func apply_early(gs) -> void:
	var sc := def(current(gs))
	if sc.has("start_year"):
		gs.settings["start_year"] = int(sc["start_year"])
	var target := int(sc.get("era", 1))
	if target > 1:
		var ids_: Array = GameData.technologies.keys()
		ids_.sort()
		for id in ids_:
			var tv = GameData.technologies[id]
			if not (tv is Dictionary) or str(id).begins_with("_"):
				continue
			var t: Dictionary = tv
			if int(t.get("era", 1)) < target and not gs.techs.has(id):
				gs.techs.append(id)
		gs.research["era"] = target
		TechSim._recompute_mods(gs)


## Al final de new_game: capital, crédito, empresa y deuda heredadas.
static func apply_late(gs) -> void:
	var id := current(gs)
	var sc := def(id)
	if id == "normal" or sc.is_empty():
		return
	if sc.has("money_mult"):
		gs.money = snappedf(gs.money * float(sc["money_mult"]), 1.0)
	if sc.has("credit_score"):
		CreditSim._rec(gs, "jugador")["score"] = float(sc["credit_score"])
	var p: Citizen = gs.player_citizen()
	if p != null:
		var sb: Dictionary = sc.get("skill_bonus", {})
		for k in sb:
			p.skills[k] = minf(100.0, float(p.skills.get(k, 0.0)) + float(sb[k]))
	match id:
		"quebrada":
			_inherit_business(gs, sc)
		"otro_pais":
			gs.notify("Emigraste a %s: nadie te conoce en el banco, pero sabes de comercio. Mira la tarjeta del país en el mapa mundial." % MapSim.country_def(MapSim.country_id(gs)).get("label", "tu nuevo país"), "importante")
		"industrial", "moderna":
			gs.notify("Empiezas en %d, en la %s: ya conoces %d tecnologías." % [TimeManager.year(), GameData.era_label(gs.era()), gs.techs.size()], "importante")
		"pobre":
			gs.notify("Llegas con lo puesto: %s. Busca un trabajo o un negocio pequeño para empezar." % Fmt.money(gs.money), "importante")


static func _inherit_business(gs, sc: Dictionary) -> void:
	var type_id := str(sc.get("business", "granja"))
	var spot := _free_spot(gs, type_id)
	if spot != Vector2.INF:
		var b: Dictionary = ConstructionSim.make_building(gs, type_id, 1, spot.x, spot.y, atan2(-spot.x, -spot.y), "jugador")
		b["name"] = str(sc.get("business_name", "Negocio heredado"))
		b["inherited"] = true
		# Valor de la empresa (patrimonio, dación en pago): lo que costó levantarla, como una obra propia.
		b["ledger"]["total"]["obras"] = snappedf(float(GameData.level_def(type_id, 1).get("cost", 500)) * gs.price_mult(), 1.0)
		gs.add_building(b)
		HiringSim.on_building_ready(gs, b)
	var debt := snappedf(float(gs.diff().get("start_money", 8000)) * float(sc.get("debt_mult", 1.6)) * gs.price_mult(), 1.0)
	var l := BankSim._new_loan(gs, BankSim.EXTERNAL, "jugador", debt, float(sc.get("debt_rate", 0.13)), int(sc.get("debt_months", 36)), INHERITED_PURPOSE)
	l["type"] = "frances"
	l["missed"] = int(sc.get("missed", 2))
	l["months_paid"] = 4
	l["inherited"] = true
	gs.notify("Heredaste %s con una deuda de %s en mora (%d cuotas atrasadas, cuota %s). Negocia en Finanzas antes de que el banco embargue." % [
		str(sc.get("business_name", "la empresa familiar")), Fmt.money(debt), int(l["missed"]), Fmt.money(float(l["payment"]))], "jugador")


static func _free_spot(gs, type_id: String) -> Vector2:
	for ring in range(8):
		var r := 14.0 + ring * 4.0
		for k in range(16):
			var ang := TAU * float(k) / 16.0 + ring * 0.37
			var pos := Vector2(cos(ang), sin(ang)) * r
			if ConstructionSim.placement_block_reason(gs, type_id, pos.x, pos.y) == "":
				return pos
	return Vector2.INF


## El préstamo heredado (o {} si ya se pagó o negoció hasta cerrarlo).
static func inherited_loan(gs) -> Dictionary:
	for l in gs.loans:
		if str(l.get("purpose", "")) == INHERITED_PURPOSE:
			return l
	return {}
