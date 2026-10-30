class_name CompanyReportSim
extends RefCounted
## "Mis empresas" (docs/MIS_EMPRESAS.md): lectura consolidada de cada empresa del jugador para la ventana del HUD.
## Solo LEE el estado y no mueve dinero. Lo único que escribe es el historial mensual de resultados por edificio
## (b["pnl_hist"] = [[día, ingresos, costos, transferido], …], hasta HIST_MAX meses), que se llena al cerrar cada mes
## (TerrenosCostosSim.monthly, después de CostSim). Partidas viejas: sin historial, la gráfica arranca con el libro
## del mes anterior y se completa mes a mes.
##
## Utilidad de gestión de una empresa = ingresos del libro + producción entregada al almacén (a precio de mercado)
##   − costos del libro (todo lo que no es ingreso ni inversión).
## Una fábrica que entrega al almacén no factura (las ventas las registra la tienda, el contrato o la exportación);
## sin esa transferencia valorada se vería siempre en pérdida. La utilidad TOTAL del grupo NO suma transferencias:
## es el consolidado contable (TransportDivSim.consolidated), así nada se cuenta dos veces.

const HIST_MAX := 60
const GROUPS := ["produccion", "comercio", "transporte", "propiedades"]
const GROUP_LABELS := {"produccion": "Producción", "comercio": "Comercio y servicios", "transporte": "Transporte", "propiedades": "Inmuebles y otros"}
const STATUS_LABELS := {"activo": "Activa", "construccion": "En obra", "mejorando": "Mejorando", "cerrado": "Cerrada"}
const SORTS := ["profit", "margin", "roi", "income", "level", "name"]
const SORT_LABELS := {"profit": "Utilidad del mes", "margin": "Margen", "roi": "ROI anual", "income": "Ingresos", "level": "Nivel", "name": "Nombre"}
const FILTERS := ["todas", "rentables", "perdidas", "obra", "cerradas"]
const FILTER_LABELS := {"todas": "Todas", "rentables": "Rentables", "perdidas": "Con pérdidas", "obra": "En obra o mejora", "cerradas": "Cerradas"}
const INCOME_LABELS := {"ventas": "Ventas", "alquileres": "Alquileres", "intereses": "Intereses", "subsidios": "Subsidios"}


# --- Clasificación ------------------------------------------------------------------------------------

static func group_of(def: Dictionary) -> String:
	if str(def.get("category", "")) != "negocio":
		return "propiedades"
	if TransportDivSim.is_transport_def(def):
		return "transporte"
	if CostSim.is_producer_def(def):
		return "produccion"
	return "comercio"


static func companies(gs) -> Array:
	return gs.player_buildings()


static func is_warehouse_output(gs, b: Dictionary) -> bool:
	var def: Dictionary = gs.building_def(b)
	var ld: Dictionary = gs.level_def(b)
	return CostSim.is_producer_def(def) and LogisticsSim.uses_chain(def, ld) and LogisticsSim.outputs_to_warehouse(def, ld)


# --- Números del mes ----------------------------------------------------------------------------------

## Producción entregada al almacén valorada a precio de mercado. period: "last_month" (costeo cerrado) | "month".
static func transfer_value(gs, b: Dictionary, period := "last_month") -> float:
	if not is_warehouse_output(gs, b):
		return 0.0
	if period == "month":
		return float(b.get("cost_units_m", 0.0)) * EconomySim.market_price(gs, CostSim.product_of(gs.building_def(b)))
	var c: Dictionary = b.get("costing", {})
	return float(c.get("units", 0.0)) * float(c.get("price", 0.0))


static func invested(b: Dictionary) -> float:
	return BusinessSim.period_value(b, "total", "obras")


## Utilidad de los últimos 12 meses del historial (o el último mes × 12 si hay menos). NAN si no hay datos.
static func annual_profit(b: Dictionary, fallback_month: float) -> float:
	var h: Array = b.get("pnl_hist", [])
	if h.size() >= 12:
		var s := 0.0
		for e in h.slice(h.size() - 12):
			s += float(e[1]) + float(e[3]) - float(e[2])
		return s
	if h.size() >= 2:
		var s2 := 0.0
		for e in h:
			s2 += float(e[1]) + float(e[3]) - float(e[2])
		return s2 / h.size() * 12.0
	return fallback_month * 12.0


## Fila de la lista: todo lo que muestra la tarjeta. `staff` = BusinessSim.employee_index (opcional, para no
## recorrer a los ciudadanos por cada empresa).
static func row(gs, b: Dictionary, staff = null) -> Dictionary:
	var def: Dictionary = gs.building_def(b)
	var status := str(b.get("status", "activo"))
	var inc := TransportDivSim.income(b)
	var cost := TransportDivSim.expenses(b)
	var tr := transfer_value(gs, b)
	var revenue := inc + tr
	var profit := revenue - cost
	var inv := invested(b)
	var has_data := revenue > 0.0 or cost > 0.0
	var margin := profit / revenue if revenue > 0.0 else NAN
	var annual := annual_profit(b, profit)
	var roi := annual / inv if inv > 0.0 and has_data else NAN
	var emps := 0
	var list: Array = staff.get(int(b["id"]), []) if staff is Dictionary else gs.employees_of(int(b["id"]))
	for c in list:
		if c.job_kind == "empleo":
			emps += 1
	var jobs := MineSim.jobs(gs, b) if BusinessSim.is_business(b) else 0
	var cls := ""
	if status != "activo":
		cls = "cerrada" if status == "cerrado" else "obra"
	elif not has_data:
		cls = "sin datos"
	elif is_nan(margin) or margin < -0.05:
		cls = "perdidas" if profit < 0.0 else "equilibrio"
	elif margin > 0.05:
		cls = "rentable"
	else:
		cls = "equilibrio"
	var alerts := []
	if BusinessSim.is_business(b) and status == "activo":
		if emps < jobs:
			alerts.append("%d vacantes" % (jobs - emps))
		if int(b.get("loss_months", 0)) > 0:
			alerts.append("%d meses con pérdidas" % int(b["loss_months"]))
		var cs := str(b.get("chain_status", ""))
		if cs != "":
			alerts.append(cs)
	return {"id": int(b["id"]), "name": gs.building_label(b), "type": str(b.get("type", "")),
		"type_label": str(def.get("label", b.get("type", ""))), "group": group_of(def),
		"level": int(b.get("level", 1)), "max_level": (def.get("levels", []) as Array).size(),
		"status": status, "status_label": STATUS_LABELS.get(status, status), "cls": cls,
		"income": inc, "transfer": tr, "revenue": revenue, "costs": cost, "profit": profit,
		"ledger_profit": inc - cost, "margin": margin, "invested": inv, "annual": annual, "roi": roi,
		"month_profit": BusinessSim.period_profit(b, "month") + transfer_value(gs, b, "month"),
		"employees": emps, "jobs": jobs, "alerts": alerts, "has_data": has_data,
		"value": EconomySim.property_value(gs, b)}


static func rows(gs) -> Array:
	var staff := BusinessSim.employee_index(gs)
	var out := []
	for b in companies(gs):
		out.append(row(gs, b, staff))
	return out


# --- Orden y filtro -----------------------------------------------------------------------------------

static func _key(r: Dictionary, key: String) -> float:
	var v := float(r.get(key, 0.0))
	return -INF if is_nan(v) else v


static func sort_rows(list: Array, key := "profit", desc := true) -> Array:
	var out := list.duplicate()
	if key == "name":
		out.sort_custom(func(a, b): return (str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0) != desc)
	else:
		out.sort_custom(func(a, b):
			var x := _key(a, key)
			var y := _key(b, key)
			if x == y:
				return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0
			return x > y if desc else x < y)
	return out


## filter: FILTERS · group: "" o uno de GROUPS · text: búsqueda en nombre y tipo.
static func filter_rows(list: Array, filter := "todas", group := "", text := "") -> Array:
	var t := text.strip_edges().to_lower()
	return list.filter(func(r):
		if group != "" and str(r["group"]) != group:
			return false
		if t != "" and not (str(r["name"]).to_lower().contains(t) or str(r["type_label"]).to_lower().contains(t)):
			return false
		match filter:
			"rentables":
				return str(r["cls"]) == "rentable"
			"perdidas":
				return bool(r["has_data"]) and float(r["profit"]) < 0.0 and str(r["status"]) != "cerrado"
			"obra":
				return str(r["status"]) in ["construccion", "mejorando"]
			"cerradas":
				return str(r["status"]) == "cerrado"
		return true)


# --- Resumen del grupo --------------------------------------------------------------------------------

## {net_worth, assets, debt, money, result (consolidado contable del mes anterior), result_month (en curso),
##  sum_mgmt, count, active, best, worst (filas o {}), by_group {grupo: utilidad}}
static func summary(gs, list = null) -> Dictionary:
	var rs: Array = list if list is Array else rows(gs)
	var cons := TransportDivSim.consolidated(gs)
	var month := 0.0
	for b in companies(gs):
		month += BusinessSim.period_profit(b, "month")
	var best := {}
	var worst := {}
	var active := 0
	var sum_mgmt := 0.0
	var by_group := {}
	for r in rs:
		sum_mgmt += float(r["profit"])
		by_group[r["group"]] = float(by_group.get(r["group"], 0.0)) + float(r["profit"])
		if str(r["status"]) != "activo":
			continue
		active += 1
		if not bool(r["has_data"]) or (str(r["group"]) == "propiedades" and float(r["revenue"]) <= 0.0):
			continue
		if best.is_empty() or _rank(r) > _rank(best):
			best = r
		if worst.is_empty() or _rank(r) < _rank(worst):
			worst = r
	if not best.is_empty() and best == worst and rs.size() > 1:
		worst = {}
	return {"net_worth": EconomySim.net_worth(gs), "assets": EconomySim.player_assets(gs), "debt": EconomySim.player_debt(gs),
		"money": float(gs.money), "result": float(cons["result"]), "income": float(cons["income"]), "expenses": float(cons["expenses"]),
		"internal": float(cons["internal"]), "result_month": month, "sum_mgmt": sum_mgmt, "count": rs.size(), "active": active,
		"best": best, "worst": worst, "by_group": by_group}


## Rentabilidad para el ranking: ROI anual si hay inversión; si no, margen.
static func _rank(r: Dictionary) -> float:
	if not is_nan(float(r["roi"])):
		return float(r["roi"])
	return float(r["margin"]) if not is_nan(float(r["margin"])) else -INF


static func rank_text(r: Dictionary) -> String:
	if r.is_empty():
		return "—"
	if not is_nan(float(r["roi"])):
		return "ROI %s" % Fmt.pct_1(float(r["roi"]) * 100.0)
	if not is_nan(float(r["margin"])):
		return "margen %s" % Fmt.pct_1(float(r["margin"]) * 100.0)
	return "—"


# --- Historial ----------------------------------------------------------------------------------------

## Al cerrar el mes (después de BusinessSim.monthly y CostSim.monthly): una muestra por empresa.
static func monthly(gs) -> void:
	for b in companies(gs):
		var h: Array = b.get("pnl_hist", [])
		h.append([gs.today(), snappedf(TransportDivSim.income(b), 0.01), snappedf(TransportDivSim.expenses(b), 0.01), snappedf(transfer_value(gs, b), 0.01)])
		while h.size() > HIST_MAX:
			h.pop_front()
		b["pnl_hist"] = h


## Series para la gráfica: {days, income, costs, profit}. Sin historial (partida vieja o empresa nueva) usa el
## libro del mes anterior como único punto.
static func history(gs, b: Dictionary) -> Dictionary:
	var h: Array = b.get("pnl_hist", [])
	if h.is_empty() and not (b.get("ledger", {}).get("last_month", {}) as Dictionary).is_empty():
		h = [[gs.today(), TransportDivSim.income(b), TransportDivSim.expenses(b), transfer_value(gs, b)]]
	var out := {"days": [], "income": [], "costs": [], "profit": []}
	for e in h:
		var rev := float(e[1]) + float(e[3])
		out["days"].append(int(e[0]))
		out["income"].append(rev)
		out["costs"].append(float(e[2]))
		out["profit"].append(rev - float(e[2]))
	return out


# --- Ficha: compras, ventas, personal, vehículos y módulos ----------------------------------------------

## Unidades producidas por mes (costeo cerrado; si no hay, estimado con la plantilla de hoy).
static func units_month(gs, b: Dictionary) -> float:
	var c: Dictionary = b.get("costing", {})
	if float(c.get("units", 0.0)) > 0.0:
		return float(c["units"])
	return BusinessSim.expected_output(gs, b) * 30.0 if gs.is_active(b) else 0.0


## Qué compra: [{good, label, qty, unit_price, market, total, suppliers [texto]}] (insumos de la receta) y una
## fila por los materiales por unidad, el mantenimiento y la energía.
static func purchases(gs, b: Dictionary) -> Array:
	var def: Dictionary = gs.building_def(b)
	var ld: Dictionary = gs.level_def(b)
	var out := []
	var units := units_month(gs, b)
	var L: Dictionary = b.get("ledger", {}).get("last_month", {})
	if LogisticsSim.uses_chain(def, ld):
		var inputs := LogisticsSim.recipe_inputs(def, ld)
		for g in inputs:
			var good := str(g)
			var qty := float(inputs[g]) * units
			var up := CostSim.input_unit_value(gs, good)
			out.append({"good": good, "label": GameData.good_label(good), "qty": qty, "unit_price": up,
				"market": EconomySim.market_price(gs, good), "import": LogisticsSim.buy_unit_price(gs, good),
				"total": qty * up, "suppliers": suppliers_of(gs, b, good), "kind": "insumo"})
	var uc: float = float(ld.get("unit_cost", 0.0)) * gs.price_mult()
	var share := float(FlowSim.cfg().get("import_share", {}).get("insumos", FlowSim.cfg().get("default_import_share", 0.3)))
	if uc > 0.0:
		out.append({"good": "", "label": "Materiales por unidad", "qty": units, "unit_price": uc, "market": uc, "import": 0.0,
			"total": uc * units, "kind": "materiales",
			"suppliers": ["Proveedores del pueblo (vecinos y empresas NPC); %s se importa" % Fmt.pct(share * 100.0)]})
	var maint := float(L.get("mantenimiento", 0.0)) + float(L.get("reparaciones", 0.0))
	if maint > 0.0:
		out.append({"good": "", "label": "Mantenimiento y reparaciones", "qty": 0.0, "unit_price": 0.0, "market": 0.0, "import": 0.0,
			"total": maint, "kind": "servicio", "suppliers": ["Artesanos y proveedores del pueblo (parte importada)"]})
	if EnergySim.grid_active(gs) and EnergySim.level_demand_kw(def, ld) > 0.0:
		var kw := EnergySim.level_demand_kw(def, ld)
		out.append({"good": "", "label": "Electricidad", "qty": kw * 30.0, "unit_price": EnergySim.price(gs), "market": EnergySim.price(gs), "import": 0.0,
			"total": kw * 30.0 * EnergySim.price(gs), "kind": "energia", "suppliers": ["Red eléctrica (generadoras conectadas)"]})
	return out


## A quién le compra un insumo: tus fábricas que lo producen, rutas que lo traen, contratos de compra, empresas NPC
## que lo venden y, si no hay nada, el mercado del pueblo o la importación.
static func suppliers_of(gs, b: Dictionary, good: String) -> Array:
	var out := []
	for o in gs.buildings:
		if int(o["id"]) == int(b["id"]):
			continue
		if CostSim.product_of(gs.building_def(o)) != good:
			continue
		if gs.owned_by_player(o):
			out.append("Tu empresa: %s" % gs.building_label(o))
	var targets := WarehouseSim.chain_ids(gs, b)
	targets.append(int(b["id"]))
	for r in LogisticsSim.routes(gs):
		if str(r.get("good", "")) != good or not bool(r.get("active", true)) or not targets.has(int(r.get("to", -1))):
			continue
		if bool(r.get("buy", false)):
			out.append("Ruta %s: compra afuera a %s/u" % [str(r.get("name", "L%d" % int(r["id"]))), Fmt.money2(LogisticsSim.buy_unit_price(gs, good))])
		else:
			out.append("Ruta %s desde %s" % [str(r.get("name", "L%d" % int(r["id"]))), LogisticsSim.endpoint_label(gs, int(r.get("from", 0)))])
	for k in ContractSim.active_contracts(gs):
		if ContractSim.is_buy(k) and str(k.get("good", "")) == good:
			out.append("Contrato de compra: %s (%s/u)" % [str(k.get("client_name", "")), Fmt.money2(float(k.get("unit_price", 0.0)))])
	for t in gs.trade.get("contracts", []):
		if str(t.get("good", "")) == good and str(t.get("kind", "")) == TradeSim.KIND_BUY and bool(t.get("active", true)):
			out.append("Importación automática de %s" % str(TradeSim.town(gs, str(t.get("town_id", ""))).get("name", "otro pueblo")))
	var npc := 0
	for o in NpcBusinessSim.npc_buildings(gs):
		if CostSim.product_of(gs.building_def(o)) == good and str(o.get("npc_state", "")) == NpcBusinessSim.STATE_OPEN:
			npc += 1
	if npc > 0:
		out.append("%d empresa(s) NPC del pueblo lo producen" % npc)
	if out.is_empty():
		out.append("Mercado del pueblo o importación (%s/u)" % Fmt.money2(EconomySim.market_price(gs, good)))
	return out


## Qué vende y por qué canal: [{label, channel, detail, amount}] con lo facturado el mes anterior por concepto.
static func sales(gs, b: Dictionary) -> Array:
	var def: Dictionary = gs.building_def(b)
	var out := []
	var product := CostSim.product_of(def)
	var L: Dictionary = b.get("ledger", {}).get("last_month", {})
	if is_warehouse_output(gs, b):
		var whs := []
		for w in WarehouseSim.chain_ids(gs, b):
			whs.append(WarehouseSim.label_of(gs, int(w)))
		out.append({"label": GameData.good_label(product), "channel": "Entrega al almacén",
			"detail": ", ".join(whs) if not whs.is_empty() else "sin almacén", "amount": transfer_value(gs, b)})
		for d in downstream(gs, product):
			out.append({"label": GameData.good_label(product), "channel": d[0], "detail": d[1], "amount": -1.0})
	elif CostSim.is_producer_def(def):
		out.append({"label": GameData.good_label(product), "channel": "Venta directa en el local",
			"detail": "Ciudadanos y empresas del pueblo a %s/u" % Fmt.money2(CostSim.sale_ref_price(gs, b)), "amount": float(L.get("ventas", 0.0))})
		for d in downstream(gs, product, false):
			out.append({"label": GameData.good_label(product), "channel": d[0], "detail": d[1], "amount": -1.0})
	elif TransportDivSim.is_transport_def(def):
		var t := TransportDivSim.st(gs)
		var row: Dictionary = t["last"].get("tkm", {}).get(str(int(b["id"])), {})
		var names := []
		for k in row:
			var o: Dictionary = gs.get_building(int(k))
			if not o.is_empty():
				names.append(gs.building_label(o))
		var internal := float(b.get("fletes_internos_last", 0.0))
		out.append({"label": "Fletes", "channel": "Empresa aparte: fletes a tus negocios" if TransportDivSim.org(b) == "empresa" else "División interna (costo repartido, no factura)",
			"detail": ", ".join(names) if not names.is_empty() else "sin envíos el mes pasado", "amount": internal})
		if float(b.get("fletes_npc_last", 0.0)) > 0.0:
			out.append({"label": "Fletes", "channel": "Clientes NPC", "detail": "Empresas del pueblo con carga", "amount": float(b["fletes_npc_last"])})
	if bool(def.get("shop", false)) or str(b.get("type", "")) == "tienda" or bool(def.get("warehouse_shop", false)):
		out.append({"label": "Productos del almacén", "channel": "Tienda", "detail": "Vecinos que compran en tu tienda", "amount": float(L.get("ventas", 0.0))})
	for k in INCOME_KEYS_EXTRA:
		if float(L.get(k, 0.0)) > 0.0:
			out.append({"label": INCOME_LABELS[k], "channel": {"alquileres": "Inquilinos", "intereses": "Préstamos de tu banco", "subsidios": "Gobierno"}[k],
				"detail": "", "amount": float(L[k])})
	if out.is_empty() and float(L.get("ventas", 0.0)) > 0.0:
		out.append({"label": str(def.get("label", "")), "channel": "Servicio a clientes", "detail": "", "amount": float(L["ventas"])})
	return out


const INCOME_KEYS_EXTRA := ["alquileres", "intereses", "subsidios"]


## A dónde sigue el producto después del almacén: [canal, detalle].
static func downstream(gs, product: String, include_shops := true) -> Array:
	var out := []
	if include_shops and bool(GameData.goods.get(product, {}).get("shop_sale", false)):
		var shops := []
		for o in gs.buildings:
			if gs.owned_by_player(o) and (str(o.get("type", "")) == "tienda" or bool(gs.building_def(o).get("warehouse_shop", false))):
				shops.append(gs.building_label(o))
		if not shops.is_empty():
			out.append(["Tus tiendas", ", ".join(shops)])
	for k in ContractSim.active_contracts(gs):
		if not ContractSim.is_buy(k) and str(k.get("good", "")) == product:
			out.append(["Contrato de venta", "%s · %s/u" % [str(k.get("client_name", "")), Fmt.money2(float(k.get("unit_price", 0.0)))]])
	for t in gs.trade.get("contracts", []):
		if str(t.get("good", "")) == product and str(t.get("kind", "")) == TradeSim.KIND_SELL and bool(t.get("active", true)):
			out.append(["Exportación", str(TradeSim.town(gs, str(t.get("town_id", ""))).get("name", "otro pueblo"))])
	for r in LogisticsSim.routes(gs):
		if str(r.get("good", "")) == product and bool(r.get("active", true)):
			var to_b: Dictionary = gs.get_building(int(r.get("to", -1)))
			if not to_b.is_empty() and CostSim.product_of(gs.building_def(to_b)) != product:
				out.append(["Ruta a otra empresa tuya", "%s → %s" % [str(r.get("name", "L%d" % int(r["id"]))), gs.building_label(to_b)]])
	return out


## Personal: {employees, jobs, payroll (sueldos del mes anterior), avg_wage, people [{name, wage, prod}]}.
static func staff(gs, b: Dictionary) -> Dictionary:
	var skill := str(gs.building_def(b).get("skill", ""))
	var people := []
	var wages := 0.0
	for c in gs.employees_of(int(b["id"])):
		if c.job_kind != "empleo":
			continue
		wages += c.wage
		people.append({"id": c.id, "name": c.full_name(), "wage": c.wage, "prod": BusinessSim.productivity(c, skill)})
	people.sort_custom(func(x, y): return float(x["prod"]) > float(y["prod"]))
	var L: Dictionary = b.get("ledger", {}).get("last_month", {})
	return {"employees": people.size(), "jobs": MineSim.jobs(gs, b) if BusinessSim.is_business(b) else 0,
		"payroll": float(L.get("salarios", 0.0)) + float(L.get("salarios_negro", 0.0)),
		"avg_wage": wages / people.size() if not people.is_empty() else 0.0, "people": people}


## Vehículos con base en el edificio: [{id, label, mode, model}].
static func vehicles(gs, b: Dictionary) -> Array:
	var out := []
	for v in LogisticsSim.vehicles_of(gs, int(b["id"])):
		out.append({"id": int(v["id"]), "label": LogisticsSim.vehicle_label(gs, v), "mode": str(v.get("mode", "")), "model": str(v.get("model", ""))})
	return out


## Módulos: [{id, label, level, max, name}] solo los que aplican al edificio.
static func modules(gs, b: Dictionary) -> Array:
	var out := []
	for m in ModulesSim.module_ids():
		if not ModulesSim.applies(gs, b, str(m)):
			continue
		var lvl := ModulesSim.level(b, str(m))
		out.append({"id": str(m), "label": ModulesSim.label(str(m)), "level": lvl, "max": ModulesSim.max_level(str(m)),
			"name": str(ModulesSim.cur(b, str(m)).get("label", ModulesSim.cur(b, str(m)).get("name", "")))})
	return out


## Costo por unidad: el costeo cerrado del mes (CostSim) o, si aún no hay, la calculadora a plantilla completa.
## {source: "real"|"estimado"|"", data}.
static func unit_cost(gs, b: Dictionary) -> Dictionary:
	if not CostSim.is_producer_def(gs.building_def(b)):
		return {"source": "", "data": {}}
	var c: Dictionary = b.get("costing", {})
	if float(c.get("units", 0.0)) > 0.0:
		return {"source": "real", "data": c}
	return {"source": "estimado", "data": CostSim.estimate(gs, str(b["type"]), int(b.get("level", 1)))}


## Precios actuales: {sell, market, product, auto} (sell = el que fijaste o el de mercado si entrega al almacén).
static func prices(gs, b: Dictionary) -> Dictionary:
	var def: Dictionary = gs.building_def(b)
	var product := CostSim.product_of(def)
	if not GameData.goods.has(product):
		return {"product": "", "sell": float(b.get("price", 0.0)), "market": 0.0, "auto": bool(b.get("auto_price", false))}
	return {"product": product, "sell": CostSim.sale_ref_price(gs, b) if CostSim.is_producer_def(def) else float(b.get("price", 0.0)),
		"market": EconomySim.market_price(gs, product), "auto": bool(b.get("auto_price", false))}
