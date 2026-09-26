class_name RealEstateSim
extends RefCounted
## Bienes raíces: edificios multifamiliares divididos en unidades (apartamentos) que se
## arriendan o venden por separado, ficha de factibilidad, proyectos pagados por etapas,
## preventa sobre planos, crédito constructor e hipotecas para los ciudadanos.
## Configuración en data/realestate.json. Documentación en docs/BIENES_RAICES.md.
##
## Estado:
##  - b["units"]: Array de unidades del edificio (layout del nivel objetivo), cada una
##    {id, code, floor, type, area, capacity, status, tenant_id, owner_id, household,
##     rent, price, for_rent, for_sale, manual, presale, seller}.
##    status: disponible | arrendada | vendida | preventa | embargada.
##  - b["re_project"]: proyecto en obra (etapas pagadas, crédito, preventas).
##  - gs.realestate: demanda del pueblo y contadores mensuales.

const STATUS_LABELS := {"disponible": "Disponible", "arrendada": "Arrendada", "vendida": "Vendida",
	"preventa": "Preventa", "embargada": "Embargada"}

static var _idx := {}          # citizen_id -> [building_id, unit_index]
static var _idx_dirty := true


static func cfg() -> Dictionary:
	return GameData.extra("realestate")


static func pricing_cfg() -> Dictionary:
	return cfg().get("pricing", {})


static func init_state(gs) -> void:
	if typeof(gs.realestate) != TYPE_DICTIONARY:
		gs.realestate = {}
	if not gs.realestate.has("demand"):
		gs.realestate["demand"] = 1.0
	for k in ["month", "last_month", "total"]:
		if not gs.realestate.has(k):
			gs.realestate[k] = {}
	_idx_dirty = true
	for b in gs.buildings:
		if is_multi(b) and gs.is_active(b):
			ensure_units(gs, b)


static func _count(gs, key: String, amount: float) -> void:
	for period in ["month", "total"]:
		var d: Dictionary = gs.realestate.get(period, {})
		d[key] = float(d.get(key, 0.0)) + amount
		gs.realestate[period] = d


# --- Tipología ----------------------------------------------------------------------------

static func is_multi_level(level: int) -> bool:
	if cfg().get("levels", {}).has(str(level)):
		return true
	var ld := GameData.level_def("vivienda", level)
	return not ld.is_empty() and int(ld.get("capacity", 0)) > int(cfg().get("family_capacity", 10))


## Vivienda multifamiliar (según su nivel objetivo, para incluir obras en curso).
static func is_multi(b: Dictionary) -> bool:
	return Housing.is_home(b) and is_multi_level(int(b.get("target_level", b.get("level", 1))))


static func has_units(b: Dictionary) -> bool:
	return Housing.is_home(b) and not (b.get("units", []) as Array).is_empty()


## Distribución: [{floor, type}] por nivel.
static func layout(level: int) -> Array:
	var out := []
	var lc: Dictionary = cfg().get("levels", {}).get(str(level), {})
	if lc.is_empty():
		var cap := int(GameData.level_def("vivienda", level).get("capacity", 0))
		var n := maxi(2, int(cap / 4))
		for i in range(n):
			out.append({"floor": int(i / 2) + 1, "type": "familiar"})
		return out
	var per: Array = lc.get("per_floor", ["familiar"])
	for f in range(int(lc.get("floors", 1))):
		for t in per:
			out.append({"floor": f + 1, "type": str(t)})
	return out


static func floors(level: int) -> int:
	var l := layout(level)
	return 0 if l.is_empty() else int(l[-1]["floor"])


static func type_def(t: String) -> Dictionary:
	return cfg().get("unit_types", {}).get(t, {"label": t, "area": 60, "capacity": 4})


static func type_label(t: String) -> String:
	return str(type_def(t).get("label", t))


static func status_label(s: String) -> String:
	return str(STATUS_LABELS.get(s, s))


# --- Precios ---------------------------------------------------------------------------------

## Costo de reposición: obra nueva de ese nivel con todos los materiales importados.
static func replacement_cost(gs, level: int, tier: String) -> float:
	var ld := GameData.level_def("vivienda", level)
	var pm: float = gs.price_mult()
	var factor := float(Housing.tier_def_by_id(tier).get("cost_mult", 1.0))
	var total := float(ld.get("cost", 0)) * pm * factor
	var mats: Dictionary = ld.get("materials", {})
	for g in mats:
		total += ceilf(float(mats[g]) * factor) * float(GameData.goods.get(g, {}).get("import_price", 5.0)) * pm * GovSim.import_mult(gs)
	return total


static func demand(gs) -> float:
	return float(gs.realestate.get("demand", 1.0)) if typeof(gs.realestate) == TYPE_DICTIONARY else 1.0


static func cap_rate(gs) -> float:
	return float(pricing_cfg().get("era_cap_rate", {}).get(str(gs.era()), 0.07))


## Valor de mercado de todo el edificio (suma de sus unidades).
static func value_total(gs, level: int, tier: String) -> float:
	var pc := pricing_cfg()
	return replacement_cost(gs, level, tier) * (1.0 + float(pc.get("developer_margin", 0.24))) * demand(gs) \
		* float(pc.get("era_value_mult", {}).get(str(gs.era()), 1.0)) * GlobalEconSim.property_mult(gs)   # Ciclo económico.


static func _floor_factor(floor: int) -> float:
	return 1.0 + float(pricing_cfg().get("floor_premium", 0.015)) * (floor - 1)


## Precio y renta sugeridos de cada unidad del layout: [{price, rent}] (los pisos altos valen más).
static func unit_prices(gs, level: int, tier: String) -> Array:
	var lay := layout(level)
	var weights := []
	var sum_w := 0.0
	for u in lay:
		var w := float(type_def(str(u["type"])).get("area", 60)) * _floor_factor(int(u["floor"]))
		weights.append(w)
		sum_w += w
	var total := value_total(gs, level, tier)
	var cr := cap_rate(gs)
	var out := []
	for i in range(lay.size()):
		var price := total * float(weights[i]) / maxf(1.0, sum_w)
		out.append({"price": snappedf(price, 1.0), "rent": snappedf(price * cr / 12.0, 0.1)})
	return out


static func make_units(gs, level: int, tier: String) -> Array:
	var lay := layout(level)
	var prices := unit_prices(gs, level, tier)
	var out := []
	var per_floor := {}
	for i in range(lay.size()):
		var f := int(lay[i]["floor"])
		per_floor[f] = int(per_floor.get(f, 0)) + 1
		var t := str(lay[i]["type"])
		var td := type_def(t)
		out.append({"id": i + 1, "code": "P%d-%02d" % [f, int(per_floor[f])], "floor": f, "type": t,
			"area": int(td.get("area", 60)), "capacity": int(td.get("capacity", 4)),
			"status": "disponible", "tenant_id": -1, "owner_id": -1, "household": [],
			"rent": float(prices[i]["rent"]), "price": float(prices[i]["price"]),
			"for_rent": true, "for_sale": false, "manual": false, "presale": {}, "seller": ""})
	return out


## Crea (o adapta tras una mejora) las unidades del edificio sin perder inquilinos ni dueños.
static func ensure_units(gs, b: Dictionary) -> void:
	if not is_multi(b):
		return
	var level := int(b.get("target_level", b["level"]))
	var want := layout(level).size()
	var cur: Array = b.get("units", [])
	if cur.size() != want:
		var fresh := make_units(gs, level, str(b.get("tier", "normal")))
		for i in range(mini(cur.size(), fresh.size())):
			var o: Dictionary = cur[i]
			for k in ["status", "tenant_id", "owner_id", "household", "for_rent", "for_sale", "presale", "seller"]:
				if o.has(k):
					fresh[i][k] = o[k]
			if str(o.get("status", "")) in ["arrendada", "vendida", "preventa"]:
				fresh[i]["rent"] = float(o.get("rent", fresh[i]["rent"]))
				fresh[i]["price"] = float(o.get("price", fresh[i]["price"]))
		b["units"] = fresh
		_idx_dirty = true
	b["for_sale"] = false   # Un multifamiliar se vende por unidades.
	for u in b["units"]:
		u["tenant_id"] = int(u.get("tenant_id", -1))
		u["owner_id"] = int(u.get("owner_id", -1))
	if gs.is_active(b):
		_assign_residents(gs, b)


## Familias que ya vivían en el edificio (migración o mejora) reciben su unidad.
static func _assign_residents(gs, b: Dictionary) -> void:
	var bid := int(b["id"])
	var units: Array = b["units"]
	var covered := {}
	for u in units:
		for id in _unit_people(u):
			covered[id] = true
	var groups := []
	for members in MarketSim.households(gs):
		var head: Citizen = members[0]
		if head.home_id != bid or covered.has(head.id):
			continue
		groups.append(members)
	for members in groups:
		var best := -1
		for i in range(units.size()):
			var u: Dictionary = units[i]
			if str(u["status"]) != "disponible":
				continue
			if best < 0:
				best = i
			var fits: bool = int(u["capacity"]) >= members.size()
			var best_fits: bool = int(units[best]["capacity"]) >= members.size()
			if fits and (not best_fits or int(u["capacity"]) < int(units[best]["capacity"])):
				best = i
		if best < 0:
			return   # Sin unidades libres: siguen pagando la renta por persona de antes.
		_rent_to(gs, units[best], members)


static func _unit_people(u: Dictionary) -> Array:
	var out: Array = (u.get("household", []) as Array).duplicate()
	for k in ["tenant_id", "owner_id"]:
		var id := int(u.get(k, -1))
		if id >= 0 and not out.has(id):
			out.append(id)
	var ps: Dictionary = u.get("presale", {})
	if not ps.is_empty():
		for id in ps.get("household", []):
			if not out.has(int(id)):
				out.append(int(id))
	return out


static func _ids(members: Array) -> Array:
	return members.map(func(m): return int(m.id))


static func _rent_to(gs, u: Dictionary, members: Array) -> void:
	u["status"] = "arrendada"
	u["tenant_id"] = int(members[0].id)
	u["owner_id"] = -1
	u["household"] = _ids(members)
	u["seller"] = ""
	_idx_dirty = true


static func _free(u: Dictionary) -> void:
	u["status"] = "disponible"
	u["tenant_id"] = -1
	u["owner_id"] = -1
	u["household"] = []
	u["presale"] = {}
	u["seller"] = ""
	_idx_dirty = true


# --- Índice ciudadano → unidad ------------------------------------------------------------------

static func _rebuild_index(gs) -> void:
	_idx = {}
	for b in gs.buildings:
		if not has_units(b):
			continue
		var units: Array = b["units"]
		for i in range(units.size()):
			var u: Dictionary = units[i]
			if str(u["status"]) in ["arrendada", "vendida"]:
				for id in _unit_people(u):
					_idx[int(id)] = [int(b["id"]), i]
	_idx_dirty = false


## Unidad donde vive el ciudadano en este edificio ({} si no tiene).
static func unit_of(gs, b: Dictionary, c: Citizen) -> Dictionary:
	if _idx_dirty:
		_rebuild_index(gs)
	var bid := int(b["id"])
	for id in [c.id, c.spouse_id] + c.parent_ids:
		var e: Array = _idx.get(int(id), [])
		if not e.is_empty() and int(e[0]) == bid:
			var units: Array = b["units"]
			if int(e[1]) < units.size():
				return units[int(e[1])]
	return {}


static func find_unit(gs, ref: String) -> Dictionary:
	var p := ref.split(":")
	if p.size() != 2:
		return {}
	var b: Dictionary = gs.get_building(int(p[0]))
	if b.is_empty() or not has_units(b):
		return {}
	var units: Array = b["units"]
	var i := int(p[1])
	return units[i] if i >= 0 and i < units.size() else {}


static func unit_ref(b: Dictionary, u: Dictionary) -> String:
	return "%d:%d" % [int(b["id"]), int(u["id"]) - 1]


# --- Pago diario de vivienda -------------------------------------------------------------------

## Lo llama PopulationSim._pay_housing para viviendas del jugador con unidades.
## 1 = pagado/no aplica, 0 = no pudo pagar, -1 = sin unidad (sigue la renta por persona).
static func pay_unit_housing(gs, c: Citizen, home: Dictionary, payers: Array) -> int:
	if not gs.is_active(home):
		return 1   # En obra: no se cobra (como antes).
	var u := unit_of(gs, home, c)
	if u.is_empty():
		return -1
	if str(u["status"]) != "arrendada" or int(u["tenant_id"]) != c.id:
		return 1   # Dueño de su unidad o familiar del inquilino.
	var rent := float(u["rent"]) / 30.0
	if rent <= 0.0:
		return 1
	if PopulationSim.pay_with(gs, payers, rent):
		BusinessSim.earn(gs, home, rent, "alquileres")
		_count(gs, "rent", rent)
		c.unpaid_days = 0
		return 1
	c.unpaid_days += 1
	return 0


# --- Ficha del proyecto (factibilidad) -------------------------------------------------------------

static func upkeep_month(gs, level: int) -> float:
	return float(GameData.level_def("vivienda", level).get("upkeep", 0.0)) * 30.0 * gs.price_mult()


## Ficha de factibilidad para construir (o mejorar a) un nivel multifamiliar.
## Si `b` es un proyecto en obra, usa su costo real y sus precios fijados.
static func feasibility(gs, level: int, tier: String, is_upgrade := false, b := {}) -> Dictionary:
	var cost := ConstructionSim.cost_for(gs, "vivienda", level, is_upgrade, tier)
	var total := float(cost["total"])
	var prices := unit_prices(gs, level, tier)
	var units: Array = []
	if not b.is_empty() and has_units(b):
		units = b["units"]
		if b.has("re_project"):
			total = float(b["re_project"]["total"])
	var n := prices.size()
	var rent_total := 0.0
	var sales_total := 0.0
	var rmin := INF
	var rmax := 0.0
	var pmin := INF
	var pmax := 0.0
	for i in range(n):
		var rent := float(prices[i]["rent"])
		var price := float(prices[i]["price"])
		if i < units.size():
			rent = float(units[i]["rent"])
			price = float(units[i]["price"])
		rent_total += rent
		sales_total += price
		rmin = minf(rmin, rent)
		rmax = maxf(rmax, rent)
		pmin = minf(pmin, price)
		pmax = maxf(pmax, price)
	var upkeep := upkeep_month(gs, level)
	var tax := sales_total * float(GovSim.policy(gs).get("property_tax", 0.0)) / 12.0
	var net := rent_total - upkeep - tax
	var stages := []
	for s in cfg().get("stages", []):
		stages.append({"label": str(s["label"]), "amount": total * float(s["share"])})
	return {
		"level": level, "tier": tier, "label": str(GameData.level_def("vivienda", level).get("label", "")),
		"units": n, "floors": floors(level), "cost_total": total, "cost_per_unit": total / maxf(1.0, n),
		"days": int(cost["days"]), "workers": int(cost["workers"]), "import_cost": float(cost["import_cost"]),
		"rent_total": rent_total, "rent_unit": rent_total / maxf(1.0, n), "rent_min": rmin if n > 0 else 0.0, "rent_max": rmax,
		"sales_total": sales_total, "price_unit": sales_total / maxf(1.0, n), "price_min": pmin if n > 0 else 0.0, "price_max": pmax,
		"margin": (sales_total - total) / maxf(1.0, total),
		"gross_yield": rent_total * 12.0 / maxf(1.0, total),
		"yield_on_value": rent_total * 12.0 / maxf(1.0, sales_total),
		"net_month": net, "upkeep_month": upkeep, "tax_month": tax,
		"net_yield": net * 12.0 / maxf(1.0, total),
		"payback_months": total / net if net > 0.0 else INF,
		"stages": stages, "cap_rate": cap_rate(gs), "demand": demand(gs),
	}


static func feasibility_text(f: Dictionary) -> String:
	var s := "[b]Ficha del proyecto: %s[/b] (%d unidades en %d pisos)\n" % [f["label"], int(f["units"]), int(f["floors"])]
	s += "Costo total: %s · por unidad: %s · obra: %d días con %d trabajadores\n" % [Fmt.money(f["cost_total"]), Fmt.money(f["cost_per_unit"]), int(f["days"]), int(f["workers"])]
	var st := []
	for x in f["stages"]:
		st.append("%s %s" % [x["label"], Fmt.money(x["amount"])])
	s += "Pago por etapas: %s\n" % " → ".join(st)
	s += "Arriendo/mes por unidad: %s (de %s a %s) · total %s\n" % [Fmt.money2(f["rent_unit"]), Fmt.money2(f["rent_min"]), Fmt.money2(f["rent_max"]), Fmt.money(f["rent_total"])]
	s += "Venta por unidad: %s (de %s a %s) · total %s\n" % [Fmt.money(f["price_unit"]), Fmt.money(f["price_min"]), Fmt.money(f["price_max"]), Fmt.money(f["sales_total"])]
	var mc := "#6c6" if float(f["margin"]) >= 0.0 else "#e66"
	s += "Margen de venta: [color=%s]%s[/color] · Rentabilidad arriendo: %s bruta, %s neta/año\n" % [mc, Fmt.pct(float(f["margin"]) * 100.0), Fmt.pct(float(f["gross_yield"]) * 100.0), Fmt.pct(float(f["net_yield"]) * 100.0)]
	var pb := float(f["payback_months"])
	s += "Recuperas la inversión arrendando en: %s · mantenimiento %s/mes\n" % ["nunca (renta < gastos)" if pb == INF else "%d meses (%.1f años)" % [int(ceil(pb)), pb / 12.0], Fmt.money(f["upkeep_month"])]
	s += "[color=#aaa]Demanda del pueblo ×%.2f · tasa de capitalización %s. Los pisos altos valen más.[/color]\n" % [float(f["demand"]), Fmt.pct(float(f["cap_rate"]) * 100.0)]
	return s


# --- Proyectos por etapas ---------------------------------------------------------------------------

static func stage_defs() -> Array:
	return cfg().get("stages", [{"id": "obra", "label": "Obra", "share": 1.0}])


static func _new_project(kind: String, level: int, tier: String, cost: Dictionary, from_level: int) -> Dictionary:
	var stages := []
	for s in stage_defs():
		stages.append({"id": str(s["id"]), "label": str(s["label"]), "share": float(s["share"]),
			"amount": float(cost["total"]) * float(s["share"]), "paid": false})
	return {"kind": kind, "level": level, "tier": tier, "from_level": from_level, "total": float(cost["total"]),
		"stages": stages, "paused": false, "credit_id": -1, "credit_ratio": 0.0,
		"presale_received": 0.0, "paid_total": 0.0, "notified_pause": false}


## Monto que el jugador necesita de su bolsillo para una etapa (descontando el crédito).
static func own_share(gs, b: Dictionary, idx: int) -> float:
	var p: Dictionary = b["re_project"]
	var st: Dictionary = p["stages"][idx]
	var amount := float(st["amount"])
	var l := LoanContract.find_loan(gs, int(p.get("credit_id", -1)))
	if l.is_empty() or bool(l.get("closed", false)):
		return amount
	var from_credit := minf(amount * float(p["credit_ratio"]), maxf(0.0, float(l["limit"]) - float(l["disbursed"])))
	return amount - from_credit


static func _pay_stage(gs, b: Dictionary, idx: int) -> bool:
	var p: Dictionary = b["re_project"]
	var st: Dictionary = p["stages"][idx]
	if bool(st["paid"]):
		return true
	var amount := float(st["amount"])
	var own := own_share(gs, b, idx)
	if gs.money < own:
		return false
	var l := LoanContract.find_loan(gs, int(p.get("credit_id", -1)))
	var got := LoanContract.disburse(gs, l, amount - own)
	if got + 0.01 < amount - own and gs.money < amount - got:
		return false
	gs.add_money(-amount)
	BusinessSim.ledger_add(b, "obras", amount)
	st["paid"] = true
	p["paid_total"] = float(p["paid_total"]) + amount
	if idx > 0:
		gs.notify("%s: pagaste la etapa de %s (%s%s)." % [gs.building_label(b), str(st["label"]).to_lower(), Fmt.money(amount),
			", %s del crédito constructor" % Fmt.money(got) if got > 0.0 else ""], "construccion")
	return true


static func project_block_reason(gs, level: int, tier: String, credit_ratio := 0.0) -> String:
	if not is_multi_level(level):
		return "No es un nivel multifamiliar"
	var r := ConstructionSim.level_block_reason(gs, "vivienda", level)
	if r != "":
		return r
	var cost := ConstructionSim.cost_for(gs, "vivienda", level, false, tier)
	var first := float(cost["total"]) * float(stage_defs()[0]["share"]) * (1.0 - credit_ratio)
	if gs.money < first:
		return "Necesitas %s para la cimentación" % Fmt.money(first)
	return ""


## Obra nueva de un multifamiliar pagada por etapas. opts: {credit_lender, credit_ratio}.
static func start_project(gs, level: int, tier: String, x: float, z: float, rot: float, bname := "", opts := {}) -> Dictionary:
	var ratio := clampf(float(opts.get("credit_ratio", 0.0)), 0.0, float(cfg().get("constructor_credit", {}).get("max_ratio", 0.6)))
	var lender := str(opts.get("credit_lender", ""))
	if lender == "":
		ratio = 0.0
	var reason := project_block_reason(gs, level, tier, ratio)
	if reason == "":
		reason = ConstructionSim.placement_block_reason(gs, "vivienda", x, z, -1, level)
	if reason != "":
		return {"error": reason}
	var cost := ConstructionSim.cost_for(gs, "vivienda", level, false, tier)
	var b := ConstructionSim.make_building(gs, "vivienda", level, x, z, rot, "jugador")
	b["status"] = "construccion"
	b["target_level"] = level
	b["work_needed"] = float(int(cost["days"]) * int(cost["workers"]))
	b["name"] = bname
	ConstructionSim.apply_tier(b, tier)
	b["re_project"] = _new_project("nuevo", level, tier, cost, 0)
	b["units"] = make_units(gs, level, tier)
	var err := _setup_credit(gs, b, lender, ratio, int(cost["days"]))
	if err != "":
		return {"error": err}
	for g in cost["from_stock"]:
		ConstructionSim._consume_stock(gs, g, float(cost["from_stock"][g]))
	gs.add_building(b)
	if not _pay_stage(gs, b, 0):
		_cancel_credit(gs, b)
		gs.remove_building(int(b["id"]))
		return {"error": "Dinero insuficiente para la cimentación"}
	LogisticsSim.on_buildings_changed(gs)
	gs.notify("Proyecto inmobiliario iniciado: %s (%d unidades). Pagas por etapas: %s de cimentación." % [gs.building_label(b), (b["units"] as Array).size(), Fmt.money(float(b["re_project"]["stages"][0]["amount"]))], "construccion")
	EventBus.building_changed.emit(int(b["id"]))
	return {"building": b}


## Mejora de una vivienda tuya a un nivel multifamiliar, pagada por etapas.
static func start_project_upgrade(gs, b: Dictionary, opts := {}) -> String:
	if not gs.owned_by_player(b) or not Housing.is_home(b):
		return "Solo tus viviendas"
	if not gs.is_active(b):
		return "Ya está en obras"
	var next := int(b["level"]) + 1
	if not is_multi_level(next):
		return "El siguiente nivel no es multifamiliar"
	var reason := ConstructionSim.level_block_reason(gs, "vivienda", next)
	if reason == "":
		reason = ConstructionSim.upgrade_space_reason(gs, b, next)
	if reason != "":
		return reason
	var ratio := clampf(float(opts.get("credit_ratio", 0.0)), 0.0, float(cfg().get("constructor_credit", {}).get("max_ratio", 0.6)))
	var lender := str(opts.get("credit_lender", ""))
	if lender == "":
		ratio = 0.0
	var tier := str(b.get("tier", "normal"))
	var cost := ConstructionSim.cost_for(gs, "vivienda", next, true, tier)
	var first := float(cost["total"]) * float(stage_defs()[0]["share"]) * (1.0 - ratio)
	if gs.money < first:
		return "Necesitas %s para la cimentación" % Fmt.money(first)
	var old_units: Array = b.get("units", [])
	b["re_project"] = _new_project("mejora", next, tier, cost, int(b["level"]))
	var err := _setup_credit(gs, b, lender, ratio, int(cost["days"]))
	if err != "":
		b.erase("re_project")
		return err
	b["target_level"] = next
	if not _pay_stage(gs, b, 0):
		_cancel_credit(gs, b)
		b.erase("re_project")
		b["target_level"] = int(b["level"])
		return "Dinero insuficiente para la cimentación"
	for g in cost["from_stock"]:
		ConstructionSim._consume_stock(gs, g, float(cost["from_stock"][g]))
	b["status"] = "mejorando"
	b["work_done"] = 0.0
	b["work_needed"] = float(int(cost["days"]) * int(cost["workers"]))
	b["units"] = old_units
	ensure_units(gs, b)   # Layout del nivel nuevo, conservando inquilinos y dueños.
	gs.notify("Proyecto de mejora iniciado: %s → %s, pagado por etapas." % [gs.building_label(b), GameData.level_def("vivienda", next).get("label", "")], "construccion")
	EventBus.building_changed.emit(int(b["id"]))
	return ""


static func _setup_credit(gs, b: Dictionary, lender: String, ratio: float, days: int) -> String:
	if lender == "" or ratio <= 0.0:
		return ""
	var p: Dictionary = b["re_project"]
	var cc: Dictionary = cfg().get("constructor_credit", {})
	var months := int(ceil(days / 30.0)) + int(cc.get("extra_months", 12))
	var r := LoanContract.open_constructor_credit(gs, lender, float(p["total"]) * ratio, months, int(b["id"]))
	if r.has("error"):
		return str(r["error"])
	p["credit_id"] = int(r["loan"]["id"])
	p["credit_ratio"] = ratio
	b["re_credit_id"] = int(r["loan"]["id"])
	return ""


static func _cancel_credit(gs, b: Dictionary) -> void:
	var l := LoanContract.find_loan(gs, int(b.get("re_project", {}).get("credit_id", -1)))
	if not l.is_empty():
		LoanContract.close_credit(gs, l)


static func stage_index(b: Dictionary) -> int:
	var p: Dictionary = b.get("re_project", {})
	if p.is_empty():
		return -1
	var prog := float(b["work_done"]) / maxf(1.0, float(b["work_needed"]))
	var cum := 0.0
	var stages: Array = p["stages"]
	for i in range(stages.size()):
		cum += float(stages[i]["share"])
		if prog < cum - 0.0001:
			return i
	return stages.size() - 1


## Diario (antes de las obras): paga la etapa que empieza o pausa la obra si no hay dinero.
static func daily(gs) -> void:
	for b in gs.buildings:
		if not b.has("re_project") or not (b["status"] == "construccion" or b["status"] == "mejorando"):
			continue
		var p: Dictionary = b["re_project"]
		var stages: Array = p["stages"]
		var wn := float(b["work_needed"])
		var cum := 0.0
		var blocked := false
		for i in range(stages.size()):
			var start := cum * wn
			cum += float(stages[i]["share"])
			if bool(stages[i]["paid"]):
				continue
			if float(b["work_done"]) + 0.0001 < start:
				break
			if not _pay_stage(gs, b, i):
				b["work_done"] = start   # Lo avanzado se conserva; no se trabaja lo que no está pagado.
				blocked = true
				if not bool(p.get("notified_pause", false)):
					p["notified_pause"] = true
					gs.notify("OBRA PAUSADA: %s no puede empezar la etapa de %s. Necesitas %s." % [gs.building_label(b), str(stages[i]["label"]).to_lower(), Fmt.money(own_share(gs, b, i))], "jugador")
				break
		if blocked != bool(b.get("paused", false)):
			b["paused"] = blocked
			if blocked:
				for c in gs.citizens.values():
					if c.job_id == int(b["id"]) and c.job_kind == "obra":
						c.job_id = -1
						c.job_kind = ""
						c.wage = 0.0
			else:
				p["notified_pause"] = false
				gs.notify("Obra reanudada: %s." % gs.building_label(b), "construccion")
			EventBus.building_changed.emit(int(b["id"]))


## Gancho de ConstructionSim._complete: crea unidades, entrega preventas, cierra el crédito.
static func on_building_ready(gs, b: Dictionary) -> void:
	b.erase("paused")
	if is_multi(b):
		ensure_units(gs, b)
	if not b.has("re_project"):
		return
	var p: Dictionary = b["re_project"]
	var l := LoanContract.find_loan(gs, int(p.get("credit_id", -1)))
	if not l.is_empty():
		l["closed"] = true
		if float(l["balance"]) <= 0.01:
			gs.loans.erase(l)
	b["re_done"] = {"total": float(p["total"]), "paid_total": float(p["paid_total"]), "kind": str(p["kind"]), "presale_received": float(p["presale_received"]), "finished_day": gs.today()}
	b.erase("re_project")
	if has_units(b):
		for u in b["units"]:
			if str(u["status"]) == "preventa":
				_deliver(gs, b, u)
		_assign_residents(gs, b)
	_idx_dirty = true


## Cancela un proyecto: devuelve las preventas; una obra nueva se demuele y una mejora vuelve
## al nivel anterior. Lo pagado en etapas se pierde y el crédito sigue debiéndose.
static func cancel_project(gs, b: Dictionary) -> String:
	if not b.has("re_project"):
		return "No hay proyecto en obra"
	var p: Dictionary = b["re_project"]
	var refunded := 0.0
	if has_units(b):
		for u in b["units"]:
			if str(u["status"]) == "preventa":
				refunded += _rescind(gs, b, u, true)
	_cancel_credit(gs, b)
	b.erase("re_project")
	b.erase("paused")
	gs.notify("Cancelaste el proyecto %s. Devolviste %s de preventas." % [gs.building_label(b), Fmt.money(refunded)], "jugador")
	if str(p["kind"]) == "nuevo":
		ConstructionSim.demolish(gs, b)
	else:
		for c in gs.citizens.values():
			if c.job_id == int(b["id"]) and c.job_kind == "obra":
				c.job_id = -1
				c.job_kind = ""
				c.wage = 0.0
		b["status"] = "activo"
		b["target_level"] = int(b["level"])
		b["work_done"] = 0.0
		b["work_needed"] = 0.0
		if is_multi(b):
			var keep: Array = b["units"]
			b["units"] = keep.slice(0, layout(int(b["level"])).size())
		else:
			b.erase("units")
		EventBus.building_changed.emit(int(b["id"]))
	_idx_dirty = true
	return ""


# --- Preventa y ventas --------------------------------------------------------------------------------

static func presale_cfg() -> Dictionary:
	return cfg().get("presale", {})


static func _household_money(members: Array) -> float:
	var m := 0.0
	for x in members:
		m += maxf(0.0, x.money)
	return m


static func _household_income(members: Array) -> float:
	var inc := 0.0
	for x in members:
		if x.job_kind == "empleo":
			inc += x.wage * 30.0
	return inc


static func _members_of(gs, ids: Array) -> Array:
	var out := []
	for id in ids:
		if gs.citizens.has(int(id)):
			out.append(gs.citizens[int(id)])
	return out


## Venta de una unidad terminada a una familia (contado o con hipoteca).
static func _sell_unit(gs, b: Dictionary, u: Dictionary, members: Array, price: float, mortgage: Dictionary) -> void:
	var head: Citizen = members[0]
	if not mortgage.is_empty():
		LoanContract.grant_mortgage(gs, mortgage, head, float(mortgage["amount"]), unit_ref(b, u))
		_count(gs, "mortgages_player" if str(mortgage["lender"]).is_valid_int() else "mortgages_external", float(mortgage["amount"]))
	PopulationSim.pay_with(gs, members, price)
	var seller := str(u.get("seller", ""))
	if str(u["status"]) == "embargada":
		if seller == "gobierno":
			GovSim.add_treasury(gs, price)
	else:
		BusinessSim.earn(gs, b, price, "ventas")
		_count(gs, "sales", price)
		_credit_sweep(gs, b, price)
	u["status"] = "vendida"
	u["owner_id"] = head.id
	u["tenant_id"] = -1
	u["household"] = _ids(members)
	u["for_sale"] = false
	u["seller"] = ""
	u["presale"] = {}
	for m in members:
		m.home_id = int(b["id"])
		m.unpaid_days = 0
	_idx_dirty = true
	if seller == "":
		gs.notify("Vendiste el apartamento %s de %s a la familia %s por %s%s." % [u["code"], gs.building_label(b), head.last_name, Fmt.money(price),
			" (hipoteca con %s)" % LoanContract.lender_label(gs, str(mortgage["lender"])) if not mortgage.is_empty() else ""], "negocio")


## Con cada venta se abona al crédito constructor del edificio.
static func _credit_sweep(gs, b: Dictionary, price: float) -> void:
	var l := LoanContract.find_loan(gs, int(b.get("re_credit_id", -1)))
	if l.is_empty():
		return
	var pay := LoanContract.sweep(gs, l, price * float(cfg().get("constructor_credit", {}).get("sales_sweep", 0.7)))
	if pay > 0.0 and float(l["balance"]) <= 0.01 and bool(l.get("closed", false)):
		gs.loans.erase(l)
		gs.notify("Pagaste con ventas el crédito constructor de %s." % gs.building_label(b), "importante")


## Firma de preventa: cuota inicial hoy, cuotas mensuales durante la obra y saldo al entregar.
static func _presell(gs, b: Dictionary, u: Dictionary, members: Array) -> void:
	var pc := presale_cfg()
	var price := float(u["price"])
	var down := price * float(pc.get("down_share", 0.1))
	var months := maxi(1, int(ceil(ConstructionSim.days_left(gs, b) / 30.0)))
	PopulationSim.pay_with(gs, members, down)
	gs.add_money(down)
	var p: Dictionary = b["re_project"]
	p["presale_received"] = float(p["presale_received"]) + down
	_count(gs, "presales", down)
	u["status"] = "preventa"
	u["for_sale"] = false
	u["presale"] = {"buyer_id": members[0].id, "household": _ids(members), "price": price, "paid": down,
		"installment": price * float(pc.get("during_share", 0.2)) / months, "months_left": months, "missed": 0, "day": gs.today()}
	_idx_dirty = true
	gs.notify("Preventa: la familia %s separó el apartamento %s de %s por %s (cuota inicial %s, %d cuotas de %s)." % [members[0].last_name, u["code"], gs.building_label(b), Fmt.money(price), Fmt.money(down), months, Fmt.money(float(u["presale"]["installment"]))], "negocio")


static func _presale_members(gs, u: Dictionary) -> Array:
	var ps: Dictionary = u["presale"]
	var ids: Array = [int(ps.get("buyer_id", -1))]
	for id in ps.get("household", []):
		if not ids.has(int(id)):
			ids.append(int(id))
	return _members_of(gs, ids)


## Devuelve lo pagado por el comprador (si vive alguien de la familia) y libera la unidad.
static func _rescind(gs, b: Dictionary, u: Dictionary, refund: bool) -> float:
	var ps: Dictionary = u.get("presale", {})
	var paid := float(ps.get("paid", 0.0))
	var members := _presale_members(gs, u)
	var back := 0.0
	if refund and paid > 0.0 and not members.is_empty():
		back = paid
		gs.add_money(-paid)
		members[0].money += paid
		if b.has("re_project"):
			b["re_project"]["presale_received"] = float(b["re_project"]["presale_received"]) - paid
		_count(gs, "presales", -paid)
	_free(u)
	return back


## Entrega: el comprador paga el saldo con ahorros o con hipoteca; si no puede, se rescinde.
static func _deliver(gs, b: Dictionary, u: Dictionary) -> void:
	var ps: Dictionary = u["presale"]
	var members := _presale_members(gs, u)
	if members.is_empty():
		_free(u)   # Sin herederos: lo pagado queda como arras del promotor.
		return
	var price := float(ps["price"])
	var paid := float(ps["paid"])
	var balance := maxf(0.0, price - paid)
	var money := _household_money(members)
	var mortgage := {}
	if money < balance:
		var cash := money * 0.9
		var need := balance - cash
		mortgage = LoanContract.mortgage_offer(gs, need, _household_income(members))
		if mortgage.is_empty():
			var back := _rescind(gs, b, u, true)
			gs.notify("La familia %s no pudo pagar el saldo del apartamento %s: se devolvieron %s." % [members[0].last_name, u["code"], Fmt.money(back)], "negocio")
			return
		mortgage["amount"] = need
		LoanContract.grant_mortgage(gs, mortgage, members[0], need, unit_ref(b, u))
		_count(gs, "mortgages_player" if str(mortgage["lender"]).is_valid_int() else "mortgages_external", need)
	PopulationSim.pay_with(gs, members, balance)
	BusinessSim.earn(gs, b, balance, "ventas")
	BusinessSim.ledger_add(b, "ventas", paid)   # Lo recibido en preventa ya estaba en caja.
	_count(gs, "sales", price)
	_credit_sweep(gs, b, price)
	u["status"] = "vendida"
	u["owner_id"] = members[0].id
	u["household"] = _ids(members)
	u["presale"] = {}
	for m in members:
		m.home_id = int(b["id"])
		m.unpaid_days = 0
	_idx_dirty = true
	gs.notify("Entrega: la familia %s recibió el apartamento %s de %s (saldo %s%s)." % [members[0].last_name, u["code"], gs.building_label(b), Fmt.money(balance),
		", hipoteca con %s" % LoanContract.lender_label(gs, str(mortgage["lender"])) if not mortgage.is_empty() else ""], "negocio")


static func _presale_installments(gs) -> void:
	var limit := int(presale_cfg().get("default_missed", 3))
	for b in gs.buildings:
		if not b.has("re_project") or not has_units(b):
			continue
		for u in b["units"]:
			if str(u["status"]) != "preventa":
				continue
			var ps: Dictionary = u["presale"]
			var members := _presale_members(gs, u)
			if members.is_empty():
				_free(u)
				continue
			ps["buyer_id"] = members[0].id
			if int(ps["months_left"]) <= 0:
				continue
			var inst := float(ps["installment"])
			if PopulationSim.pay_with(gs, members, inst):
				gs.add_money(inst)
				ps["paid"] = float(ps["paid"]) + inst
				ps["months_left"] = int(ps["months_left"]) - 1
				ps["missed"] = 0
				b["re_project"]["presale_received"] = float(b["re_project"]["presale_received"]) + inst
				_count(gs, "presales", inst)
			else:
				ps["missed"] = int(ps["missed"]) + 1
				if int(ps["missed"]) >= limit:
					var back := _rescind(gs, b, u, true)
					gs.notify("Preventa rescindida: la familia %s dejó de pagar el apartamento %s (se devolvieron %s)." % [members[0].last_name, u["code"], Fmt.money(back)], "negocio")


# --- Hipotecas: impago ---------------------------------------------------------------------------------

## Gancho de BankSim._default: si una hipoteca no se paga, la unidad se embarga.
static func on_loan_default(gs, l: Dictionary, borrower: String) -> void:
	if str(l.get("purpose", "")) != "hipoteca":
		return
	var ref := str(l.get("unit_ref", ""))
	var u := find_unit(gs, ref)
	if u.is_empty() or str(u["status"]) != "vendida":
		return
	var b: Dictionary = gs.get_building(int(ref.split(":")[0]))
	if borrower == "":
		# Murió el deudor: la familia hereda la unidad (el banco asume la pérdida).
		return
	for id in _unit_people(u):
		if gs.citizens.has(int(id)) and gs.citizens[int(id)].home_id == int(b["id"]):
			gs.citizens[int(id)].home_id = -1
	var lender := str(l["lender"])
	if lender.is_valid_int() and gs.owned_by_player(b):
		_free(u)   # Tu banco recupera la garantía: la unidad vuelve a ti.
		u["for_sale"] = true
	else:
		_free(u)
		u["status"] = "embargada"
		u["seller"] = "externo" if not lender.is_valid_int() else "banco"
		u["for_sale"] = true
		u["price"] = snappedf(float(u["price"]) * float(LoanContract.mortgage_cfg().get("foreclosure_resale", 0.85)), 1.0)
	gs.notify("EMBARGO HIPOTECARIO: el apartamento %s de %s fue embargado por %s." % [u["code"], gs.building_label(b), LoanContract.lender_label(gs, lender)], "negocio")
	EventBus.citizens_moved.emit()


# --- Ciclo mensual -------------------------------------------------------------------------------------

static func monthly(gs) -> void:
	init_state(gs)
	var led: Dictionary = gs.realestate
	led["last_month"] = led.get("month", {})
	led["month"] = {}
	_update_demand(gs)
	for b in gs.buildings:
		if not is_multi(b):
			continue
		ensure_units(gs, b)
		if gs.is_active(b):
			_reconcile(gs, b)
			_auto_prices(gs, b)
			if gs.owned_by_player(b):
				_condo_fees(gs, b)
	_presale_installments(gs)
	_market(gs)
	_idx_dirty = true


static func _update_demand(gs) -> void:
	var want := 0.0
	var households := 0
	var occ := PopulationSim.home_occupancy(gs)
	for members in MarketSim.households(gs):
		households += 1
		var head: Citizen = members[0]
		var h: Dictionary = gs.get_building(head.home_id)
		if h.is_empty():
			want += 1.0
		elif int(occ.get(head.home_id, 0)) > gs.building_capacity(h):
			want += 1.0
		elif str(h.get("owner", "")) == "pueblo":
			want += 0.3
	var vacant := 0.0
	for b in gs.buildings:
		if has_units(b) and gs.is_active(b):
			for u in b["units"]:
				if str(u["status"]) in ["disponible", "embargada"]:
					vacant += 1.0
	var pc := pricing_cfg()
	var ratio := (want - vacant) / maxf(5.0, households * 0.25)
	var target := clampf(1.0 + 0.15 * ratio, float(pc.get("demand_min", 0.9)), float(pc.get("demand_max", 1.15)))
	var d := demand(gs)
	gs.realestate["demand"] = d + (target - d) * 0.3


## Inquilinos que se fueron, murieron o no pagan; dueños fallecidos.
static func _reconcile(gs, b: Dictionary) -> void:
	var bid := int(b["id"])
	var evict := int(GameData.citizens.get("eviction_unpaid_days", 30))
	for u in b["units"]:
		var st := str(u["status"])
		if st != "arrendada" and st != "vendida":
			continue
		var living := []
		for id in _unit_people(u):
			if gs.citizens.has(int(id)) and gs.citizens[int(id)].home_id == bid:
				living.append(gs.citizens[int(id)])
		if st == "arrendada":
			var tenant: Citizen = gs.citizens.get(int(u["tenant_id"]))
			if tenant != null and gs.owned_by_player(b) and tenant.unpaid_days >= evict and not gs.is_player(tenant.id):
				for m in living:
					m.home_id = -1
					m.unpaid_days = 0
				gs.notify("La familia %s fue desalojada del apartamento %s de %s por no pagar el arriendo." % [tenant.last_name, u["code"], gs.building_label(b)], "negocio")
				_count(gs, "evictions", 1.0)
				_free(u)
				continue
			if living.is_empty():
				_free(u)
				_count(gs, "moved_out", 1.0)
				continue
			if tenant == null or tenant.home_id != bid:
				u["tenant_id"] = living[0].id
			u["household"] = _ids(living)
		else:
			var owner: Citizen = gs.citizens.get(int(u["owner_id"]))
			if owner != null:
				if living.size() > 0:
					u["household"] = _ids(living)
				continue
			if not living.is_empty():
				u["owner_id"] = living[0].id   # Herencia a la familia que vive ahí.
				u["household"] = _ids(living)
			else:
				# Sin herederos: herencia vacante, el pueblo la remata y el dinero va al tesoro.
				_free(u)
				u["status"] = "embargada"
				u["seller"] = "gobierno"
				u["for_sale"] = true
	_idx_dirty = true
	_assign_residents(gs, b)


## Precios automáticos (demanda, época, inflación) para unidades libres no fijadas a mano.
static func _auto_prices(gs, b: Dictionary) -> void:
	if not gs.owned_by_player(b):
		return
	var prices := unit_prices(gs, int(b["level"]), str(b.get("tier", "normal")))
	var units: Array = b["units"]
	var svc := GridSim.home_value_mult(gs, b)   # Redes: sin luz/agua exigidas valen menos.
	for i in range(mini(units.size(), prices.size())):
		var u: Dictionary = units[i]
		if str(u["status"]) == "disponible" and not bool(u.get("manual", false)):
			u["price"] = snappedf(float(prices[i]["price"]) * svc, 1.0)
			u["rent"] = snappedf(float(prices[i]["rent"]) * svc, 0.01)


## Cuota de administración: los dueños de unidades pagan su parte del mantenimiento.
static func _condo_fees(gs, b: Dictionary) -> void:
	var upkeep := upkeep_month(gs, int(b["level"])) * float(cfg().get("condo_fee_share", 1.0))
	var units: Array = b["units"]
	var area := 0.0
	for u in units:
		area += float(u["area"])
	for u in units:
		if str(u["status"]) != "vendida":
			continue
		var fee := upkeep * float(u["area"]) / maxf(1.0, area)
		var members := _members_of(gs, _unit_people(u))
		if members.is_empty() or fee <= 0.0:
			continue
		if PopulationSim.pay_with(gs, members, fee):
			BusinessSim.earn(gs, b, fee, "alquileres")
			_count(gs, "fees", fee)


static func _home_score(gs, b: Dictionary, u: Dictionary) -> float:
	return MarketSim.home_quality(gs, b) + 0.02 * float(u["floor"])


## Mercado mensual: familias que arriendan, compran de contado, con hipoteca o sobre planos.
static func _market(gs) -> void:
	var rent_offers := []
	var sale_offers := []
	for b in gs.buildings:
		if not has_units(b):
			continue
		var active: bool = gs.is_active(b)
		var mine: bool = gs.owned_by_player(b)
		var in_project: bool = b.has("re_project") and mine
		for u in b["units"]:
			var st := str(u["status"])
			if active and mine and st == "disponible" and bool(u.get("for_rent", false)):
				rent_offers.append([b, u])
			if bool(u.get("for_sale", false)) and ((st == "disponible" and mine and (active or in_project)) or (st == "embargada" and active)):
				sale_offers.append([b, u])
	if rent_offers.is_empty() and sale_offers.is_empty():
		return
	var occ := PopulationSim.home_occupancy(gs)
	var chance := float(LoanContract.mortgage_cfg().get("monthly_buy_chance", 0.35))
	var presale_chance := float(presale_cfg().get("monthly_chance", 0.35))
	var owners := {}
	for b in gs.buildings:
		if has_units(b):
			for u in b["units"]:
				if str(u["status"]) in ["vendida", "preventa"]:
					for id in _unit_people(u):
						owners[int(id)] = true
	var moved := false
	var fair := {}
	for members in MarketSim.households(gs):
		if sale_offers.is_empty() and rent_offers.is_empty():
			break
		var head: Citizen = members[0]
		if members.any(func(m): return gs.is_player(m.id)) or owners.has(head.id):
			continue
		var cur: Dictionary = gs.get_building(head.home_id)
		if not cur.is_empty() and int(cur.get("owner_id", -1)) == head.id:
			continue   # Ya es dueño de su casa.
		var size: int = members.size()
		var homeless := cur.is_empty()
		var crowded: bool = not homeless and int(occ.get(head.home_id, 0)) > gs.building_capacity(cur)
		var cur_q := 0.0 if homeless else MarketSim.home_quality(gs, cur)
		var money := _household_money(members)
		var income := _household_income(members)
		var fit := mini(size, 6)
		# 1) Compra (contado, hipoteca o preventa).
		if not sale_offers.is_empty() and income > 0.0:
			var bought := false
			for i in range(sale_offers.size()):
				var b: Dictionary = sale_offers[i][0]
				var u: Dictionary = sale_offers[i][1]
				if int(u["capacity"]) < fit:
					continue
				if not homeless and not crowded and _home_score(gs, b, u) <= cur_q:
					continue
				var key := "%d" % int(b["id"])
				if not fair.has(key):
					fair[key] = unit_prices(gs, int(b.get("target_level", b["level"])), str(b.get("tier", "normal")))
				var fp: Array = fair[key]
				var idx := int(u["id"]) - 1
				var fair_price := float(fp[idx]["price"]) if idx < fp.size() else float(u["price"])
				var price := float(u["price"])
				var over := price / maxf(1.0, fair_price) - 1.0
				if over > 0.3 or (over > 0.0 and gs.rng.randf() < over / 0.3):
					continue
				if not gs.is_active(b):
					# Preventa sobre planos.
					var down := price * float(presale_cfg().get("down_share", 0.1))
					if money < down * 1.2 or gs.rng.randf() > presale_chance:
						continue
					var need := price * (1.0 - float(presale_cfg().get("down_share", 0.1)) - float(presale_cfg().get("during_share", 0.2)))
					if money < price and LoanContract.mortgage_offer(gs, need, income).is_empty():
						continue
					_presell(gs, b, u, members)
				else:
					if gs.rng.randf() > chance:
						continue
					var mortgage := {}
					if money < price * 1.05:
						var down := price * float(LoanContract.mortgage_cfg().get("down_share", 0.2))
						if money < down * 1.05:
							continue
						var loan_amt := price - money * 0.9
						mortgage = LoanContract.mortgage_offer(gs, loan_amt, income)
						if mortgage.is_empty():
							continue
						mortgage["amount"] = loan_amt
					_sell_unit(gs, b, u, members, price, mortgage)
					occ[int(b["id"])] = int(occ.get(int(b["id"]), 0)) + size
				sale_offers.remove_at(i)
				owners[head.id] = true
				bought = true
				moved = true
				break
			if bought:
				continue
		# 2) Arriendo.
		if rent_offers.is_empty():
			continue
		var wants: bool = homeless or crowded or gs.rng.randf() < 0.25
		if not wants:
			continue
		var best := -1
		var best_score := -INF
		for i in range(rent_offers.size()):
			var b: Dictionary = rent_offers[i][0]
			var u: Dictionary = rent_offers[i][1]
			if int(u["capacity"]) < fit or int(b["id"]) == head.home_id:
				continue
			var q := _home_score(gs, b, u)
			if not homeless and not crowded and q <= cur_q:
				continue
			var rent := float(u["rent"])
			if money < rent * 2.0 or (income * 0.4 < rent and money < rent * 12.0):
				continue
			var score := q * 10.0 - rent / maxf(1.0, money) * 20.0
			if score > best_score:
				best_score = score
				best = i
		if best >= 0:
			var b: Dictionary = rent_offers[best][0]
			var u: Dictionary = rent_offers[best][1]
			for m in members:
				m.home_id = int(b["id"])
				m.unpaid_days = 0
			_rent_to(gs, u, members)
			occ[int(b["id"])] = int(occ.get(int(b["id"]), 0)) + size
			rent_offers.remove_at(best)
			moved = true
			_count(gs, "rentals", 1.0)
			gs.notify("La familia %s arrendó el apartamento %s de %s por %s/mes." % [head.last_name, u["code"], gs.building_label(b), Fmt.money2(float(u["rent"]))], "negocio")
	if moved:
		_idx_dirty = true
		EventBus.citizens_moved.emit()


# --- Consultas para la interfaz ------------------------------------------------------------------------

static func counts(b: Dictionary) -> Dictionary:
	var out := {"total": 0, "disponible": 0, "arrendada": 0, "vendida": 0, "preventa": 0, "embargada": 0,
		"rent_month": 0.0, "for_sale": 0, "for_rent": 0}
	for u in b.get("units", []):
		out["total"] += 1
		var st := str(u["status"])
		out[st] = int(out.get(st, 0)) + 1
		if st == "arrendada":
			out["rent_month"] += float(u["rent"])
		if st == "disponible" and bool(u.get("for_sale", false)):
			out["for_sale"] += 1
		if st == "disponible" and bool(u.get("for_rent", false)):
			out["for_rent"] += 1
	return out


## Valor de lo que aún es tuyo en un edificio con unidades (para patrimonio y embargo).
static func owned_value(gs, b: Dictionary) -> float:
	if not gs.is_active(b):
		return BusinessSim.period_value(b, "total", "obras") * 0.7
	var v := 0.0
	for u in b["units"]:
		if str(u["status"]) in ["disponible", "arrendada"]:
			v += float(u["price"])
		elif str(u["status"]) == "preventa":
			v += maxf(0.0, float(u["price"]) - float(u["presale"].get("paid", 0.0)))
	return v


## No se puede demoler un edificio con unidades de ciudadanos (vendidas o en preventa).
static func demolish_block_reason(b: Dictionary) -> String:
	for u in b.get("units", []):
		if str(u["status"]) == "vendida":
			return "No puedes demoler: hay apartamentos vendidos a ciudadanos."
		if str(u["status"]) == "preventa":
			return "Hay preventas: cancela el proyecto (devuelve lo pagado) antes de demoler."
	return ""


static func player_projects(gs) -> Array:
	var out := []
	for b in gs.buildings:
		if gs.owned_by_player(b) and (has_units(b) or b.has("re_project")):
			out.append(b)
	return out


## Fija precio/renta de una unidad (queda en modo manual) o de todas las libres.
static func set_unit_terms(b: Dictionary, idx: int, price: float, rent: float) -> void:
	var u: Dictionary = b["units"][idx]
	if price >= 0.0:
		u["price"] = price
	if rent >= 0.0:
		u["rent"] = rent
	u["manual"] = true


static func set_all(b: Dictionary, key: String, on: bool) -> void:
	for u in b.get("units", []):
		if str(u["status"]) == "disponible":
			u[key] = on


static func reset_prices(gs, b: Dictionary) -> void:
	for u in b.get("units", []):
		u["manual"] = false
	_auto_prices(gs, b)
