class_name ModulesSim
extends RefCounted
## Módulos o submejoras por edificio (docs/MODULOS.md): además del nivel del edificio, cada negocio
## del jugador tiene líneas de mejora con SU PROPIO nivel (datos en data/modulos.json):
##   - "almacen": almacén integrado. TODO negocio productor o comercio lo tiene desde el nivel 1
##     (base, 100 espacios) y se amplía por niveles. Es un almacén más de WarehouseSim (mismo id que
##     el edificio), privado del negocio: toma insumos y guarda la producción ahí primero y luego en
##     el almacén separado que tenga al lado. Rutas y distribución lo ven como cualquier almacén.
##   - "parqueadero": parqueadero y flota de la empresa. Define cuántos y qué tipos de vehículos de
##     carga puede tener ASIGNADOS el negocio (fleet_limit / fleet_types). Los vehículos se compran
##     en el panel central de Vehículos (otro módulo) y la conexión que exige cada tipo (carretera,
##     rieles, agua o pista) la valida quien asigna. Nivel 1 = cargadores a pie (solo vacantes).
## Estado en el diccionario del edificio (valores por defecto: almacén en su nivel base, sin flota):
##   b["modules"]     = {"almacen": nivel, "parqueadero": nivel}
##   b["module_work"] = {"module", "target", "done", "needed", "start"}   (obra en curso, una a la vez)
## La obra de un módulo NO detiene el negocio (sigue produciendo y facturando). Los pagos (obra y
## mantenimiento mensual) van a proveedores y contratistas del pueblo: la economía queda cerrada.

const ALMACEN := "almacen"
const PARQUEADERO := "parqueadero"

static var _cargo_cache := {}


static func cfg() -> Dictionary:
	return GameData.extra("modulos")


static func module_ids() -> Array:
	return cfg().get("order", [ALMACEN, PARQUEADERO])


static func mdef(m: String) -> Dictionary:
	return cfg().get("modules", {}).get(m, {})


static func label(m: String) -> String:
	return str(mdef(m).get("label", m))


static func max_level(m: String) -> int:
	return (mdef(m).get("levels", []) as Array).size()


## Definición del nivel `lvl` (1..max) de un módulo; {} si no existe.
static func mlevel(m: String, lvl: int) -> Dictionary:
	var ls: Array = mdef(m).get("levels", [])
	if lvl < 1 or lvl > ls.size():
		return {}
	return ls[lvl - 1]


## Nivel incluido sin obra (el almacén integrado nivel 1 en negocios productores y comercios).
static func base_level(b: Dictionary, m: String) -> int:
	if m == ALMACEN and is_cargo_type(str(b.get("type", "")), int(b.get("level", 1))):
		return int(mdef(m).get("base_level", 1))
	return 0


## Nivel actual del módulo (lo guardado o, si no hay nada, el nivel base).
static func level(b: Dictionary, m: String) -> int:
	var stored := 0
	var mods = b.get("modules", null)
	if mods is Dictionary:
		stored = int((mods as Dictionary).get(m, 0))
	return maxi(stored, base_level(b, m))


static func cur(b: Dictionary, m: String) -> Dictionary:
	return mlevel(m, level(b, m))


static func work(b: Dictionary) -> Dictionary:
	var w = b.get("module_work", null)
	return w if w is Dictionary else {}


# --- A qué edificios aplica ----------------------------------------------------------------------

## Negocio productor o comercio (no servicios, no transporte, no almacenes): necesita guardar
## insumos y producción. Por tipo y nivel, con caché.
static func is_cargo_type(type_id: String, lvl := 1) -> bool:
	var key := "%s|%d" % [type_id, lvl]
	if _cargo_cache.has(key):
		return _cargo_cache[key]
	var def := GameData.building_def(type_id)
	var ld := GameData.level_def(type_id, lvl)
	var ok := false
	if str(def.get("category", "")) == "negocio" and float(ld.get("warehouse_capacity", 0.0)) <= 0.0 and not ld.has("transport_modes"):
		var product := str(def.get("product", ""))
		var gd: Dictionary = GameData.goods.get(product, {})
		ok = LogisticsSim.uses_chain(def, ld) or product == "comercio" or type_id == "tienda" or bool(def.get("warehouse_shop", false)) \
				or (not gd.is_empty() and bool(gd.get("storable", true)) and not bool(gd.get("internal", false)))
	_cargo_cache[key] = ok
	return ok


static func applies(gs, b: Dictionary, m: String) -> bool:
	if b.is_empty() or not gs.owned_by_player(b) or mdef(m).is_empty():
		return false
	return is_cargo_type(str(b.get("type", "")), int(b.get("level", 1)))


static func applies_any(gs, b: Dictionary) -> bool:
	for m in module_ids():
		if applies(gs, b, str(m)):
			return true
	return false


## Nivel mínimo del edificio para un nivel de módulo (acotado al nivel máximo del tipo).
static func min_building_level(b: Dictionary, m: String, lvl: int) -> int:
	return mini(int(mlevel(m, lvl).get("min_building_level", 1)), maxi(1, GameData.max_level(str(b.get("type", "")))))


# --- Efectos --------------------------------------------------------------------------------------

## Capacidad del almacén integrado (0 si el negocio no lo tiene).
static func warehouse_capacity(b: Dictionary) -> float:
	var l := level(b, ALMACEN)
	if l <= 0:
		return 0.0
	return float(mlevel(ALMACEN, l).get("capacity", 0.0))


## ¿El almacén `wid` es SOLO un almacén integrado (privado de su negocio)?
static func is_private_warehouse(gs, wid: int) -> bool:
	if wid <= 0:
		return false
	var b: Dictionary = gs.get_building(wid)
	return not b.is_empty() and float(gs.level_def(b).get("warehouse_capacity", 0.0)) <= 0.0 and warehouse_capacity(b) > 0.0


## Cuántos vehículos (o cargadores, "pie") de ese tipo puede tener asignados el negocio según su
## módulo Parqueadero y flota. 0 = no admite ese tipo. La conexión la valida quien asigna.
static func fleet_limit(gs, b: Dictionary, tipo: String) -> int:
	if not applies(gs, b, PARQUEADERO) or level(b, PARQUEADERO) <= 0:
		return 0
	return int(cur(b, PARQUEADERO).get("limits", {}).get(tipo, 0))


## Tipos que admite el negocio (en el orden de los medios de transporte).
static func fleet_types(gs, b: Dictionary) -> Array:
	if not applies(gs, b, PARQUEADERO) or level(b, PARQUEADERO) <= 0:
		return []
	var lim: Dictionary = cur(b, PARQUEADERO).get("limits", {})
	var out := []
	for k in lim:
		if int(lim[k]) > 0:
			out.append(str(k))
	out.sort_custom(func(a, c): return int(LogisticsSim.mode_def(a).get("order", 99)) < int(LogisticsSim.mode_def(c).get("order", 99)))
	return out


## Metros que crece la huella del edificio por sus módulos (GameState.footprint_of).
static func footprint_extra(b: Dictionary) -> float:
	var mods = b.get("modules", null)
	if not (mods is Dictionary) or (mods as Dictionary).is_empty():
		return 0.0
	var e := 0.0
	for m in mods:
		e += float(mlevel(str(m), int(mods[m])).get("footprint_add", 0.0))
	return e


## Lo máximo que pueden crecer los módulos de un tipo de edificio (reserva al colocar).
static func max_footprint_extra(type_id: String) -> float:
	if not is_cargo_type(type_id, GameData.max_level(type_id)) and not is_cargo_type(type_id, 1):
		return 0.0
	var e := 0.0
	for m in module_ids():
		var mx := 0.0
		for ld in mdef(str(m)).get("levels", []):
			mx = maxf(mx, float(ld.get("footprint_add", 0.0)))
		e += mx
	return e


## Huella de crecimiento de un tipo: la del nivel máximo + los módulos al máximo.
static func growth_footprint(type_id: String) -> float:
	var fp := 0.0
	for l in range(1, maxi(1, GameData.max_level(type_id)) + 1):
		fp = maxf(fp, GameData.footprint(type_id, l))
	return fp + max_footprint_extra(type_id)


static var _reserve_cache := {}


## Huella que se reserva al colocar (negocios y viviendas: la de crecimiento; lo demás, la de nivel 1).
static func reserve_footprint(type_id: String) -> float:
	if _reserve_cache.has(type_id):
		return _reserve_cache[type_id]
	var cat := str(GameData.building_def(type_id).get("category", ""))
	var fp := growth_footprint(type_id) if cat == "negocio" or cat == "vivienda" else GameData.footprint(type_id, 1)
	_reserve_cache[type_id] = fp
	return fp


## Mantenimiento mensual de todos los módulos del edificio (× price_mult).
static func monthly_upkeep(gs, b: Dictionary) -> float:
	var total := 0.0
	for m in module_ids():
		total += float(cur(b, str(m)).get("upkeep", 0.0))
	return total * gs.price_mult()


# --- Costos y requisitos --------------------------------------------------------------------------

## {money, from_stock, import, import_cost, total, days} del nivel `lvl` de un módulo.
static func cost(gs, m: String, lvl: int) -> Dictionary:
	var ld := mlevel(m, lvl)
	var pm: float = gs.price_mult()
	var money := float(ld.get("cost", 0.0)) * pm
	var mats: Dictionary = ld.get("materials", {})
	var from_stock := {}
	var imports := {}
	var import_cost := 0.0
	for g in mats:
		var need := ceilf(float(mats[g]))
		var use := minf(ConstructionSim.stock_of(gs, str(g)), need)
		from_stock[g] = use
		imports[g] = need - use
		import_cost += (need - use) * float(GameData.goods.get(g, {}).get("import_price", 5.0)) * pm * GovSim.import_mult(gs)
	return {"money": money, "materials": mats, "from_stock": from_stock, "import": imports, "import_cost": import_cost,
		"total": money + import_cost, "days": int(ld.get("days", 10))}


## Motivo por el que no se puede mejorar el módulo al siguiente nivel ("" si se puede).
static func block_reason(gs, b: Dictionary, m: String) -> String:
	if not applies(gs, b, m):
		return "Este edificio no admite ese módulo"
	var next := level(b, m) + 1
	var ld := mlevel(m, next)
	if ld.is_empty():
		return "Nivel máximo del módulo"
	var req := requirement_reason(gs, b, m, next)
	if req != "":
		return req
	if str(b.get("status", "")) == "construccion":
		return "El edificio aún está en obra"
	if not work(b).is_empty():
		return "Ya hay una obra de módulo en curso (%s)" % label(str(work(b).get("module", "")))
	var space := space_reason(gs, b, float(ld.get("footprint_add", 0.0)) - float(cur(b, m).get("footprint_add", 0.0)))
	if space != "":
		return space
	var c := cost(gs, m, next)
	if gs.money < float(c["total"]):
		return "Dinero insuficiente (%s)" % Fmt.money(float(c["total"]))
	return ""


## Requisitos de investigación, época, nivel del edificio y otros módulos ("" si se cumplen).
static func requirement_reason(gs, b: Dictionary, m: String, lvl: int) -> String:
	var ld := mlevel(m, lvl)
	var tech := str(ld.get("tech", ""))
	if not gs.has_tech(tech):
		return "Requiere investigar: %s (%s)" % [GameData.tech_label(tech), GameData.era_label(int(GameData.technologies.get(tech, {}).get("era", 1)))]
	var need := min_building_level(b, m, lvl)
	if int(b.get("level", 1)) < need:
		return "Requiere el edificio en nivel %d (%s)" % [need, str(GameData.level_def(str(b["type"]), need).get("label", ""))]
	var rm: Dictionary = (mdef(m).get("requires_module", {}) as Dictionary).duplicate()
	rm.merge(ld.get("requires_module", {}), true)
	for other in rm:
		if level(b, str(other)) < int(rm[other]):
			return "Requiere %s nivel %d (%s)" % [label(str(other)), int(rm[other]), str(mlevel(str(other), int(rm[other])).get("label", ""))]
	return ""


## La huella crece `grow` metros: debe quedar espacio libre alrededor.
static func space_reason(gs, b: Dictionary, grow: float) -> String:
	if grow <= 0.01:
		return ""
	var fp: float = float(gs.footprint_of(b)) + grow
	var p := Vector2(float(b["x"]), float(b["z"]))
	for o in gs.buildings:
		if int(o["id"]) == int(b["id"]):
			continue
		if p.distance_to(Vector2(float(o["x"]), float(o["z"]))) < (fp + float(gs.footprint_of(o))) * 0.5 + 0.8:
			return "No hay espacio para ampliar el módulo (%.0f m): choca con %s" % [fp, gs.building_label(o)]
	return ""


# --- Acciones ---------------------------------------------------------------------------------

## Inicia la obra del siguiente nivel de un módulo. Devuelve "" o el motivo del bloqueo.
static func start(gs, b: Dictionary, m: String) -> String:
	var reason := block_reason(gs, b, m)
	if reason != "":
		return reason
	var next := level(b, m) + 1
	var c := cost(gs, m, next)
	for g in c["from_stock"]:
		ConstructionSim._consume_stock(gs, str(g), float(c["from_stock"][g]))
	_spend(gs, b, float(c["total"]), "obras")
	b["module_work"] = {"module": m, "target": next, "done": 0.0, "needed": maxf(1.0, float(c["days"])), "start": gs.today()}
	gs.notify("Obra de módulo iniciada: %s → %s (%d días). El negocio sigue funcionando." % [gs.building_label(b), str(mlevel(m, next).get("label", "")), int(c["days"])], "construccion")
	EventBus.building_changed.emit(int(b["id"]))
	return ""


## Días que faltan para terminar la obra de módulo en curso.
static func days_left(gs, b: Dictionary) -> int:
	var w := work(b)
	if w.is_empty():
		return 0
	return int(ceil(maxf(0.0, float(w["needed"]) - float(w["done"])) / maxf(0.1, TechSim.mult(gs, "construction_speed"))))


## Pago del jugador que se queda en el pueblo: el negocio lo registra (obras/mantenimiento) y el
## dinero va a vecinos sin empleo (contratistas y proveedores); sin ellos, al tesoro municipal.
static func _spend(gs, b: Dictionary, amount: float, key: String) -> void:
	if amount <= 0.0:
		return
	BusinessSim.pay(gs, b, amount, key)
	_pay_local(gs, amount)


static func _pay_local(gs, amount: float) -> void:
	var adult := int(GameData.citizens.get("adult_age", 16))
	var today: int = gs.today()
	var pool := []
	for c in gs.citizens.values():
		if c.job_id < 0 and not gs.is_player(c.id) and c.prison_until < 0 and c.age_years(today) >= adult:
			pool.append(c)
			if pool.size() >= 40:
				break
	if pool.is_empty():
		GovSim.add_treasury(gs, amount)
		return
	var n := mini(4, pool.size())
	var start_i := today % pool.size()
	for i in range(n):
		var c: Citizen = pool[(start_i + i) % pool.size()]
		c.money += amount / n


# --- Simulación ---------------------------------------------------------------------------------

static func daily(gs) -> void:
	var speed: float = TechSim.mult(gs, "construction_speed")
	for b in gs.buildings:
		if not b.has("module_work"):
			continue
		var w := work(b)
		if w.is_empty() or not gs.owned_by_player(b):
			b.erase("module_work")
			continue
		w["done"] = float(w.get("done", 0.0)) + speed
		if float(w["done"]) >= float(w.get("needed", 1.0)):
			_complete(gs, b, str(w.get("module", "")), int(w.get("target", 1)))


static func _complete(gs, b: Dictionary, m: String, target: int) -> void:
	b.erase("module_work")
	var mods = b.get("modules", null)
	if not (mods is Dictionary):
		mods = {}
	mods[m] = target
	b["modules"] = mods
	LogisticsSim.on_buildings_changed(gs)   # El almacén integrado crece en WarehouseSim.
	_absorb_yard(gs, b)
	gs.notify("Módulo terminado: %s — %s." % [gs.building_label(b), str(mlevel(m, target).get("label", ""))], "construccion")
	EventBus.building_changed.emit(int(b["id"]))


## Lo que esperaba en el patio (inventario local de la cadena) pasa al almacén integrado si cabe.
static func _absorb_yard(gs, b: Dictionary) -> void:
	if not WarehouseSim.is_warehouse_building(gs, b) or not LogisticsSim.uses_chain(gs.building_def(b), gs.level_def(b)):
		return
	var product := str(gs.building_def(b).get("product", ""))
	var inv: Dictionary = b.get("inventory", {})
	var q := float(inv.get(product, 0.0))
	if q > 0.0 and product != "" and bool(GameData.goods.get(product, {}).get("storable", true)):
		inv[product] = q - WarehouseSim.add_to(gs, int(b["id"]), product, q)


## Mantenimiento mensual de los módulos (se cobra al cerrar el mes, antes de BusinessSim.monthly).
static func monthly(gs) -> void:
	for b in gs.buildings:
		if not b.has("modules") or not gs.owned_by_player(b):
			continue
		var up := monthly_upkeep(gs, b)
		if up > 0.0:
			_spend(gs, b, up, "mantenimiento")


# --- Texto para la interfaz ----------------------------------------------------------------------

## Beneficios de un nivel de módulo en una línea.
static func benefits_text(gs, b: Dictionary, m: String, lvl: int) -> String:
	var ld := mlevel(m, lvl)
	if ld.is_empty():
		return "—"
	match m:
		ALMACEN:
			return "%s espacios propios (toma insumos y guarda la producción aquí)" % Fmt.thousands(float(ld.get("capacity", 0)))
		PARQUEADERO:
			var lim: Dictionary = ld.get("limits", {})
			var keys := lim.keys()
			keys.sort_custom(func(a, c): return int(LogisticsSim.mode_def(str(a)).get("order", 99)) < int(LogisticsSim.mode_def(str(c)).get("order", 99)))
			var names := []
			for k in keys:
				names.append("%d %s" % [int(lim[k]), LogisticsSim.mode_short(str(k))])
			return "puede tener asignados: " + ", ".join(names)
	return ""


## Resumen corto de los módulos del edificio ("" si no aplica).
static func summary_line(gs, b: Dictionary) -> String:
	if not applies_any(gs, b):
		return ""
	var parts := []
	for m in module_ids():
		parts.append("%s %d" % [label(str(m)), level(b, str(m))])
	var w := work(b)
	if not w.is_empty():
		parts.append("obra: %s → %d (%d días)" % [label(str(w.get("module", ""))), int(w.get("target", 1)), days_left(gs, b)])
	return "Módulos: " + " · ".join(parts) + "\n"
