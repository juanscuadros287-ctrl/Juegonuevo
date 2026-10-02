class_name CostSim
extends RefCounted
## Costeo por fábrica (pedido: "saber un aproximado de cada fábrica, porque hay que pagar transporte, sueldos y
## eso"). Cada mes, para cada negocio productor tuyo, el costo por unidad producida desglosado en:
##   insumos      receta × unidades a precio real (lo que te cuesta producirlo si lo haces tú el mes anterior;
##                si no, precio de mercado) + materiales por unidad (unit_cost)
##   sueldos      salarios (formales y en negro)
##   mant_energia mantenimiento + reparaciones + electricidad (insumos del libro que no son materiales ni compras)
##   transporte   fletes cobrados por tu empresa de transporte + costo asignado de la división interna
##   depreciacion obras invertidas / (20 años × 12)
##   impuestos    renta, propiedad, nómina, IVA y multas pagados en el mes
## total = suma del desglose (la prueba lo exige). Además: precio de venta promedio, margen por unidad y punto
## de equilibrio (unidades/mes). Resultado en b["costing"] e historial b["cost_hist"].
## La "Calculadora de fábrica" (estimate) hace lo mismo ANTES de construir, a plantilla completa con los
## precios de hoy y los mejores candidatos disponibles (productividad y sueldo que piden).

const PARTS := ["insumos", "sueldos", "mant_energia", "transporte", "depreciacion", "impuestos"]
const PART_LABELS := {"insumos": "Insumos", "sueldos": "Sueldos", "mant_energia": "Mantenimiento y energía",
	"transporte": "Transporte", "depreciacion": "Depreciación", "impuestos": "Impuestos"}
const SKIP_PRODUCTS := ["", "credito", "educacion", "servicio", "transporte", "investigacion", "construccion"]


static func cfg() -> Dictionary:
	return GameData.extra("terrenos_costos").get("costing", {})


static func product_of(def: Dictionary) -> String:
	return str(def.get("product", ""))


static func is_producer_def(def: Dictionary) -> bool:
	var p := product_of(def)
	if str(def.get("category", "")) != "negocio" or p in SKIP_PRODUCTS or bool(def.get("shop", false)):
		return false
	return GameData.goods.has(p) and not bool(GameData.goods[p].get("internal", false))


static func producers(gs) -> Array:
	return gs.buildings.filter(func(b): return gs.owned_by_player(b) and is_producer_def(gs.building_def(b)))


static func output_value(gs, b: Dictionary) -> float:
	return float(b.get("costing", {}).get("units", 0.0)) * EconomySim.market_price(gs, product_of(gs.building_def(b)))


## Compras de insumos con rutas (las registra TransportDivSim al ver el envío): no son consumo del mes.
static func add_purchase(gs, bid: int, amount: float) -> void:
	var b: Dictionary = gs.get_building(bid)
	if not b.is_empty():
		b["cost_purchases_m"] = float(b.get("cost_purchases_m", 0.0)) + amount


## Precio de referencia de venta hoy: el que fijaste si vende en su sitio; el de mercado si va al almacén.
static func sale_ref_price(gs, b: Dictionary) -> float:
	var def: Dictionary = gs.building_def(b)
	var ld: Dictionary = gs.level_def(b)
	if LogisticsSim.uses_chain(def, ld) and LogisticsSim.outputs_to_warehouse(def, ld):
		return EconomySim.market_price(gs, product_of(def))
	var p := float(b.get("price", 0.0))
	return p if p > 0.0 else EconomySim.market_price(gs, product_of(def))


## Cada día (al final): unidades producidas y precio de referencia.
static func daily(gs) -> void:
	for b in gs.buildings:
		if not gs.owned_by_player(b):
			continue
		var def: Dictionary = gs.building_def(b)
		if not is_producer_def(def):
			continue
		var units := 0.0
		if LogisticsSim.uses_chain(def, gs.level_def(b)):
			units = float(b.get("produced_today", 0.0))
		else:
			units = float(b.get("units_today", 0.0))
		b["units_today"] = 0.0
		if gs.is_active(b):
			b["cost_units_m"] = float(b.get("cost_units_m", 0.0)) + units
			b["cost_psum_m"] = float(b.get("cost_psum_m", 0.0)) + sale_ref_price(gs, b)
			b["cost_pn_m"] = int(b.get("cost_pn_m", 0)) + 1


## Precio unitario de un insumo: tu costo si lo produces tú (último mes), si no el de mercado.
static func input_unit_value(gs, good: String) -> float:
	var own := float(gs.economy.get("costing_goods", {}).get(good, 0.0))
	return own if own > 0.0 else EconomySim.market_price(gs, good)


## Desglose a partir de un libro (last_month) y unidades. Devuelve el diccionario de costeo.
static func breakdown(gs, b: Dictionary, units: float, price_avg: float, purchases := 0.0) -> Dictionary:
	var def: Dictionary = gs.building_def(b)
	var ld: Dictionary = gs.level_def(b)
	var L: Dictionary = b.get("ledger", {}).get("last_month", {})
	var pm: float = gs.price_mult()
	var consumables := float(ld.get("unit_cost", 0.0)) * pm * units
	var recipe := 0.0
	if LogisticsSim.uses_chain(def, ld):
		var inputs := LogisticsSim.recipe_inputs(def, ld)
		for g in inputs:
			recipe += float(inputs[g]) * units * input_unit_value(gs, str(g))
	var energy := maxf(0.0, float(L.get("insumos", 0.0)) - consumables - purchases)
	var alloc := TransportDivSim.allocated_to(gs, b)
	var years := float(cfg().get("depreciation_years", 20))
	var parts := {
		"insumos": recipe + consumables,
		"sueldos": float(L.get("salarios", 0.0)) + float(L.get("salarios_negro", 0.0)),
		"mant_energia": float(L.get("mantenimiento", 0.0)) + float(L.get("reparaciones", 0.0)) + energy,
		"transporte": float(L.get("fletes", 0.0)) + alloc,
		"depreciacion": BusinessSim.period_value(b, "total", "obras") / maxf(1.0, years * 12.0),
		"impuestos": float(L.get("impuestos", 0.0)) + float(L.get("iva", 0.0)) + float(L.get("multas", 0.0)),
	}
	var total := 0.0
	for k in PARTS:
		total += float(parts[k])
	var per_unit := {}
	for k in PARTS:
		per_unit[k] = float(parts[k]) / units if units > 0.0 else 0.0
	var unit := total / units if units > 0.0 else 0.0
	var fixed := float(parts["sueldos"]) + float(parts["mant_energia"]) + float(parts["depreciacion"]) + alloc
	var var_unit := (float(parts["insumos"]) + float(L.get("fletes", 0.0)) + float(parts["impuestos"])) / units if units > 0.0 else 0.0
	var be := fixed / (price_avg - var_unit) if price_avg > var_unit else INF
	return {"day": gs.today(), "units": units, "parts": parts, "per_unit": per_unit, "total": total, "unit_cost": unit,
		"price": price_avg, "margin": price_avg - unit, "margin_pct": (price_avg - unit) / maxf(0.0001, price_avg),
		"break_even": be, "fixed": fixed, "var_unit": var_unit, "energy": energy, "alloc": alloc, "product": product_of(def)}


## Cierre mensual (después de BusinessSim.monthly y TransportDivSim.monthly).
static func monthly(gs) -> void:
	var goods := {}
	var hmax := int(cfg().get("hist_max", 24))
	for b in gs.buildings:
		if not gs.owned_by_player(b) or not is_producer_def(gs.building_def(b)):
			continue
		var units := float(b.get("cost_units_m", 0.0))
		var pn := int(b.get("cost_pn_m", 0))
		var price := float(b.get("cost_psum_m", 0.0)) / pn if pn > 0 else sale_ref_price(gs, b)
		var c := breakdown(gs, b, units, price, float(b.get("cost_purchases_m", 0.0)))
		b["costing"] = c
		b["cost_units_m"] = 0.0
		b["cost_psum_m"] = 0.0
		b["cost_pn_m"] = 0
		b["cost_purchases_m"] = 0.0
		if units > 0.0:
			var h: Array = b.get("cost_hist", [])
			h.append([gs.today(), snappedf(float(c["unit_cost"]), 0.001), snappedf(price, 0.001), snappedf(units, 0.1)])
			while h.size() > hmax:
				h.pop_front()
			b["cost_hist"] = h
			var p := str(c["product"])
			var acc: Array = goods.get(p, [0.0, 0.0])
			acc[0] = float(acc[0]) + float(c["total"])
			acc[1] = float(acc[1]) + units
			goods[p] = acc
	var cg := {}
	for p in goods:
		if float(goods[p][1]) > 0.0:
			cg[p] = float(goods[p][0]) / float(goods[p][1])
	gs.economy["costing_goods"] = cg


# --- Calculadora de fábrica (antes de construir) -------------------------------------------------------

## Estimación a plantilla completa con precios de hoy: {units_day, unit_cost, per_unit {parte}, price, margin,
## margin_pct, monthly {ingreso, costo, resultado}, wage, productivity, staff, notes}.
static func estimate(gs, type_id: String, level := 1) -> Dictionary:
	var def := GameData.building_def(type_id)
	var ld := GameData.level_def(type_id, level)
	var pm: float = gs.price_mult()
	var product := product_of(def)
	var jobs := int(ld.get("jobs", 1))
	var skill := str(def.get("skill", ""))
	var fake := {"type": type_id, "level": level}
	var cands := BusinessSim.candidates(gs, fake).filter(func(c): return c.education >= int(ld.get("min_education", 0)))
	var prod := 0.0
	var wage := 0.0
	var n := mini(jobs, cands.size())
	for i in range(n):
		prod += BusinessSim.productivity(cands[i], skill)
		wage += maxf(BusinessSim.asked_wage(gs, cands[i], type_id), GovSim.min_wage(gs))
	if n > 0:
		prod /= n
		wage /= n
	else:
		prod = 1.0
		wage = maxf(float(def.get("base_wage", 2.0)) * pm, GovSim.min_wage(gs))
	var units := jobs * prod * float(ld.get("prod_per_worker", 1.0))
	units *= TechSim.mult(gs, "production", product)
	units *= float(def.get("resource_bonus", {}).get(str(gs.settings.get("map_type", "")), 1.0))
	if bool(def.get("seasonal", false)):
		units *= float(WeatherSim.season_data(gs).get("farming", 1.0))
	var notes := []
	var recipe := 0.0
	var inputs := LogisticsSim.recipe_inputs(def, ld)
	var in_qty := 0.0
	for g in inputs:
		recipe += float(inputs[g]) * input_unit_value(gs, str(g))
		in_qty += float(inputs[g])
	var day := {}
	day["insumos"] = units * (recipe + float(ld.get("unit_cost", 0.0)) * pm)
	day["sueldos"] = jobs * wage
	var discount := minf(0.9, BusinessSim.office_discount(gs))
	var energy := 0.0
	if EnergySim.grid_active(gs) and EnergySim.level_demand_kw(def, ld) > 0.0:
		energy = EnergySim.level_demand_kw(def, ld) * EnergySim.price(gs)
	day["mant_energia"] = float(ld.get("upkeep", 0.0)) * pm * (1.0 - discount) + energy
	day["transporte"] = 0.0
	var build := float(ConstructionSim.cost_for(gs, type_id, level, false)["total"])
	day["depreciacion"] = build / maxf(1.0, float(cfg().get("depreciation_years", 20)) * 360.0)
	var price := EconomySim.market_price(gs, product)
	var p := GovSim.policy(gs)
	var pre_tax := units * price - (float(day["insumos"]) + float(day["sueldos"]) + float(day["mant_energia"]) + float(day["depreciacion"]))
	day["impuestos"] = maxf(0.0, pre_tax) * float(p.get("profit_tax", 0.0)) + build * 0.7 * float(p.get("property_tax", 0.0)) / 360.0 \
			+ float(day["sueldos"]) * float(p.get("wage_tax", 0.0))
	var total := 0.0
	for k in PARTS:
		total += float(day[k])
	var per_unit := {}
	for k in PARTS:
		per_unit[k] = float(day[k]) / units if units > 0.0 else 0.0
	var unit := total / units if units > 0.0 else 0.0
	if not inputs.is_empty():
		var fr := (in_qty + 1.0) * (TransportDivSim.handling(gs) + TransportDivSim.market_rate(gs) * 0.6)
		notes.append("Si traes los insumos o sacas la producción con rutas, súmale ≈ %s por unidad de flete." % Fmt.money2(fr))
	if n < jobs:
		notes.append("Solo hay %d candidatos disponibles para %d puestos: se estimó con productividad normal para el resto." % [n, jobs])
	if str(ld.get("requires_deposit", "")) != "":
		notes.append("Necesita un yacimiento de %s." % RegionSim.resource_label(str(ld["requires_deposit"])).to_lower())
	if energy > 0.0:
		notes.append("Incluye electricidad (%s/día)." % Fmt.money2(energy))
	return {"type": type_id, "level": level, "product": product, "units_day": units, "per_unit": per_unit, "per_day": day,
		"unit_cost": unit, "price": price, "margin": price - unit, "margin_pct": (price - unit) / maxf(0.0001, price),
		"monthly": {"income": units * price * 30.0, "cost": total * 30.0, "result": (units * price - total) * 30.0},
		"wage": wage, "productivity": prod, "staff": jobs, "build_cost": build, "notes": notes}


static func estimate_text(e: Dictionary) -> String:
	var lines := ["[b]%s[/b] a plantilla completa (%d empleados): %s %s/día" % [GameData.good_label(str(e["product"])), int(e["staff"]),
		String.num(float(e["units_day"]), 1).replace(".", ","), "u."]]
	var parts := []
	for k in PARTS:
		if float(e["per_unit"][k]) > 0.0005:
			parts.append("%s %s" % [PART_LABELS[k].to_lower(), Fmt.money2(float(e["per_unit"][k]))])
	lines.append("Costo por unidad ≈ [b]%s[/b] (%s)" % [Fmt.money2(float(e["unit_cost"])), ", ".join(parts)])
	var col := "#6c6" if float(e["margin"]) >= 0.0 else "#e66"
	lines.append("Precio de mercado %s · margen [color=%s]%s (%s)[/color] · resultado ≈ %s/mes" % [Fmt.money2(float(e["price"])), col,
		Fmt.money2(float(e["margin"])), Fmt.pct(float(e["margin_pct"]) * 100.0), Fmt.money(float(e["monthly"]["result"]))])
	for n in e.get("notes", []):
		lines.append("[color=#8a8f99]%s[/color]" % n)
	return "\n".join(lines)
