class_name DistributionSim
extends RefCounted
## Ventas y distribución (docs/DISTRIBUCION.md): por dónde se vende lo que fabricas.
## Canales:
##   tienda        tus tiendas y la venta directa de tus negocios a los vecinos (ShopSim, MarketSim, WarehouseSim)
##   mayorista     venta B2B: las tiendas NPC del pueblo reponen su stock de reventa comprándote al precio
##                 mayorista (menor al minorista) y los comerciantes de los pueblos con ruta te compran parte
##                 de su demanda (con ruta Y vehículo; pagan desde la caja del pueblo al llegar)
##   sucursal      comercio propio en otro pueblo: abastecido por ruta, vende al detalle allá
##   distribuidora tu negocio Distribuidora compra a tus fábricas (traspaso interno) y a empresas NPC y
##                 revende a las tiendas NPC y a los pueblos con ruta, con su margen y su flota
##   exportacion   el excedente sale fuera de la región (ruta o puerto + vehículo); dinero del exterior
##   contratos     entregas de contratos firmados (ContractSim), solo para las estadísticas
## Cada producto tiene prioridad de canales, canales activos y precio mínimo mayorista (configurables).
## Economía cerrada: todo pago tiene origen y destino (cajas NPC, caja del pueblo, jugador, FlowSim).
## Estado: gs.market["distribution"] (se guarda con el mercado; las partidas viejas lo crean al cargar).
## Campos nuevos en edificios (por defecto vacíos): NPC b["resale"] {bien: unidades}, b["resale_cost"],
## b["resale_sold"] / b["resale_sold_last"]; Distribuidora b["dist_stock"], b["dist_cost"], b["dist_margin"].

const CHANNELS := ["tienda", "mayorista", "sucursal", "distribuidora", "exportacion", "contratos"]
const CONFIG_CHANNELS := ["tienda", "mayorista", "sucursal", "distribuidora", "exportacion"]
const DIST_TYPE := "distribuidora"
const Q := 0
const REV := 1
const FREIGHT := 2


static func cfg() -> Dictionary:
	return GameData.extra("distribucion")


static func state(gs) -> Dictionary:
	if gs.market.is_empty():
		FreeMarketSim.init_state(gs)   # El mercado se crea primero (no saltarse su inicialización).
	var m: Dictionary = gs.market
	if not (m.get("distribution") is Dictionary):
		m["distribution"] = {}
	var s: Dictionary = m["distribution"]
	if not s.has("v"):
		for k in ["products", "month", "last_month", "totals", "town_month", "fleet", "notes"]:
			if not (s.get(k) is Dictionary):
				s[k] = {}
		for k in ["branches", "trips"]:
			if not (s.get(k) is Array):
				s[k] = []
		if not s.has("next_id"):
			s["next_id"] = 1
		if not s.has("internal_month"):
			s["internal_month"] = 0.0
			s["internal_last"] = 0.0
		s["v"] = 1
	return s


static func ensure(gs) -> void:
	state(gs)


static func _next_id(gs) -> int:
	var s := state(gs)
	var n := int(s.get("next_id", 1))
	s["next_id"] = n + 1
	return n


static func channel_label(ch: String, short := false) -> String:
	var c: Dictionary = cfg().get("channels", {}).get(ch, {})
	return str(c.get("short" if short else "label", ch))


static func _note(gs, key: String, text: String) -> void:
	state(gs)["notes"][key] = text


static func notes(gs) -> Dictionary:
	return state(gs)["notes"]


# --- Configuración por producto -------------------------------------------------------------------

static func default_priority() -> Array:
	var out := []
	for ch in cfg().get("default_priority", CONFIG_CHANNELS):
		if CONFIG_CHANNELS.has(str(ch)) and not out.has(str(ch)):
			out.append(str(ch))
	for ch in CONFIG_CHANNELS:
		if not out.has(ch):
			out.append(ch)
	return out


## {priority: [canales], enabled: {canal: bool}, min_wholesale: precio (0 = automático)}.
static func product_cfg(gs, good: String) -> Dictionary:
	var row: Dictionary = state(gs)["products"].get(good, {})
	var pr := []
	for ch in row.get("priority", []):
		if CONFIG_CHANNELS.has(str(ch)) and not pr.has(str(ch)):
			pr.append(str(ch))
	for ch in default_priority():
		if not pr.has(ch):
			pr.append(ch)
	var en: Dictionary = (cfg().get("default_enabled", {}) as Dictionary).duplicate()
	var re: Dictionary = row.get("enabled", {})
	for ch in CONFIG_CHANNELS:
		en[ch] = bool(re.get(ch, en.get(ch, true)))
	return {"priority": pr, "enabled": en, "min_wholesale": maxf(0.0, float(row.get("min_wholesale", 0.0)))}


static func _row(gs, good: String) -> Dictionary:
	var p: Dictionary = state(gs)["products"]
	if not (p.get(good) is Dictionary):
		p[good] = {}
	return p[good]


static func set_priority(gs, good: String, order: Array) -> void:
	var clean := []
	for ch in order:
		if CONFIG_CHANNELS.has(str(ch)) and not clean.has(str(ch)):
			clean.append(str(ch))
	_row(gs, good)["priority"] = clean


## Sube (dir = -1) o baja (dir = +1) un canal en la prioridad del producto.
static func move_channel(gs, good: String, ch: String, dir: int) -> void:
	var pr: Array = product_cfg(gs, good)["priority"]
	var i := pr.find(ch)
	var j := i + dir
	if i < 0 or j < 0 or j >= pr.size():
		return
	pr[i] = pr[j]
	pr[j] = ch
	set_priority(gs, good, pr)


static func set_enabled(gs, good: String, ch: String, on: bool) -> void:
	var r := _row(gs, good)
	if not (r.get("enabled") is Dictionary):
		r["enabled"] = {}
	r["enabled"][ch] = on


static func set_min_wholesale(gs, good: String, price: float) -> void:
	_row(gs, good)["min_wholesale"] = maxf(0.0, snappedf(price, 0.01))


static func enabled(gs, good: String, ch: String) -> bool:
	return bool(product_cfg(gs, good)["enabled"].get(ch, true))


## ¿El canal `a` va antes que `b` en la prioridad del producto?
static func before(gs, good: String, a: String, b: String) -> bool:
	var pr: Array = product_cfg(gs, good)["priority"]
	return pr.find(a) >= 0 and pr.find(a) < pr.find(b)


# --- Estadísticas por canal ---------------------------------------------------------------------

## Registra una venta (o un flete con qty = 0) de un canal. revenue = lo que entró al grupo.
static func record(gs, ch: String, good: String, qty: float, revenue: float, freight := 0.0) -> void:
	if qty <= 0.0 and revenue <= 0.0 and freight <= 0.0:
		return
	var s := state(gs)
	_add(s["month"], good, ch, qty, revenue, freight)
	_add(s["totals"], good, ch, qty, revenue, freight)


static func _add(d: Dictionary, good: String, ch: String, qty: float, revenue: float, freight: float) -> void:
	if not d.has(good):
		d[good] = {}
	var g: Dictionary = d[good]
	if not g.has(ch):
		g[ch] = [0.0, 0.0, 0.0]
	var a: Array = g[ch]
	a[Q] = float(a[Q]) + qty
	a[REV] = float(a[REV]) + revenue
	a[FREIGHT] = float(a[FREIGHT]) + freight


static func _cell(d: Dictionary, good: String, ch: String, idx: int) -> float:
	var a = d.get(good, {}).get(ch, null)
	return float(a[idx]) if a is Array and a.size() > idx else 0.0


## Unidades vendidas por un canal: period = "month" | "last_month" | "totals".
static func sold(gs, good: String, ch: String, period := "last_month") -> float:
	return _cell(state(gs)[period], good, ch, Q)


static func revenue(gs, good: String, ch: String, period := "last_month") -> float:
	return _cell(state(gs)[period], good, ch, REV)


static func freight_of(gs, good: String, ch: String, period := "last_month") -> float:
	return _cell(state(gs)[period], good, ch, FREIGHT)


static func total_sold(gs, good: String, period := "last_month") -> float:
	var n := 0.0
	for ch in CHANNELS:
		n += sold(gs, good, ch, period)
	return n


## Ventas por día recientes (el mes pasado o el ritmo de este mes, lo mayor).
static func daily_rate(gs, good: String, ch := "") -> float:
	var dom := float(int(gs.today()) % 30 + 1)
	var last := total_sold(gs, good, "last_month") if ch == "" else sold(gs, good, ch, "last_month")
	var cur := total_sold(gs, good, "month") if ch == "" else sold(gs, good, ch, "month")
	return maxf(last / 30.0, cur / dom)


# --- Stock y precios ------------------------------------------------------------------------------

static func available(gs, good: String) -> float:
	return ConstructionSim.stock_of(gs, good)


static func take(gs, good: String, qty: float) -> float:
	return ContractSim._take_goods(gs, good, qty)


## Reserva para tus tiendas: días de sus ventas recientes (si el canal tienda va antes).
static func shop_reserve(gs, good: String) -> float:
	var r := daily_rate(gs, good, "tienda") * float(cfg().get("shop_reserve_days", 21))
	if r <= 0.0 and _player_shop_sells(gs, good):
		r = float(cfg().get("shop_min_reserve", 8))
	return r


static func _player_shop_sells(gs, good: String) -> bool:
	for b in gs.buildings:
		if gs.owned_by_player(b) and gs.is_active(b) and ShopSim.shop_def_of(str(b.get("type", ""))).get("sells", []).has(good):
			return true
	return false


## Lo que un canal puede tomar del stock sin quitarle a los canales que van antes.
static func sellable(gs, good: String, ch: String) -> float:
	var reserve := 0.0
	if ch != "tienda" and enabled(gs, good, "tienda") and before(gs, good, "tienda", ch):
		reserve = shop_reserve(gs, good)
	return maxf(0.0, available(gs, good) - reserve)


static func market_ref(gs, good: String) -> float:
	return ContractSim.market_ref(gs, good)


## Costo unitario de producción del mes pasado (CostSim), 0 si no se conoce.
static func unit_cost(gs, good: String) -> float:
	return float(gs.economy.get("costing_goods", {}).get(good, 0.0))


static func auto_floor(gs, good: String) -> float:
	var uc := unit_cost(gs, good)
	if uc > 0.0:
		return uc * float(cfg().get("auto_floor_cost_mult", 1.05))
	return market_ref(gs, good) * float(cfg().get("auto_floor_market", 0.45))


## Precio mínimo mayorista vigente (el que fijaste o el automático).
static func min_wholesale(gs, good: String) -> float:
	var m := float(product_cfg(gs, good)["min_wholesale"])
	return m if m > 0.0 else auto_floor(gs, good)


static func wholesale_price(gs, good: String) -> float:
	return snappedf(maxf(market_ref(gs, good) * float(cfg().get("wholesale_factor", 0.78)), min_wholesale(gs, good)), 0.01)


## Lo máximo que paga una tienda NPC del pueblo (debe ganar al revender).
static func local_buyer_max(gs, good: String) -> float:
	return market_ref(gs, good) * float(cfg().get("buyer_max_factor", 0.92))


static func town_wholesale_price(gs, tid: String, good: String, qty: float) -> float:
	return TradeSim.export_price(gs, tid, good, qty * 0.5) * float(cfg().get("town_wholesale_factor", 0.8))


## Negocio tuyo que recibe el ingreso de una venta del producto (el que lo fabrica).
static func producer_of(gs, good: String) -> Dictionary:
	var fallback: Dictionary = {}
	for b in gs.buildings:
		if not gs.owned_by_player(b) or str(b.get("status", "")) in ["construccion", "cerrado"]:
			continue
		if str(gs.building_def(b).get("product", "")) == good:
			if gs.is_active(b):
				return b
			fallback = b
	return fallback


## Cobra una venta del canal: entra al negocio que fabrica el bien (o a tu caja si no hay).
static func credit_sale(gs, good: String, amount: float) -> void:
	if amount <= 0.0:
		return
	var p := producer_of(gs, good)
	if not p.is_empty():
		BusinessSim.earn(gs, p, amount, "ventas")
	else:
		gs.add_money(amount)
		gs.add_counter("ventas_distribucion", amount)


## Productos tuyos para el panel: lo que fabricas, lo que tienes en stock y lo que vendiste.
static func products(gs) -> Array:
	var d := {}
	for g in ContractSim.player_goods(gs):
		d[str(g)] = true
	var st := WarehouseSim.all_stock(gs)
	for g in st:
		if float(st[g]) > 0.5:
			d[str(g)] = true
	var s := state(gs)
	for per in ["month", "last_month"]:
		for g in s[per]:
			d[str(g)] = true
	var out := []
	for g in d:
		if GameData.goods.has(g) and bool(GameData.goods[g].get("storable", true)) and not bool(GameData.goods[g].get("internal", false)):
			out.append(g)
	out.sort_custom(func(a, b): return GameData.good_label(a) < GameData.good_label(b))
	return out


## Stock por almacén: [{name, qty}] — almacenes, inventario de negocios, distribuidoras y sucursales.
static func stock_rows(gs, good: String) -> Array:
	var out := []
	for wid in WarehouseSim.ids(gs):
		var q := WarehouseSim.stock_in(gs, int(wid), good)
		if q > 0.001:
			out.append({"name": WarehouseSim.label_of(gs, int(wid)), "qty": q, "kind": "almacen"})
	for b in gs.buildings:
		if not gs.owned_by_player(b):
			continue
		var q := float(b.get("inventory", {}).get(good, 0.0))
		if q > 0.001:
			out.append({"name": gs.building_label(b), "qty": q, "kind": "negocio"})
		if is_distributor(gs, b):
			var dq := float(dist_stock(b).get(good, 0.0))
			if dq > 0.001:
				out.append({"name": gs.building_label(b), "qty": dq, "kind": "distribuidora"})
	for br in branches(gs):
		var bq := float(br.get("stock", {}).get(good, 0.0))
		if bq > 0.001:
			out.append({"name": str(br.get("name", "Sucursal")), "qty": bq, "kind": "sucursal"})
	return out


# --- Tiendas NPC (compran al mayorista y revenden) ---------------------------------------------------

static func is_reseller(gs, b: Dictionary) -> bool:
	return NpcBusinessSim.is_npc(b) and gs.is_active(b) and str(b.get("npc_state", "")) == NpcBusinessSim.STATE_OPEN \
			and not ShopSim.shop_def_of(str(b.get("type", ""))).is_empty()


static func resellers(gs) -> Array:
	return gs.buildings.filter(func(b): return is_reseller(gs, b))


## Bienes que puede revender una tienda NPC (los de su tipo de comercio, menos su propio producto).
static func reseller_goods(gs, b: Dictionary) -> Array:
	var own := str(gs.building_def(b).get("product", ""))
	return ShopSim.shop_def_of(str(b.get("type", ""))).get("sells", []).filter(func(g): return GameData.goods.has(str(g)) and str(g) != own)


static func resale(b: Dictionary) -> Dictionary:
	if not (b.get("resale") is Dictionary):
		b["resale"] = {}
	return b["resale"]


static func resale_stock(b: Dictionary, good: String) -> float:
	var r = b.get("resale")
	return float(r.get(good, 0.0)) if r is Dictionary else 0.0


## Precio al que revende una tienda NPC: mercado + su margen, nunca bajo su costo.
static func resale_price(gs, b: Dictionary, good: String) -> float:
	var cost := float(b.get("resale_cost", {}).get(good, 0.0)) if b.get("resale_cost") is Dictionary else 0.0
	return maxf(EconomySim.market_price(gs, good) * (1.0 + float(b.get("markup", 0.08))), cost * 1.03)


## Clientes por semana de una tienda NPC para los deseos (ShopSim).
static func reseller_customers(gs, b: Dictionary) -> float:
	var emps: Array = NpcBusinessSim.staff_of(b).duplicate()
	if NpcBusinessSim.owner_works(gs, b):
		emps.append(gs.citizens[int(b["owner_id"])])
	var out := NpcBusinessSim._output(gs, b, emps)
	var sd := ShopSim.shop_def_of(str(b.get("type", "")))
	return maxf(float(cfg().get("store_customers_floor", 6)), out * 7.0 * float(sd.get("customers_mult", 1.0)))


## La tienda NPC vendió `qty` de su stock de reventa (ShopSim ya cobró al vecino).
static func take_resale(gs, b: Dictionary, good: String, qty: float, value: float) -> void:
	var r := resale(b)
	r[good] = maxf(0.0, float(r.get(good, 0.0)) - qty)
	if not (b.get("resale_sold") is Dictionary):
		b["resale_sold"] = {}
	b["resale_sold"][good] = float(b["resale_sold"].get(good, 0.0)) + qty
	var s := state(gs)
	s["npc_resale_month"] = float(s.get("npc_resale_month", 0.0)) + value


## La tienda NPC recibe mercancía comprada (costo medio ponderado).
static func _stock_store(b: Dictionary, good: String, qty: float, unit: float) -> void:
	var r := resale(b)
	if not (b.get("resale_cost") is Dictionary):
		b["resale_cost"] = {}
	var have := float(r.get(good, 0.0))
	var old := float(b["resale_cost"].get(good, unit))
	b["resale_cost"][good] = (old * have + unit * qty) / maxf(0.0001, have + qty)
	r[good] = have + qty


## Unidades que los vecinos quisieron y no encontraron el mes pasado, por bien (ShopSim).
static func unmet_units(gs) -> Dictionary:
	var out := {}
	var st := ShopSim.state(gs)
	var m: Dictionary = st.get("last_month", {})
	if m.is_empty():
		m = st.get("month", {})
	var wants := ShopSim.wants_cfg()
	for wid in m:
		var w: Dictionary = wants.get(wid, {})
		var goods: Array = w.get("goods", [])
		if goods.is_empty():
			continue
		var r: Dictionary = m[wid]
		var miss := float(r.get("no_shop", 0.0)) + float(r.get("no_stock", 0.0))
		if miss <= 0.0:
			continue
		var per := miss * float(w.get("qty", 1.0)) / goods.size()
		for g in goods:
			out[str(g)] = float(out.get(str(g), 0.0)) + per
	return out


## Pedido semanal de una tienda NPC para un bien: cubrir store_cover_days de su demanda.
static func store_need(gs, b: Dictionary, good: String, unmet: Dictionary, sellers: int) -> float:
	var dom := float(int(gs.today()) % 30 + 1)
	var last := float(b.get("resale_sold_last", {}).get(good, 0.0)) if b.get("resale_sold_last") is Dictionary else 0.0
	var cur := float(b.get("resale_sold", {}).get(good, 0.0)) if b.get("resale_sold") is Dictionary else 0.0
	var monthly := maxf(last, cur * 30.0 / dom) * 1.1 + float(unmet.get(good, 0.0)) * float(cfg().get("store_unmet_capture", 0.6)) / maxf(1.0, float(sellers))
	var target := monthly * float(cfg().get("store_cover_days", 14)) / 30.0
	if float(GameData.goods.get(good, {}).get("base_price", 0.0)) >= float(ShopSim.cfg().get("whole_unit_price", 20.0)):
		target = ceilf(target)
	return maxf(0.0, target - resale_stock(b, good))


# --- Distribuidoras ------------------------------------------------------------------------------

static func is_distributor_def(def: Dictionary) -> bool:
	return bool(def.get("distribution", false))


static func is_distributor(gs, b: Dictionary) -> bool:
	return gs.owned_by_player(b) and is_distributor_def(gs.building_def(b))


static func distributors(gs, active_only := true) -> Array:
	return gs.buildings.filter(func(b): return is_distributor(gs, b) and (not active_only or gs.is_active(b)))


static func dist_stock(b: Dictionary) -> Dictionary:
	if not (b.get("dist_stock") is Dictionary):
		b["dist_stock"] = {}
	return b["dist_stock"]


static func dist_used(b: Dictionary) -> float:
	var n := 0.0
	var st := dist_stock(b)
	for g in st:
		n += float(st[g])
	return n


static func dist_capacity(gs, b: Dictionary) -> float:
	return float(gs.level_def(b).get("dist_capacity", 400.0))


static func dist_margin(b: Dictionary) -> float:
	return float(b.get("dist_margin", cfg().get("distribuidora", {}).get("default_margin", 0.12)))


static func set_dist_margin(b: Dictionary, m: float) -> void:
	b["dist_margin"] = clampf(m, 0.0, float(cfg().get("distribuidora", {}).get("max_margin", 0.6)))


static func dist_staff(gs, b: Dictionary) -> int:
	var n := 0
	for c in gs.employees_of(int(b["id"])):
		if c.job_kind == "empleo" and not c.sick:
			n += 1
	return n


static func _dist_put(b: Dictionary, good: String, qty: float, unit: float) -> void:
	var st := dist_stock(b)
	if not (b.get("dist_cost") is Dictionary):
		b["dist_cost"] = {}
	var have := float(st.get(good, 0.0))
	var old := float(b["dist_cost"].get(good, unit))
	b["dist_cost"][good] = (old * have + unit * qty) / maxf(0.0001, have + qty)
	st[good] = have + qty


static func _dist_unit_cost(b: Dictionary, good: String) -> float:
	return float(b.get("dist_cost", {}).get(good, 0.0)) if b.get("dist_cost") is Dictionary else 0.0


# --- Sucursales ------------------------------------------------------------------------------------

static func branches(gs) -> Array:
	return state(gs)["branches"]


static func branch(gs, id: int) -> Dictionary:
	for br in branches(gs):
		if int(br["id"]) == id:
			return br
	return {}


static func branch_in(gs, tid: String) -> Dictionary:
	for br in branches(gs):
		if str(br["town_id"]) == tid:
			return br
	return {}


static func branch_level_def(level: int) -> Dictionary:
	var lv: Array = cfg().get("branch", {}).get("levels", [])
	if lv.is_empty():
		return {}
	return lv[clampi(level - 1, 0, lv.size() - 1)]


static func branch_capacity(br: Dictionary) -> float:
	return float(branch_level_def(int(br.get("level", 1))).get("capacity", 200))


static func branch_used(br: Dictionary) -> float:
	var n := 0.0
	var st: Dictionary = br.get("stock", {})
	for g in st:
		n += float(st[g])
	return n


static func branch_monthly_cost(gs, br: Dictionary) -> float:
	var ld := branch_level_def(int(br.get("level", 1)))
	return (float(ld.get("rent_month", 20)) + float(ld.get("staff", 2)) * float(ld.get("staff_wage", 1.8)) * 30.0) * gs.price_mult()


static func branch_open_cost(gs, level := 1) -> float:
	return float(branch_level_def(level).get("open_cost", 900)) * gs.price_mult()


static func open_branch_block(gs, tid: String) -> String:
	var t := TradeSim.town(gs, tid)
	if t.is_empty():
		return "Ese pueblo no existe."
	if TradeSim.connection(gs, tid).is_empty():
		return "Primero abre una ruta comercial con %s." % str(t.get("name", ""))
	if not branch_in(gs, tid).is_empty():
		return "Ya tienes una sucursal en %s." % str(t.get("name", ""))
	if gs.money < branch_open_cost(gs):
		return "Necesitas %s para abrir la sucursal." % Fmt.money(branch_open_cost(gs))
	return ""


## Abre un comercio propio en otro pueblo. La obra y el arriendo los cobran vecinos de allá (caja del pueblo).
static func open_branch(gs, tid: String) -> String:
	var why := open_branch_block(gs, tid)
	if why != "":
		return why
	var t := TradeSim.town(gs, tid)
	var cost := branch_open_cost(gs)
	gs.add_money(-cost)
	t["cash"] = float(t.get("cash", 0.0)) + cost
	gs.add_counter("trade_investment", cost)
	var br := {"id": _next_id(gs), "town_id": tid, "name": "Sucursal %s" % str(t.get("name", "")), "level": 1,
		"markup": float(cfg().get("branch", {}).get("default_markup", 0.1)), "stock": {}, "opened_day": gs.today(),
		"ledger": {"month": {}, "last_month": {}, "total": {"obras": cost}}, "active": true}
	branches(gs).append(br)
	gs.notify("Abriste %s. Se abastece por la ruta desde tus almacenes." % str(br["name"]), "negocio")
	return ""


static func upgrade_branch_block(gs, br: Dictionary) -> String:
	var next := int(br.get("level", 1)) + 1
	var lv: Array = cfg().get("branch", {}).get("levels", [])
	if next > lv.size():
		return "La sucursal ya está al máximo."
	var ld := branch_level_def(next)
	if not gs.has_tech(str(ld.get("tech", ""))):
		return "Requiere investigar %s." % GameData.tech_label(str(ld.get("tech", "")))
	if gs.money < branch_open_cost(gs, next):
		return "Necesitas %s." % Fmt.money(branch_open_cost(gs, next))
	return ""


static func upgrade_branch(gs, id: int) -> String:
	var br := branch(gs, id)
	if br.is_empty():
		return "Sucursal no encontrada."
	var why := upgrade_branch_block(gs, br)
	if why != "":
		return why
	var next := int(br.get("level", 1)) + 1
	var cost := branch_open_cost(gs, next)
	var t := TradeSim.town(gs, str(br["town_id"]))
	gs.add_money(-cost)
	t["cash"] = float(t.get("cash", 0.0)) + cost
	br["level"] = next
	_branch_ledger(br, "obras", cost)
	gs.notify("%s ahora es %s." % [str(br["name"]), str(branch_level_def(next).get("label", ""))], "negocio")
	return ""


## Cierra la sucursal: la mercancía que queda vuelve a la bodega de la plaza.
static func close_branch(gs, id: int) -> String:
	var br := branch(gs, id)
	if br.is_empty():
		return "Sucursal no encontrada."
	var st: Dictionary = br.get("stock", {})
	for g in st:
		_return_to_plaza(gs, str(g), float(st[g]))
	branches(gs).erase(br)
	gs.notify("Cerraste %s." % str(br["name"]), "negocio")
	return ""


static func set_branch_markup(br: Dictionary, m: float) -> void:
	br["markup"] = clampf(m, -0.3, float(cfg().get("branch", {}).get("max_markup", 0.8)))


static func _branch_ledger(br: Dictionary, key: String, amount: float) -> void:
	var led: Dictionary = br.get("ledger", {})
	for per in ["month", "total"]:
		if not (led.get(per) is Dictionary):
			led[per] = {}
		led[per][key] = float(led[per].get(key, 0.0)) + amount
	br["ledger"] = led


static func branch_result(br: Dictionary, period := "last_month") -> float:
	var p: Dictionary = br.get("ledger", {}).get(period, {})
	return float(p.get("ventas", 0.0)) - float(p.get("costos", 0.0)) - float(p.get("fletes", 0.0))


static func _branch_price(gs, br: Dictionary, good: String) -> float:
	var tid := str(br["town_id"])
	var p := TradeSim.export_price(gs, tid, good)
	if p <= 0.0:
		p = market_ref(gs, good)
	return p * (1.0 + float(br.get("markup", 0.1)))


## Demanda mensual de un bien en un pueblo (filas de TradeSim; si no hay, una parte por habitante).
static func town_demand(gs, tid: String, good: String) -> float:
	var t := TradeSim.town(gs, tid)
	var row: Dictionary = t.get("goods", {}).get(good, {})
	var floor_d := float(t.get("population", 0)) * float(cfg().get("branch", {}).get("min_demand_per_pop", 0.03))
	return maxf(float(row.get("demand", 0.0)), floor_d)


static func _branch_daily_units(gs, br: Dictionary, good: String) -> float:
	var bc: Dictionary = cfg().get("branch", {})
	var ld := branch_level_def(int(br.get("level", 1)))
	var el := clampf(1.2 - float(bc.get("elasticity", 2.0)) * float(br.get("markup", 0.1)), 0.15, 1.6)
	return town_demand(gs, str(br["town_id"]), good) / 30.0 * float(ld.get("capture", 0.3)) * el


# --- Vehículos y rutas -----------------------------------------------------------------------------

static func _ccfg() -> Dictionary:
	return cfg().get("carriers", {})


## Tipos de medio (pie, animal, carreta, camion, tren, barco, avion) de una estación de transporte.
static func _station_kinds(gs, b: Dictionary) -> Array:
	var out := []
	var modes: Array = (gs.level_def(b).get("transport_modes", []) as Array).duplicate()
	for v in LogisticsSim.vehicles_of(gs, int(b["id"])):
		modes.append(str(v.get("mode", "")))
	for m in modes:
		var k := str(LogisticsSim.mode_def(str(m)).get("tipo", "pie"))
		if not out.has(k):
			out.append(k)
	if out.is_empty():
		out.append("pie")
	return out


## Vehículos disponibles esta semana: [{id, kind ("div"|"dist"), cap, reach, speed, label}].
static func carriers(gs) -> Array:
	var cc := _ccfg()
	var out := []
	for b in LogisticsSim.stations(gs):
		if not TransportDivSim.is_transport(gs, b):
			continue
		var crew := LogisticsSim.crew_size(gs, b)
		if crew <= 0:
			continue
		var mult := 0.0
		var reach := 0.0
		var speed := 0.0
		for k in _station_kinds(gs, b):
			mult = maxf(mult, float(cc.get("mode_mult", {}).get(k, 1.0)))
			reach = maxf(reach, float(cc.get("reach_km", {}).get(k, 90.0)))
			speed = maxf(speed, float(cc.get("speed_km_day", {}).get(k, 25.0)))
		out.append({"id": int(b["id"]), "kind": "div", "cap": crew * float(cc.get("crew_units_week", 30)) * mult, "reach": reach, "speed": speed,
			"label": gs.building_label(b)})
	for d in distributors(gs):
		var staff := dist_staff(gs, d)
		if staff <= 0:
			continue
		var ld: Dictionary = gs.level_def(d)
		out.append({"id": int(d["id"]), "kind": "dist", "cap": staff * float(ld.get("fleet_per_worker", 35)), "reach": float(ld.get("reach_km", 90)),
			"speed": float(ld.get("speed_km_day", 25)), "label": gs.building_label(d)})
	return out


static func _fleet(gs) -> Dictionary:
	var s := state(gs)
	var f: Dictionary = s["fleet"]
	var week := int(gs.today()) / 7
	if int(f.get("week", -1)) != week:
		f["week"] = week
		f["used"] = {}
	return f


static func carrier_used(gs, id: int) -> float:
	return float(_fleet(gs)["used"].get(str(id), 0.0))


## Elige un vehículo con espacio que llegue a `km`. only_id >= 0: solo ese (la flota de una distribuidora).
static func pick_carrier(gs, ctx: Dictionary, km: float, only_id := -1, prefer_kind := "div") -> Dictionary:
	var best: Dictionary = {}
	for c in ctx["carriers"]:
		if only_id >= 0 and int(c["id"]) != only_id:
			continue
		if float(c["reach"]) < km:
			continue
		var room := float(c["cap"]) - carrier_used(gs, int(c["id"]))
		if room < 1.0:
			continue
		if best.is_empty() or (str(c["kind"]) == prefer_kind and str(best["kind"]) != prefer_kind):
			best = c
	return best


## Motivo por el que no se puede llevar carga a un pueblo ("" = se puede).
static func reach_block(gs, ctx: Dictionary, tid: String, only_id := -1) -> String:
	var conn := TradeSim.connection(gs, tid)
	if conn.is_empty():
		return "sin ruta"
	if ctx["carriers"].is_empty():
		return "sin vehículo"
	if pick_carrier(gs, ctx, float(conn.get("distance", 50.0)), only_id).is_empty():
		return "sin vehículo con espacio o alcance"
	return ""


## Despacha un viaje: paga el costo variable (dueño del vehículo → proveedores y parte importada),
## lo registra en la división de transporte si es interna/empresa y agenda la llegada.
static func _dispatch(gs, ctx: Dictionary, carrier: Dictionary, trip: Dictionary, km: float, benef: int) -> float:
	var qty := float(trip["qty"])
	var f := _fleet(gs)
	f["used"][str(int(carrier["id"]))] = carrier_used(gs, int(carrier["id"])) + qty
	var cc := _ccfg()
	var pm: float = gs.price_mult()
	var cost := snappedf((qty * km * float(cc.get("cost_per_ukm", 0.004)) + float(cc.get("trip_fixed", 1.0))) * pm, 0.01)
	var cb: Dictionary = gs.get_building(int(carrier["id"]))
	if not cb.is_empty() and cost > 0.0:
		BusinessSim.pay(gs, cb, cost, "insumos")
		FlowSim.spend(gs, cost, "combustible y forraje (distribución)", float(cc.get("import_share", 0.45)))
	if str(carrier["kind"]) == "div" and not cb.is_empty():
		TransportDivSim.record_trip(gs, cb, benef, qty, km)
	var days := maxi(1, int(ceilf(km / maxf(1.0, float(carrier.get("speed", 25.0))))))
	trip["id"] = _next_id(gs)
	trip["arrive"] = gs.today() + days
	trip["carrier"] = int(carrier["id"])
	trip["freight"] = cost
	trip["depart"] = gs.today()
	state(gs)["trips"].append(trip)
	return cost


static func _return_to_plaza(gs, good: String, qty: float) -> void:
	if qty <= 0.0:
		return
	var acc := WarehouseSim.add(gs, good, qty)
	if qty - acc > 0.0001:
		var st := WarehouseSim._store(gs, WarehouseSim.PLAZA)
		st[good] = float(st.get(good, 0.0)) + (qty - acc)


static func in_transit(gs, kind: String, key: String, good: String) -> float:
	var n := 0.0
	for t in state(gs)["trips"]:
		if str(t["kind"]) == kind and str(t.get("key", "")) == key and str(t["good"]) == good:
			n += float(t["qty"])
	return n


## Salida al exterior: distancia hasta la frontera (ruta más corta o puerto propio). -1 = no hay.
static func export_gateway_km(gs) -> float:
	var best := -1.0
	for c in TradeSim.connected_towns(gs):
		var d := float(c.get("distance", 50.0))
		if best < 0.0 or d < best:
			best = d
	for b in gs.buildings:
		if gs.owned_by_player(b) and str(b.get("type", "")) == "puerto" and gs.is_active(b) and not gs.employees_of(int(b["id"])).is_empty():
			var pk := float(cfg().get("export", {}).get("port_km", 60))
			if best < 0.0 or pk < best:
				best = pk
	return best


# --- Ciclo -------------------------------------------------------------------------------------------

## Cada día (FreeMarketSim.daily): llegadas, ventas de las sucursales y, una vez por semana, la distribución.
static func daily(gs) -> void:
	_arrivals(gs)
	_branch_sales(gs)
	if int(gs.today()) % 7 == 3:
		weekly(gs)


## Una vez por semana: cada producto recorre sus canales en orden de prioridad; luego las distribuidoras
## compran a empresas NPC y revenden.
static func weekly(gs) -> void:
	var ctx := _context(gs)
	for good in products(gs):
		if available(gs, good) <= 0.01:
			continue
		var pc := product_cfg(gs, good)
		for ch in pc["priority"]:
			if not bool(pc["enabled"].get(ch, true)):
				continue
			match str(ch):
				"mayorista":
					_direct_local(gs, ctx, good)
					_direct_towns(gs, ctx, good)
				"sucursal":
					_restock_branches(gs, ctx, good)
				"distribuidora":
					for d in ctx["dists"]:
						_dist_take(gs, ctx, d, good)
						_dist_sell(gs, ctx, d, good)
				"exportacion":
					_export(gs, ctx, good)
	for d in ctx["dists"]:
		_dist_source_npc(gs, ctx, d)


static func _context(gs) -> Dictionary:
	var unmet := unmet_units(gs)
	var stores := resellers(gs)
	var by_good := {}
	for b in stores:
		for g in reseller_goods(gs, b):
			if not by_good.has(g):
				by_good[g] = []
			by_good[g].append(b)
	var cash := {}
	for b in stores:
		cash[int(b["id"])] = maxf(0.0, float(b.get("reserve", 0.0))) * float(cfg().get("store_cash_share", 0.5))
	var tcash := {}
	for c in TradeSim.connected_towns(gs):
		var t := TradeSim.town(gs, str(c["town_id"]))
		tcash[str(c["town_id"])] = maxf(0.0, float(t.get("cash", 0.0))) * float(cfg().get("town_cash_share", 0.25))
	var dists := distributors(gs).filter(func(d): return dist_staff(gs, d) > 0)
	var dcash := {}
	for d in dists:
		dcash[int(d["id"])] = maxf(0.0, gs.money) * float(cfg().get("distribuidora", {}).get("cash_share", 0.6))
	return {"unmet": unmet, "stores": stores, "by_good": by_good, "cash": cash, "tcash": tcash, "carriers": carriers(gs),
		"dists": dists, "dcash": dcash, "needs": {}, "tneeds": {}}


## Pedido pendiente de una tienda NPC esta semana (se calcula una vez y se va descontando).
static func _store_need(gs, ctx: Dictionary, b: Dictionary, good: String) -> float:
	var k := "%d|%s" % [int(b["id"]), good]
	var needs: Dictionary = ctx["needs"]
	if not needs.has(k):
		var sellers: Array = ctx["by_good"].get(good, [])
		needs[k] = store_need(gs, b, good, ctx["unmet"], sellers.size())
	return float(needs[k])


## Pedido pendiente de los comerciantes de un pueblo (mes acumulado, una vez por semana).
static func _town_need(gs, ctx: Dictionary, tid: String, good: String) -> float:
	var k := "%s|%s" % [tid, good]
	var tn: Dictionary = ctx["tneeds"]
	if not tn.has(k):
		var t := TradeSim.town(gs, tid)
		var row: Dictionary = t.get("goods", {}).get(good, {})
		if row.is_empty():
			tn[k] = 0.0
		else:
			var month_need := float(row.get("demand", 0.0)) * float(cfg().get("town_wholesale_share", 0.35))
			var dom := float(int(gs.today()) % 30)
			var bought := float(state(gs)["town_month"].get(tid, {}).get(good, 0.0))
			tn[k] = maxf(0.0, month_need * minf(1.0, (dom + 7.0) / 30.0) - bought)
	return float(tn[k])


static func _town_bought(gs, tid: String, good: String, qty: float) -> void:
	var tm: Dictionary = state(gs)["town_month"]
	if not tm.has(tid):
		tm[tid] = {}
	tm[tid][good] = float(tm[tid].get(good, 0.0)) + qty


## La tienda NPC paga y recibe la mercancía. Devuelve las unidades vendidas.
static func _sell_to_store(gs, ctx: Dictionary, b: Dictionary, good: String, qty: float, price: float) -> float:
	var id := int(b["id"])
	var budget := minf(float(ctx["cash"].get(id, 0.0)), maxf(0.0, float(b.get("reserve", 0.0))))
	var q := minf(qty, budget / maxf(0.01, price))
	if float(GameData.goods.get(good, {}).get("base_price", 0.0)) >= float(ShopSim.cfg().get("whole_unit_price", 20.0)):
		q = floorf(q)
	if q < float(cfg().get("store_min_units", 0.5)):
		return 0.0
	var value := q * price
	b["reserve"] = float(b["reserve"]) - value
	BusinessSim.ledger_add(b, "mercaderia", value)
	ctx["cash"][id] = float(ctx["cash"].get(id, 0.0)) - value
	_stock_store(b, good, q, price)
	var k := "%d|%s" % [id, good]
	ctx["needs"][k] = maxf(0.0, float(ctx["needs"].get(k, 0.0)) - q)
	return q


## Canal mayorista local: tus productos a las tiendas NPC del pueblo (ellas los recogen).
static func _direct_local(gs, ctx: Dictionary, good: String) -> void:
	var stores: Array = ctx["by_good"].get(good, [])
	if stores.is_empty():
		return
	var price := wholesale_price(gs, good)
	if price > local_buyer_max(gs, good):
		_note(gs, "precio|" + good, "%s: tu precio mínimo mayorista (%s) supera lo que pagan las tiendas (%s)." % [GameData.good_label(good), Fmt.money2(price), Fmt.money2(local_buyer_max(gs, good))])
		return
	for b in stores:
		var need := _store_need(gs, ctx, b, good)
		var avail := sellable(gs, good, "mayorista")
		var q := minf(need, avail)
		if q <= 0.0:
			continue
		var sold_q := _sell_to_store(gs, ctx, b, good, q, price)
		if sold_q <= 0.0:
			continue
		take(gs, good, sold_q)
		credit_sale(gs, good, sold_q * price)
		record(gs, "mayorista", good, sold_q, sold_q * price)


## Canal mayorista a otros pueblos: los comerciantes de allá; necesita ruta y vehículo.
static func _direct_towns(gs, ctx: Dictionary, good: String) -> void:
	var minp := min_wholesale(gs, good)
	for c in TradeSim.connected_towns(gs):
		var tid := str(c["town_id"])
		var need := _town_need(gs, ctx, tid, good)
		if need < 1.0:
			continue
		var km := float(c.get("distance", 50.0))
		var carrier := pick_carrier(gs, ctx, km)
		if carrier.is_empty():
			_note(gs, "veh|" + tid, "Sin vehículo con espacio o alcance para llevar mercancía a %s." % str(c.get("town_name", "")))
			continue
		var q := floorf(minf(minf(need, sellable(gs, good, "mayorista")), float(carrier["cap"]) - carrier_used(gs, int(carrier["id"]))))
		if q < 1.0:
			continue
		var unit := town_wholesale_price(gs, tid, good, q)
		if unit < minp or unit <= 0.0:
			continue
		var budget := float(ctx["tcash"].get(tid, 0.0))
		q = minf(q, floorf(budget / unit))
		if q < 1.0:
			continue
		var got := take(gs, good, q)
		if got <= 0.0:
			continue
		ctx["tcash"][tid] = budget - got * unit
		ctx["tneeds"]["%s|%s" % [tid, good]] = maxf(0.0, need - got)
		_town_bought(gs, tid, good, got)
		var producer := producer_of(gs, good)
		var fr := _dispatch(gs, ctx, carrier, {"kind": "mayorista", "key": tid, "good": good, "qty": got, "unit": unit, "seller": -1}, km,
			int(producer.get("id", -1)) if not producer.is_empty() else -1)
		record(gs, "mayorista", good, 0.0, 0.0, fr)


## Sucursales: reponen stock desde tus almacenes por la ruta.
static func _restock_branches(gs, ctx: Dictionary, good: String) -> void:
	var cover := float(cfg().get("branch", {}).get("cover_days", 21))
	for br in branches(gs):
		var tid := str(br["town_id"])
		var conn := TradeSim.connection(gs, tid)
		if conn.is_empty():
			br["status"] = "Sin ruta: no se puede abastecer"
			continue
		var stock := float(br.get("stock", {}).get(good, 0.0)) + in_transit(gs, "sucursal", str(br["id"]), good)
		var target := _branch_daily_units(gs, br, good) * cover
		var need := floorf(minf(target - stock, branch_capacity(br) - branch_used(br) - _branch_incoming(gs, br)))
		if need < 1.0:
			continue
		var km := float(conn.get("distance", 50.0))
		var carrier := pick_carrier(gs, ctx, km)
		if carrier.is_empty():
			br["status"] = "Sin vehículo para abastecerla"
			continue
		var q := floorf(minf(minf(need, sellable(gs, good, "sucursal")), float(carrier["cap"]) - carrier_used(gs, int(carrier["id"]))))
		if q < 1.0:
			continue
		var got := take(gs, good, q)
		if got <= 0.0:
			continue
		var producer := producer_of(gs, good)
		var fr := _dispatch(gs, ctx, carrier, {"kind": "sucursal", "key": str(br["id"]), "good": good, "qty": got, "unit": 0.0}, km,
			int(producer.get("id", -1)) if not producer.is_empty() else -1)
		_branch_ledger(br, "fletes", fr)
		record(gs, "sucursal", good, 0.0, 0.0, fr)
		br["status"] = "Abastecida"


static func _branch_incoming(gs, br: Dictionary) -> float:
	var n := 0.0
	for t in state(gs)["trips"]:
		if str(t["kind"]) == "sucursal" and str(t.get("key", "")) == str(br["id"]):
			n += float(t["qty"])
	return n


## Distribuidora: toma tus productos (traspaso interno al precio mayorista) para la demanda que atiende.
static func _dist_take(gs, ctx: Dictionary, d: Dictionary, good: String) -> void:
	var demand := _dist_demand(gs, ctx, d, good) - float(dist_stock(d).get(good, 0.0))
	var room := dist_capacity(gs, d) - dist_used(d)
	var q := minf(minf(demand, room), sellable(gs, good, "distribuidora"))
	if q < 0.5:
		return
	var unit := wholesale_price(gs, good)
	var got := take(gs, good, q)
	if got <= 0.0:
		return
	_dist_put(d, good, got, unit)
	var value := got * unit
	# Traspaso interno: la fábrica registra la venta y la distribuidora la compra; el dinero no sale del grupo.
	var producer := producer_of(gs, good)
	if not producer.is_empty():
		BusinessSim.ledger_add(producer, "ventas", value)
	BusinessSim.ledger_add(d, "mercaderia", value)
	var s := state(gs)
	s["internal_month"] = float(s.get("internal_month", 0.0)) + value
	d["dist_internal_mes"] = float(d.get("dist_internal_mes", 0.0)) + value


## Demanda que una distribuidora puede atender esta semana: tiendas NPC + pueblos a su alcance.
static func _dist_demand(gs, ctx: Dictionary, d: Dictionary, good: String) -> float:
	var n := 0.0
	for b in ctx["by_good"].get(good, []):
		n += _store_need(gs, ctx, b, good)
	var reach := float(gs.level_def(d).get("reach_km", 90))
	for c in TradeSim.connected_towns(gs):
		if float(c.get("distance", 50.0)) <= reach:
			n += _town_need(gs, ctx, str(c["town_id"]), good)
	return n


## Distribuidora: vende su stock del bien a las tiendas NPC y a los pueblos a su alcance con su flota.
static func _dist_sell(gs, ctx: Dictionary, d: Dictionary, good: String) -> void:
	var st := dist_stock(d)
	var have := float(st.get(good, 0.0))
	if have <= 0.01:
		return
	var cost := _dist_unit_cost(d, good)
	var margin := dist_margin(d)
	var minp := min_wholesale(gs, good) if not producer_of(gs, good).is_empty() else 0.0
	# Tiendas NPC del pueblo.
	var local_p := minf(local_buyer_max(gs, good), maxf(cost * (1.0 + margin), wholesale_price(gs, good)))
	if local_p >= cost and local_p >= minp:
		for b in ctx["by_good"].get(good, []):
			have = float(st.get(good, 0.0))
			if have <= 0.01:
				break
			var need := minf(_store_need(gs, ctx, b, good), have)
			if need <= 0.0:
				continue
			var q := _sell_to_store(gs, ctx, b, good, need, local_p)
			if q <= 0.0:
				continue
			st[good] = have - q
			BusinessSim.earn(gs, d, q * local_p, "ventas")
			record(gs, "distribuidora", good, q, q * local_p)
	# Pueblos con ruta a su alcance, con su propia flota.
	var reach := float(gs.level_def(d).get("reach_km", 90))
	for c in TradeSim.connected_towns(gs):
		have = float(st.get(good, 0.0))
		if have < 1.0:
			break
		var km := float(c.get("distance", 50.0))
		if km > reach:
			continue
		var tid := str(c["town_id"])
		var need := _town_need(gs, ctx, tid, good)
		if need < 1.0:
			continue
		var carrier := pick_carrier(gs, ctx, km, int(d["id"]))
		if carrier.is_empty():
			continue
		var q := floorf(minf(minf(need, have), float(carrier["cap"]) - carrier_used(gs, int(carrier["id"]))))
		if q < 1.0:
			continue
		var unit := maxf(town_wholesale_price(gs, tid, good, q), 0.0)
		if unit < cost * 1.02 or unit < minp:
			continue
		var budget := float(ctx["tcash"].get(tid, 0.0))
		q = minf(q, floorf(budget / unit))
		if q < 1.0:
			continue
		st[good] = have - q
		ctx["tcash"][tid] = budget - q * unit
		ctx["tneeds"]["%s|%s" % [tid, good]] = maxf(0.0, need - q)
		_town_bought(gs, tid, good, q)
		var fr := _dispatch(gs, ctx, carrier, {"kind": "distribuidora", "key": tid, "good": good, "qty": q, "unit": unit, "dist": int(d["id"])}, km, int(d["id"]))
		record(gs, "distribuidora", good, 0.0, 0.0, fr)
	if float(st.get(good, 0.0)) <= 0.0001:
		st.erase(good)


## Distribuidora: compra el excedente de las empresas NPC (lo que pasa de npc_keep_days de ventas) para la
## demanda que atiende, y lo revende.
static func _dist_source_npc(gs, ctx: Dictionary, d: Dictionary) -> void:
	var dc: Dictionary = cfg().get("distribuidora", {})
	for nb in NpcBusinessSim.npc_buildings(gs):
		if not gs.is_active(nb) or str(nb.get("npc_state", "")) != NpcBusinessSim.STATE_OPEN:
			continue
		var good := str(gs.building_def(nb).get("product", ""))
		if not GameData.goods.has(good) or not bool(GameData.goods[good].get("storable", true)) or bool(GameData.goods[good].get("internal", false)):
			continue
		var inv: Dictionary = nb["inventory"]
		var stock := float(inv.get(good, 0.0))
		var sold_units := BusinessSim.period_value(nb, "last_month", "ventas") / maxf(0.01, float(nb.get("price", 1.0)))
		var surplus := stock - sold_units / 30.0 * float(dc.get("npc_keep_days", 10))
		if surplus < 1.0:
			continue
		var demand := _dist_demand(gs, ctx, d, good) - float(dist_stock(d).get(good, 0.0))
		var room := dist_capacity(gs, d) - dist_used(d)
		var unit := float(nb.get("price", EconomySim.market_price(gs, good))) * float(dc.get("npc_price_factor", 0.85))
		var cash := float(ctx["dcash"].get(int(d["id"]), 0.0))
		var q := floorf(minf(minf(surplus, demand), minf(room, cash / maxf(0.01, unit))))
		if q < 1.0:
			continue
		var value := q * unit
		inv[good] = stock - q
		BusinessSim.pay(gs, d, value, "mercaderia")
		BusinessSim.earn(gs, nb, value, "ventas")   # A la caja de la empresa NPC (NpcBusinessSim.book).
		ctx["dcash"][int(d["id"])] = cash - value
		_dist_put(d, good, q, unit)
		_dist_sell(gs, ctx, d, good)


## Exportación: el excedente sale fuera de la región (ruta o puerto + vehículo). Dinero del exterior.
static func _export(gs, ctx: Dictionary, good: String) -> void:
	var ec: Dictionary = cfg().get("export", {})
	var km := export_gateway_km(gs)
	if km < 0.0:
		_note(gs, "export", "Para exportar necesitas una ruta a otro pueblo o un puerto con personal.")
		return
	var keep := daily_rate(gs, good) * float(ec.get("keep_days", 20))
	var surplus := sellable(gs, good, "exportacion") - keep
	var q := floorf(minf(surplus * float(ec.get("share", 0.5)), float(ec.get("max_units_week", 400))))
	if q < 1.0:
		return
	var unit := market_ref(gs, good) * float(ec.get("price_factor", 0.62))
	if unit < min_wholesale(gs, good):
		_note(gs, "expprecio|" + good, "%s: el precio de exportación (%s) no cubre tu precio mínimo (%s)." % [GameData.good_label(good), Fmt.money2(unit), Fmt.money2(min_wholesale(gs, good))])
		return
	var carrier := pick_carrier(gs, ctx, km)
	if carrier.is_empty():
		_note(gs, "export", "Para exportar necesitas un vehículo con espacio (estación de transporte o distribuidora).")
		return
	q = floorf(minf(q, float(carrier["cap"]) - carrier_used(gs, int(carrier["id"]))))
	if q < 1.0:
		return
	var got := take(gs, good, q)
	if got <= 0.0:
		return
	var producer := producer_of(gs, good)
	var fr := _dispatch(gs, ctx, carrier, {"kind": "exportacion", "key": "", "good": good, "qty": got, "unit": unit}, km,
		int(producer.get("id", -1)) if not producer.is_empty() else -1)
	record(gs, "exportacion", good, 0.0, 0.0, fr)


## Llegadas de los viajes: cobro (caja del pueblo o exterior), stock de la sucursal.
static func _arrivals(gs) -> void:
	var s := state(gs)
	var trips: Array = s["trips"]
	if trips.is_empty():
		return
	var today: int = gs.today()
	for t in trips.duplicate():
		if int(t.get("arrive", 0)) > today:
			continue
		trips.erase(t)
		var good := str(t["good"])
		var qty := float(t["qty"])
		match str(t["kind"]):
			"sucursal":
				var br := branch(gs, int(str(t.get("key", "-1"))))
				if br.is_empty():
					_return_to_plaza(gs, good, qty)
					continue
				var st: Dictionary = br.get("stock", {})
				st[good] = float(st.get(good, 0.0)) + qty
				br["stock"] = st
			"exportacion":
				var value := qty * float(t["unit"])
				credit_sale(gs, good, value)
				FlowSim.external_in(gs, value, "exportación (distribución)")
				record(gs, "exportacion", good, qty, value)
			"mayorista", "distribuidora":
				var tid := str(t.get("key", ""))
				var town := TradeSim.town(gs, tid)
				var value := qty * float(t["unit"])
				var paid := minf(value, maxf(0.0, float(town.get("cash", 0.0))))
				var paid_q := qty * paid / maxf(0.0001, value)
				if paid > 0.0:
					town["cash"] = float(town["cash"]) - paid
					var row: Dictionary = town.get("goods", {}).get(good, {})
					if not row.is_empty():
						row["sat"] = float(row.get("sat", 0.0)) + paid_q
					if str(t["kind"]) == "distribuidora":
						var d: Dictionary = gs.get_building(int(t.get("dist", -1)))
						if not d.is_empty():
							BusinessSim.earn(gs, d, paid, "ventas")
						else:
							gs.add_money(paid)
					else:
						credit_sale(gs, good, paid)
					record(gs, str(t["kind"]), good, paid_q, paid)
				var back := qty - paid_q
				if back > 0.001:
					# El pueblo no pudo pagar todo: lo que sobra vuelve (a la distribuidora o a la plaza).
					var d2: Dictionary = gs.get_building(int(t.get("dist", -1)))
					if str(t["kind"]) == "distribuidora" and not d2.is_empty():
						_dist_put(d2, good, back, _dist_unit_cost(d2, good))
					else:
						_return_to_plaza(gs, good, back)


## Ventas al detalle de las sucursales: los vecinos del otro pueblo pagan desde la caja del pueblo.
static func _branch_sales(gs) -> void:
	var share := float(cfg().get("branch", {}).get("daily_cash_share", 0.03))
	for br in branches(gs):
		var town := TradeSim.town(gs, str(br["town_id"]))
		if town.is_empty():
			continue
		var st: Dictionary = br.get("stock", {})
		for good in st.keys():
			var have := float(st[good])
			if have <= 0.0001:
				st.erase(good)
				continue
			var q := minf(have, _branch_daily_units(gs, br, str(good)))
			if q <= 0.0:
				continue
			var price := _branch_price(gs, br, str(good))
			var value := minf(q * price, maxf(0.0, float(town.get("cash", 0.0))) * share)
			if value <= 0.0:
				continue
			q = value / price
			town["cash"] = float(town["cash"]) - value
			gs.add_money(value)
			gs.add_counter("ventas_sucursales", value)
			st[good] = have - q
			var row: Dictionary = town.get("goods", {}).get(good, {})
			if not row.is_empty():
				row["sat"] = float(row.get("sat", 0.0)) + q
			_branch_ledger(br, "ventas", value)
			record(gs, "sucursal", str(good), q, value)


## Cierre del mes: estadísticas, costos de las sucursales, tiendas NPC y aperturas de tiendas.
static func monthly(gs) -> void:
	var s := state(gs)
	s["last_month"] = s["month"]
	s["month"] = {}
	s["town_month"] = {}
	s["internal_last"] = float(s.get("internal_month", 0.0))
	s["internal_month"] = 0.0
	s["npc_resale_last"] = float(s.get("npc_resale_month", 0.0))
	s["npc_resale_month"] = 0.0
	s["notes"] = {}
	for b in gs.buildings:
		if b.get("resale_sold") is Dictionary:
			b["resale_sold_last"] = b["resale_sold"]
			b["resale_sold"] = {}
		if is_distributor(gs, b):
			b["dist_internal_last"] = float(b.get("dist_internal_mes", 0.0))
			b["dist_internal_mes"] = 0.0
		# Una tienda NPC que pasó a ser tuya (compra o herencia): su stock de reventa pasa a su inventario.
		if gs.owned_by_player(b) and b.get("resale") is Dictionary and not (b["resale"] as Dictionary).is_empty():
			for g in b["resale"]:
				b["inventory"][g] = float(b["inventory"].get(g, 0.0)) + float(b["resale"][g])
			b["resale"] = {}
	for br in branches(gs).duplicate():
		var town := TradeSim.town(gs, str(br["town_id"]))
		var led: Dictionary = br.get("ledger", {})
		led["last_month"] = led.get("month", {})
		led["month"] = {}
		br["ledger"] = led
		if town.is_empty():
			close_branch(gs, int(br["id"]))
			continue
		var cost := branch_monthly_cost(gs, br)
		gs.add_money(-cost)
		town["cash"] = float(town.get("cash", 0.0)) + cost   # Arriendo y sueldos: vecinos de ese pueblo.
		_branch_ledger(br, "costos", cost)
	_maybe_open_store(gs)


## Si vendes al por mayor un bien que los vecinos buscan y ninguna tienda NPC lo revende, un vecino abre una tienda.
static func _maybe_open_store(gs) -> void:
	var so: Dictionary = cfg().get("store_open", {})
	var s := state(gs)
	var today: int = gs.today()
	if today / 30 < int(so.get("first_month", 4)):
		return
	if s.has("last_store_open") and today - int(s["last_store_open"]) < int(so.get("cooldown_days", 120)):
		return
	var type_id := str(so.get("type", "tienda"))
	var sells: Array = ShopSim.shop_def_of(type_id).get("sells", [])
	var unmet := unmet_units(gs)
	var stores := resellers(gs)
	var best := ""
	var best_u := float(so.get("min_unmet_units", 6))
	for g in unmet:
		if not sells.has(g) or float(unmet[g]) < best_u or available(gs, str(g)) < 1.0:
			continue
		if not (enabled(gs, str(g), "mayorista") or (enabled(gs, str(g), "distribuidora") and not distributors(gs).is_empty())):
			continue
		var covered := false
		for b in stores:
			if reseller_goods(gs, b).has(g):
				covered = true
				break
		if covered:
			continue
		best = str(g)
		best_u = float(unmet[g])
	if best == "":
		return
	var npc_cfg := NpcBusinessSim.cfg()
	var npcs := NpcBusinessSim.npc_buildings(gs).filter(func(b): return str(b.get("npc_state", "")) != NpcBusinessSim.STATE_FOR_SALE)
	if npcs.size() >= maxi(1, int(gs.citizens.size() / maxf(1.0, float(npc_cfg.get("citizens_per_business", 22))))):
		return
	if ConstructionSim.level_block_reason(gs, type_id, 1) != "":
		return
	var who := NpcBusinessSim.find_entrepreneur(gs, type_id)
	if who.is_empty():
		return
	var spot := NpcBusinessSim.find_spot(gs, type_id)
	if spot.is_empty():
		return
	var b := NpcBusinessSim.open_business(gs, who["citizen"], type_id, float(spot["x"]), float(spot["z"]), float(spot["rot"]), float(who["loan"]))
	if not b.is_empty():
		s["last_store_open"] = today
		FreeMarketSim.log_event(gs, "Un vecino abre %s para revender %s comprado al por mayor." % [str(b.get("name", "una tienda")), GameData.good_label(best).to_lower()])


# --- Consultas para la interfaz --------------------------------------------------------------------

## Fila de un producto para el panel: stock, por canal {qty, revenue, price, margin, freight} y config.
static func product_report(gs, good: String, period := "last_month") -> Dictionary:
	var uc := unit_cost(gs, good)
	var chans := {}
	var tq := 0.0
	var tr := 0.0
	for ch in CHANNELS:
		var q := sold(gs, good, ch, period)
		var r := revenue(gs, good, ch, period)
		var f := freight_of(gs, good, ch, period)
		var price := r / q if q > 0.0 else 0.0
		var margin := (r - f - q * uc) / r if r > 0.0 and uc > 0.0 else NAN
		chans[ch] = {"qty": q, "revenue": r, "freight": f, "price": price, "margin": margin}
		tq += q
		tr += r
	return {"good": good, "label": GameData.good_label(good), "stock": available(gs, good), "unit_cost": uc, "channels": chans,
		"qty": tq, "revenue": tr, "market": market_ref(gs, good), "wholesale": wholesale_price(gs, good),
		"min_wholesale": min_wholesale(gs, good), "cfg": product_cfg(gs, good), "rows": stock_rows(gs, good)}


## Clientes mayoristas: tiendas NPC (y lo que piden) y pueblos con ruta (y por qué no llega la carga).
static func clients_report(gs) -> Dictionary:
	var ctx := _context(gs)
	var stores := []
	for b in ctx["stores"]:
		var wants := []
		for g in reseller_goods(gs, b):
			var n := _store_need(gs, ctx, b, g)
			var have := resale_stock(b, g)
			if n > 0.05 or have > 0.05:
				wants.append({"good": g, "need": n, "stock": have})
		stores.append({"id": int(b["id"]), "name": gs.building_label(b), "cash": float(b.get("reserve", 0.0)), "wants": wants})
	var towns := []
	for t in TradeSim.towns(gs):
		var tid := str(t["id"])
		var block := reach_block(gs, ctx, tid)
		towns.append({"id": tid, "name": str(t.get("name", "")), "distance": float(t.get("distance", 0.0)), "cash": float(t.get("cash", 0.0)),
			"block": block, "branch": not branch_in(gs, tid).is_empty(), "demands": t.get("demands", [])})
	return {"stores": stores, "towns": towns, "carriers": ctx["carriers"]}


## Resumen del mes: ingresos por canal (todos los productos).
static func channel_totals(gs, period := "last_month") -> Dictionary:
	var out := {}
	var d: Dictionary = state(gs)[period]
	for g in d:
		for ch in d[g]:
			var a: Array = d[g][ch]
			var row: Dictionary = out.get(ch, {"qty": 0.0, "revenue": 0.0, "freight": 0.0})
			row["qty"] = float(row["qty"]) + float(a[Q])
			row["revenue"] = float(row["revenue"]) + float(a[REV])
			row["freight"] = float(row["freight"]) + float(a[FREIGHT])
			out[ch] = row
	return out
