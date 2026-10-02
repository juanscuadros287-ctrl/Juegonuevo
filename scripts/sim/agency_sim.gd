class_name AgencySim
extends RefCounted
## Sección H de docs/PENDIENTES.md — Inmobiliaria como compañía especializada.
## - Los proyectos inmobiliarios (apartamentos, edificios, rascacielos: RealEstateSim) exigen tener una
##   inmobiliaria activa (negocio "inmobiliaria"). El proyecto queda a su nombre (b["agency_id"]).
## - Desde ella: comprar un territorio del Estado a nombre de la empresa (el pago queda en su libro como
##   inversión y el predial lo paga ella) y ver las opciones de proyectos (casas, apartamentos, edificios) con
##   presupuesto, precio aproximado de venta y renta por unidad y rentabilidad.
## - Los apartamentos se venden 1 a 1 según la demanda (RealEstateSim._market) y pasan a ser del comprador.
## - Recomprar un apartamento vendido exige negociar con su dueño (NegotiationSim): unos piden alto, otros bajo y
##   otros no quieren vender. Si acepta, la familia se queda como inquilina (renta sugerida).


static func cfg() -> Dictionary:
	return GameData.extra("terrenos_costos").get("agency", {})


static func type_id() -> String:
	return str(cfg().get("type", "inmobiliaria"))


static func agencies(gs, active_only := true) -> Array:
	return gs.buildings.filter(func(b): return gs.owned_by_player(b) and str(b.get("type", "")) == type_id() and (not active_only or gs.is_active(b)))


static func main_agency(gs) -> Dictionary:
	var a := agencies(gs)
	return a[0] if not a.is_empty() else {}


## "" si puede hacer proyectos inmobiliarios.
static func block_reason(gs) -> String:
	if not GameData.businesses.has(type_id()):
		return ""
	if agencies(gs).is_empty():
		return "Necesitas una inmobiliaria activa (Construir → Inmobiliaria)"
	return ""


## Territorios del Estado que la inmobiliaria puede comprar (revelados, vecinos de tus terrenos o en tus municipios).
static func land_options(gs, limit := 8) -> Array:
	var g := MapSim.gen(gs)
	var mine := {}
	for z in gs.unlocked_zones:
		mine[MapSim.chunk_of_zone(int(z[0]), int(z[1]))] = true
	var cand := {}
	for c in mine:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var cc: Vector2i = c + Vector2i(dx, dy)
				if not mine.has(cc) and g.in_country_chunk(cc.x, cc.y):
					cand[cc] = true
	var out := []
	for cc in cand:
		if LandSim.buy_block_reason(gs, cc.x, cc.y, "fijo") == "Dinero insuficiente (%s)" % Fmt.money(LandSim.remaining_price(gs, cc.x, cc.y)) \
				or LandSim.buy_block_reason(gs, cc.x, cc.y, "fijo") == "":
			out.append({"cx": cc.x, "cy": cc.y, "price": LandSim.remaining_price(gs, cc.x, cc.y),
				"municipio": MunicipalSim.name_of(gs, g.zone_index(cc.x, cc.y)), "reason": LandSim.buy_block_reason(gs, cc.x, cc.y, "fijo")})
	out.sort_custom(func(a, b): return float(a["price"]) < float(b["price"]))
	return out.slice(0, limit)


## Compra un territorio del Estado a nombre de la inmobiliaria.
static func buy_land(gs, agency: Dictionary, cx: int, cy: int) -> String:
	if agency.is_empty() or not gs.owned_by_player(agency) or str(agency.get("type", "")) != type_id():
		return "Elige una inmobiliaria tuya"
	var price := LandSim.remaining_price(gs, cx, cy)
	var why := LandSim.buy_from_state(gs, cx, cy)
	if why != "":
		return why
	BusinessSim.ledger_add(agency, "obras", price)   # Inversión de la empresa (el dinero ya salió con la compra).
	LandPortfolioSim.sync(gs)
	var lot: Dictionary = LandPortfolioSim.st(gs)["lots"].get(LandPortfolioSim.key(cx, cy), {})
	if not lot.is_empty():
		lot["company"] = int(agency["id"])
	gs.notify("%s compró el territorio (%d, %d) a nombre de la empresa por %s." % [gs.building_label(agency), cx, cy, Fmt.money(price)], "negocio")
	return ""


## Opciones de proyectos: [{level, label, units, budget, unit_price, unit_rent, margin, yield, kind}].
static func project_options(gs, tier := "normal") -> Array:
	var out := []
	for lvl in range(1, GameData.max_level("vivienda") + 1):
		var ld := GameData.level_def("vivienda", lvl)
		if ld.is_empty():
			continue
		var cost := ConstructionSim.cost_for(gs, "vivienda", lvl, false, tier)
		var budget := float(cost["total"])
		var row := {"level": lvl, "label": str(ld.get("label", "Vivienda %d" % lvl)), "budget": budget, "days": int(cost["days"]),
			"blocked": ConstructionSim.level_block_reason(gs, "vivienda", lvl)}
		if RealEstateSim.is_multi_level(lvl):
			var f := RealEstateSim.feasibility(gs, lvl, tier)
			var units := RealEstateSim.layout(lvl).size()
			var sale := float(f["sales_total"])
			var rent := float(f["rent_total"])
			row.merge({"kind": "apartamentos", "units": units, "unit_price": sale / maxf(1, units), "unit_rent": rent / maxf(1, units),
				"sale_total": sale, "rent_total": rent, "margin": (sale - budget) / maxf(1.0, budget), "yield": rent * 12.0 / maxf(1.0, budget)})
		else:
			var td := Housing.tier_def_by_id(tier)
			var sale: float = float(ld.get("sale_price", 0.0)) * float(td.get("sale_mult", 1.0)) * gs.price_level() * GlobalEconSim.property_mult(gs)
			var rent: float = float(ld.get("rent", 0.0)) * float(td.get("rent_mult", 1.0)) * gs.price_level() * float(GameData.capacity("vivienda", lvl, tier))
			row.merge({"kind": "casa", "units": 1, "unit_price": sale, "unit_rent": rent, "sale_total": sale, "rent_total": rent,
				"margin": (sale - budget) / maxf(1.0, budget), "yield": rent * 12.0 / maxf(1.0, budget)})
		out.append(row)
	return out


# --- Recompra negociada de apartamentos ------------------------------------------------------------------

static func unit_value(gs, b: Dictionary, u: Dictionary) -> float:
	var prices := RealEstateSim.unit_prices(gs, int(b["level"]), str(b.get("tier", "normal")))
	var i := int(u.get("id", 1)) - 1
	return float(prices[i]["price"]) if i >= 0 and i < prices.size() else float(u.get("price", 0.0))


static func unit_key(b: Dictionary, u: Dictionary) -> String:
	return "unit:%d:%d" % [int(b["id"]), int(u.get("id", 0))]


## Lo que dice el dueño si le preguntas (sin compromiso): {kind, label, ask}.
static func ask_unit(gs, b: Dictionary, u: Dictionary) -> Dictionary:
	if str(u.get("status", "")) != "vendida":
		return {}
	return NegotiationSim.profile(gs, unit_key(b, u), unit_value(gs, b, u), int(u.get("owner_id", -1)), int(u.get("sold_day", -1)))


## Oferta para recomprar una unidad vendida. Devuelve {ok, text, counter}.
static func rebuy_unit(gs, b: Dictionary, u: Dictionary, amount: float) -> Dictionary:
	if str(u.get("status", "")) != "vendida" or not gs.owned_by_player(b):
		return {"ok": false, "text": "Esa unidad no es de un comprador", "counter": 0.0}
	if gs.money < amount:
		return {"ok": false, "text": "Dinero insuficiente (%s)" % Fmt.money(amount), "counter": 0.0}
	var owner: Citizen = gs.citizens.get(int(u.get("owner_id", -1)))
	if owner == null:
		return {"ok": false, "text": "El dueño ya no está", "counter": 0.0}
	var r := NegotiationSim.respond(gs, unit_key(b, u), unit_value(gs, b, u), owner.id, amount, int(u.get("sold_day", -1)))
	if not bool(r["ok"]):
		return r
	BusinessSim.pay(gs, b, amount, "obras")
	owner.money += amount
	var members := RealEstateSim._members_of(gs, u.get("household", [owner.id]))
	if members.is_empty():
		members = [owner]
	RealEstateSim._rent_to(gs, u, members)
	u["for_sale"] = false
	gs.notify("Recompraste el apartamento %s de %s a %s por %s; su familia se queda como inquilina." % [u.get("code", ""), gs.building_label(b), owner.full_name(), Fmt.money(amount)], "negocio")
	return r
