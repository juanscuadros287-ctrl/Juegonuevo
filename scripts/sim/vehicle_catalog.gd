class_name VehicleCatalog
extends RefCounted
## Catálogo de vehículos por tipo y tecnología (docs/RUTAS_BARCOS.md). API mínima reutilizable (empresas
## NPC, concesionarios y fábricas de vehículos la podrán usar después):
##   VehicleCatalog.models(gs, tipo)   → modelos DESBLOQUEADOS de ese tipo con sus stats
##   VehicleCatalog.stats(gs, modelo)  → {id, label, unit, tipo, capacity, speed_empty, speed_full, price, upkeep,
##                                        fuel_per_km, crew, tech, unlocked, road_kinds, ...}
## Tipos: pie, animal, carreta, camion, tren, barco, avion. Los modelos son los medios de
## resources.json → transport.modes (campo "tipo"); al investigar aparecen modelos más grandes y rápidos
## (carreta → carreta grande; carro de vapor → camión → camión pesado → tráiler; bote → velero → vapor →
## carguero → portacontenedores; avión de hélice → jet de carga; locomotora de vapor → diésel → eléctrica).
##
## Trenes por COMPOSICIÓN: locomotora + vagones por tipo de carga (rutas.json wagon_types: granelero,
## cisterna, cerrado, frigorífico, plataforma, pasajeros). Velocidad = velocidad máx. × potencia / peso
## (acotada), así que el peso total (tara + carga) la baja.

const TIPOS := ["pie", "animal", "carreta", "camion", "tren", "barco", "avion"]
const TIPO_LABELS := {"pie": "A pie (cargadores)", "animal": "Animales de carga", "carreta": "Carretas", "camion": "Camiones",
		"tren": "Trenes", "barco": "Barcos", "avion": "Aviones"}


static func rcfg() -> Dictionary:
	return GameData.extra("rutas")


static func tipo_of(mode: String) -> String:
	var md := LogisticsSim.mode_def(mode)
	return str(md.get("tipo", RouteSim.family(mode)))


static func tipo_label(tipo: String) -> String:
	return str(TIPO_LABELS.get(tipo, tipo))


## Modelos de un tipo (desbloqueados; con include_locked también los que faltan por investigar).
static func models(gs, tipo: String, include_locked := false) -> Array:
	var out := []
	for m in GameData.sorted_ids(LogisticsSim.modes()):
		if tipo_of(str(m)) != tipo:
			continue
		var s := stats(gs, str(m))
		if include_locked or bool(s["unlocked"]):
			out.append(s)
	return out


static func is_train(mode: String) -> bool:
	return tipo_of(mode) == "tren"


## Stats de un modelo. Trenes: con la composición por defecto (4 vagones cerrados).
static func stats(gs, mode: String, comp: Dictionary = {}) -> Dictionary:
	var md := eff_def(gs, mode)
	var tipo := tipo_of(mode)
	var pm: float = gs.price_mult() if gs else 1.0
	var tech := str(md.get("tech", ""))
	var out := {"id": mode, "label": LogisticsSim.mode_label(mode), "unit": str(md.get("unit", mode)), "tipo": tipo,
			"capacity": float(md.get("capacity", 0.0)), "speed_full": float(md.get("speed", 0.0)),
			"speed_empty": float(md.get("speed", 0.0)) * (1.0 + float(rcfg().get("empty_speed_bonus", {}).get(tipo, 0.1))),
			"price": float(md.get("price", 0.0)) * pm, "upkeep": float(md.get("upkeep", 0.0)) * pm, "fuel_per_km": float(md.get("fuel_per_km", 0.0)) * pm,
			"crew": LogisticsSim.crew_per(mode), "tech": tech, "tech_label": GameData.tech_label(tech) if tech != "" else "",
			"unlocked": gs == null or gs.has_tech(tech), "road_kinds": LogisticsSim.road_kinds(mode), "purchasable": bool(md.get("vehicle", false)),
			"spec": spec_of(mode, gs), "durability": float(md.get("durability", 0.0)), "extra_trips": extra_trips(mode, gs)}
	if mode == "pie" and gs != null:
		out["label"] = "%s · %s" % [LogisticsSim.mode_label(mode), str(gear_def(gear_id(gs)).get("label", ""))]
	if tipo == "tren":
		if comp.is_empty():
			comp = default_comp()
		var e := train_estimate(gs, mode, comp)
		out["capacity"] = float(e["capacity"])
		out["speed_empty"] = float(e["speed_empty"])
		out["speed_full"] = float(e["speed_full"])
		out["capacity_by_type"] = e["capacity_by_type"]
		out["max_wagons"] = int(md.get("max_wagons", 10))
	return out


static func stats_text(s: Dictionary) -> String:
	var t := "%s [%s] · %s u./viaje · %s m/día vacío, %s a tope · %s" % [str(s["label"]), spec_short(str(s.get("spec", "general"))), Fmt.thousands(float(s["capacity"])),
			Fmt.thousands(float(s["speed_empty"])), Fmt.thousands(float(s["speed_full"])), Fmt.money(float(s["price"]))]
	if int(s["crew"]) > 1:
		t += " · tripulación %d" % int(s["crew"])
	if not bool(s["unlocked"]):
		t += " · requiere %s" % str(s["tech_label"])
	return t


# --- Trenes por composición --------------------------------------------------------------------------

static func wagon_types() -> Dictionary:
	return rcfg().get("wagon_types", {})


static func wagon_label(wt: String) -> String:
	return str(wagon_def(wt).get("label", wt))


static func default_comp() -> Dictionary:
	return {"cerrado": 4}


## ¿Ese vagón lleva ese bien? "cerrado" lleva todo lo que no es granel especial, líquido ni refrigerado.
static func wagon_accepts(wt: String, good: String) -> bool:
	var d: Dictionary = wagon_def(wt)
	var g = d.get("goods", [])
	if g is String and str(g) == "*":
		for other in ["cisterna", "frigorifico"]:
			if (wagon_types().get(other, {}).get("goods", []) as Array).has(good):
				return false
		return good != ""
	return g is Array and (g as Array).has(good)


static func comp_wagons(comp: Dictionary) -> int:
	var n := 0
	for k in comp:
		n += int(comp[k])
	return n


## Capacidad del tren para un bien ("" = toda la carga que admite).
static func train_capacity(comp: Dictionary, good := "") -> float:
	var cap := 0.0
	for wt in comp:
		var d: Dictionary = wagon_def(str(wt))
		if good == "" or wagon_accepts(str(wt), good):
			cap += float(d.get("capacity", 0.0)) * int(comp[wt])
	return cap


static func train_mass(mode: String, comp: Dictionary, load: float) -> float:
	var m := float(LogisticsSim.mode_def(mode).get("mass", 80.0))
	for wt in comp:
		m += float(wagon_def(str(wt)).get("tare", 20.0)) * int(comp[wt])
	return m + load * float(rcfg().get("unit_mass", 0.1))


## Velocidad (m/día) según potencia y peso.
static func train_speed(mode: String, comp: Dictionary, load: float) -> float:
	var md := LogisticsSim.mode_def(mode)
	var lo := maxf(float(rcfg().get("min_speed_ratio", 0.3)), float(spec_def(spec_of(mode)).get("train_min_speed_ratio", 0.0)))   # pesada: casi no se frena
	var ratio := clampf(float(md.get("power", 900.0)) / (train_mass(mode, comp, load) * 6.0), lo, 1.0)
	return float(md.get("speed", 2400.0)) * ratio


static func comp_price(gs, comp: Dictionary) -> float:
	var p := 0.0
	for wt in comp:
		p += float(wagon_def(str(wt)).get("price", 300.0)) * int(comp[wt])
	return p * (gs.price_mult() if gs else 1.0)


## Estimación antes de comprar: {speed_empty, speed_full, capacity, capacity_by_type, price, wagons}.
static func train_estimate(gs, mode: String, comp: Dictionary) -> Dictionary:
	var cap := train_capacity(comp)
	var by := {}
	for wt in comp:
		if int(comp[wt]) > 0:
			by[str(wt)] = float(wagon_def(str(wt)).get("capacity", 0.0)) * int(comp[wt])
	return {"speed_empty": train_speed(mode, comp, 0.0), "speed_full": train_speed(mode, comp, cap), "capacity": cap, "capacity_by_type": by,
			"price": float(LogisticsSim.mode_def(mode).get("price", 0.0)) * (gs.price_mult() if gs else 1.0) + comp_price(gs, comp), "wagons": comp_wagons(comp)}


static func comp_of(v: Dictionary) -> Dictionary:
	if v.get("comp") is Dictionary:
		return v["comp"]
	if v.has("wagons"):   # Partidas de la primera versión: vagones sin tipo → cerrados.
		v["comp"] = {"cerrado": int(v["wagons"])}
		v.erase("wagons")
		return v["comp"]
	v["comp"] = default_comp()
	return v["comp"]


## Capacidad de un vehículo concreto para un bien.
static func capacity_of(v: Dictionary, good := "") -> float:
	var mode := str(v.get("mode", ""))
	if is_train(mode):
		return train_capacity(comp_of(v), good)
	return float(LogisticsSim.mode_def(mode).get("capacity", 10.0)) * cargo_mult(mode, good)


## Velocidad de un vehículo con esa carga.
static func speed_of(v: Dictionary, load: float) -> float:
	var mode := str(v.get("mode", ""))
	if is_train(mode):
		return train_speed(mode, comp_of(v), load) * wear_speed_mult(v)
	return float(LogisticsSim.mode_def(mode).get("speed", 180.0)) * wear_speed_mult(v)


static func comp_text(comp: Dictionary) -> String:
	var parts := []
	for wt in comp:
		if int(comp[wt]) > 0:
			parts.append("%d %s" % [int(comp[wt]), wagon_label(str(wt)).to_lower()])
	return ", ".join(parts) if not parts.is_empty() else "sin vagones"


# --- Variedad: especialidades, clases de carga, merma y desgaste (docs/VEHICULOS.md) -------------------

const SPECS := ["general", "refrigerado", "granel", "liquidos", "pasajeros", "lujo", "todoterreno", "pesada", "express"]


static func spec_cfg() -> Dictionary:
	return rcfg().get("specialties", {})


static func spec_def(spec: String) -> Dictionary:
	var d = spec_cfg().get(spec, {})
	return d if d is Dictionary else {}


static func spec_label(spec: String) -> String:
	return str(spec_def(spec).get("label", spec.capitalize()))


static func spec_short(spec: String) -> String:
	return str(spec_def(spec).get("short", spec.left(4).to_upper()))


static func spec_color(spec: String) -> Color:
	return Color(str(spec_def(spec).get("color", "#9aa4ad")))


static func spec_desc(spec: String) -> String:
	return str(spec_def(spec).get("desc", ""))


## Especialidad de un modelo (a pie: la del equipo de los cargadores, que depende de la partida).
static func spec_of(mode: String, gs = null) -> String:
	if mode == "pie" and gs != null:
		return str(gear_def(gear_id(gs)).get("spec", "general"))
	return str(LogisticsSim.mode_def(mode).get("spec", "general"))


static func cargo_classes() -> Dictionary:
	return rcfg().get("cargo_classes", {})


static func class_goods(cls: String) -> Array:
	var d = cargo_classes().get(cls, {})
	return d.get("goods", []) if d is Dictionary else []


static func class_label(cls: String) -> String:
	var d = cargo_classes().get(cls, {})
	return str(d.get("label", cls)) if d is Dictionary else cls


static func in_class(good: String, cls: String) -> bool:
	return good != "" and class_goods(cls).has(good)


## Clases de carga de un bien (un bien puede estar en varias: el hierro es granel y carga pesada).
static func classes_of(good: String) -> Array:
	var out := []
	for cls in cargo_classes():
		if not str(cls).begins_with("_") and in_class(good, str(cls)):
			out.append(str(cls))
	return out


static func spec_protects(spec: String, cls: String) -> bool:
	return (spec_def(spec).get("protects", []) as Array).has(cls)


## Multiplicador de capacidad de una especialidad para un bien ("" = sin bien concreto → 1).
static func spec_cargo_mult(spec: String, good: String) -> float:
	if good == "":
		return 1.0
	var cargo: Dictionary = spec_def(spec).get("cargo", {})
	if cargo.is_empty():
		return 1.0
	for cls in classes_of(good):
		if spec_protects(spec, cls):
			return 1.0
	var best := -1.0
	for cls in cargo:
		if str(cls) != "_other" and in_class(good, str(cls)):
			best = maxf(best, float(cargo[cls]))
	return best if best >= 0.0 else float(cargo.get("_other", 1.0))


static func cargo_mult(mode: String, good: String, gs = null) -> float:
	if is_train(mode):
		return 1.0   # En los trenes manda cada vagón (acepta o no el bien).
	return spec_cargo_mult(spec_of(mode, gs), good)


## ¿Puede ese modelo llevar ese bien? (una cisterna no lleva madera, un coche de pasajeros no lleva carga)
static func can_carry(mode: String, good: String, gs = null) -> bool:
	return cargo_mult(mode, good, gs) > 0.0


## Viajes extra por día (express).
static func extra_trips(mode: String, gs = null) -> int:
	return int(spec_def(spec_of(mode, gs)).get("extra_trips", 0))


## Multiplicador mínimo de carretera (todoterreno: en barro va como en empedrado). 0 = sin mínimo.
static func road_min_mult(mode: String) -> float:
	return float(spec_def(spec_of(mode)).get("road_min_mult", 0.0))


## Alcance fuera de camino de los animales (todoterreno: más lejos por el monte).
static func offroad_range_mult(mode: String) -> float:
	return float(spec_def(spec_of(mode)).get("offroad_range_mult", 1.0))


## Fracción de la carga que se pierde en el camino (perecederos sin frío, valiosos sin vehículo de valores).
## Determinista: depende de los días de viaje de ida. v = vehículo concreto ({} = cualquiera del modelo).
static func loss_frac(mode: String, good: String, travel_days: float, v: Dictionary = {}, gs = null) -> float:
	var worst := 0.0
	var losses: Dictionary = rcfg().get("cargo_loss", {})
	var spec := spec_of(mode, gs)
	for cls in classes_of(good):
		var L = losses.get(cls, {})
		if not (L is Dictionary) or (L as Dictionary).is_empty():
			continue
		var unprotected := 1.0
		if is_train(mode):
			unprotected = _train_unprotected(comp_of(v) if not v.is_empty() else default_comp(), good, cls)
		elif spec_protects(spec, cls):
			unprotected = 0.0
		if unprotected <= 0.0:
			continue
		var rate := float(L.get("per_day", 0.0)) * float(spec_def(spec).get("loss_mult", 1.0))
		var f := clampf((travel_days - float(L.get("grace", 1.0))) * rate, 0.0, float(L.get("cap", 0.3)))
		worst = maxf(worst, f * unprotected)
	return worst


## Parte de la capacidad del tren para ese bien que va en vagones que NO protegen esa clase.
static func _train_unprotected(comp: Dictionary, good: String, cls: String) -> float:
	var total := 0.0
	var bad := 0.0
	for wt in comp:
		if int(comp[wt]) <= 0 or not wagon_accepts(str(wt), good):
			continue
		var c := float(wagon_def(str(wt)).get("capacity", 0.0)) * int(comp[wt])
		total += c
		if not spec_protects(str(wagon_def(str(wt)).get("spec", "general")), cls):
			bad += c
	return bad / total if total > 0.0 else 0.0


# --- Desgaste y revisión ----------------------------------------------------------------------------

static func wear_cfg() -> Dictionary:
	return rcfg().get("wear", {})


static func durability_of(mode: String) -> float:
	return float(LogisticsSim.mode_def(mode).get("durability", 0.0))


## Vida usada desde la última revisión (1 = llegó a su durabilidad).
static func wear_of(v: Dictionary) -> float:
	var dur := durability_of(str(v.get("mode", "")))
	if dur <= 0.0:
		return 0.0
	return maxf(0.0, float(v.get("km", 0.0)) - float(v.get("serviced_km", 0.0))) / dur


static func wear_upkeep_mult(v: Dictionary) -> float:
	var w := wear_of(v)
	if w <= 1.0:
		return 1.0
	return minf(1.0 + (w - 1.0) * float(wear_cfg().get("upkeep_per_life", 0.5)) + 0.25, float(wear_cfg().get("max_upkeep_mult", 2.0)))


static func wear_speed_mult(v: Dictionary) -> float:
	return float(wear_cfg().get("worn_speed_mult", 0.9)) if wear_of(v) > 1.0 else 1.0


static func overhaul_price(gs, v: Dictionary) -> float:
	return LogisticsSim.vehicle_price(gs, str(v.get("mode", ""))) * float(wear_cfg().get("overhaul_frac", 0.35))


# --- A pie: equipo de los cargadores ----------------------------------------------------------------

static func gear_defs() -> Dictionary:
	var out := {}
	var g: Dictionary = rcfg().get("porter_gear", {})
	for k in g:
		if not str(k).begins_with("_"):
			out[str(k)] = g[k]
	return out


static func gear_def(id: String) -> Dictionary:
	var d = gear_defs().get(id, gear_defs().get("mecapal", {}))
	return d if d is Dictionary else {}


static func gear_ids() -> Array:
	var ids := gear_defs().keys()
	ids.sort_custom(func(a, b): return float(gear_def(str(a)).get("order", 0)) < float(gear_def(str(b)).get("order", 0)))
	return ids


static func gear_id(gs) -> String:
	if gs == null:
		return "mecapal"
	var g := str(gs.logistics.get("porter_gear", "mecapal"))
	return g if gear_defs().has(g) else "mecapal"


## Cargadores que se equipan (empleados de las centrales que operan a pie; mínimo 4).
static func porters(gs) -> int:
	var n := 0
	for b in LogisticsSim.stations(gs):
		if LogisticsSim.central_supports(gs, b, "pie"):
			n += LogisticsSim.crew_size(gs, b)
	return maxi(4, n)


static func gear_price(gs, id: String) -> float:
	return float(gear_def(id).get("price", 0.0)) * porters(gs) * (gs.price_mult() if gs else 1.0)


## Definición efectiva de un medio: a pie toma capacidad, velocidad, consumo y especialidad del equipo.
static func eff_def(gs, mode: String) -> Dictionary:
	var md := LogisticsSim.mode_def(mode)
	if mode != "pie" or gs == null:
		return md
	var g := gear_def(gear_id(gs))
	var out := md.duplicate()
	for k in ["capacity", "speed", "fuel_per_km", "upkeep", "spec"]:
		if g.has(k):
			out[k] = g[k]
	return out


# --- Vagones por modelo -------------------------------------------------------------------------------

## Definición completa de un vagón: hereda de su clase (granelero, cisterna, cerrado, frigorífico,
## plataforma, pasajeros) lo que no define; "@clase" en goods = bienes de esa clase de carga.
static func wagon_def(wt: String) -> Dictionary:
	var d: Dictionary = wagon_types().get(wt, {})
	if d.is_empty():
		return d
	var clase := str(d.get("clase", wt))
	var out: Dictionary = {}
	if clase != wt and wagon_types().has(clase):
		out = (wagon_types()[clase] as Dictionary).duplicate()
	for k in d:
		out[k] = d[k]
	out["clase"] = clase
	var g = out.get("goods", [])
	if g is String and str(g).begins_with("@"):
		out["goods"] = class_goods(str(g).substr(1))
	return out


static func wagon_unlocked(gs, wt: String) -> bool:
	var t := str(wagon_def(wt).get("tech", ""))
	return gs == null or t == "" or gs.has_tech(t)


## Vagones (ids) en orden de clase y precio; include_locked también los que faltan por investigar.
static func wagon_ids(gs = null, include_locked := true) -> Array:
	var ids := []
	for wt in wagon_types():
		if str(wt).begins_with("_"):
			continue
		if include_locked or wagon_unlocked(gs, str(wt)):
			ids.append(str(wt))
	var order := wagon_types().keys()
	ids.sort_custom(func(a, b):
		var ca := order.find(str(wagon_def(str(a)).get("clase", a)))
		var cb := order.find(str(wagon_def(str(b)).get("clase", b)))
		if ca != cb:
			return ca < cb
		return float(wagon_def(str(a)).get("price", 0)) < float(wagon_def(str(b)).get("price", 0)))
	return ids


# --- Partidas viejas ------------------------------------------------------------------------------------

## Mapea un vehículo guardado a los modelos actuales y rellena los campos nuevos. Devuelve true si cambió.
static func migrate_vehicle(v: Dictionary) -> bool:
	var changed := false
	var mode := str(v.get("mode", ""))
	var legacy: Dictionary = rcfg().get("legacy_modes", {})
	if LogisticsSim.mode_def(mode).is_empty() and legacy.has(mode):
		v["mode"] = str(legacy[mode])
		changed = true
	for k in ["km", "serviced_km"]:
		if not v.has(k):
			v[k] = 0.0
			changed = true
	if not v.has("trips"):
		v["trips"] = 0
		changed = true
	if is_train(str(v.get("mode", ""))):
		var comp := comp_of(v)
		for wt in comp.keys():
			if not wagon_types().has(str(wt)):
				var dest := str(legacy.get(str(wt), "cerrado"))
				if not wagon_types().has(dest):
					dest = "cerrado"
				comp[dest] = int(comp.get(dest, 0)) + int(comp[wt])
				comp.erase(wt)
				changed = true
	return changed


## Ficha comparativa de un modelo (panel de compra y pruebas).
static func sheet(gs, mode: String, comp: Dictionary = {}) -> Dictionary:
	var s := stats(gs, mode, comp)
	var spec := str(s.get("spec", "general"))
	var fx := []
	var cargo: Dictionary = spec_def(spec).get("cargo", {})
	for cls in cargo:
		if str(cls) != "_other":
			fx.append("%+d %% %s" % [int(round((float(cargo[cls]) - 1.0) * 100.0)), class_label(str(cls)).to_lower()])
	if cargo.has("_other"):
		fx.append("resto ×%.2f" % float(cargo["_other"]) if float(cargo["_other"]) > 0.0 else "no lleva otra carga")
	for cls in spec_def(spec).get("protects", []):
		fx.append("%s sin merma" % class_label(str(cls)).to_lower())
	if int(spec_def(spec).get("extra_trips", 0)) > 0:
		fx.append("+%d viaje/día" % int(spec_def(spec)["extra_trips"]))
	if float(spec_def(spec).get("road_min_mult", 0.0)) > 0.0:
		fx.append("camino malo como empedrado")
	s["effects"] = fx
	s["spec_label"] = spec_label(spec)
	s["spec_desc"] = spec_desc(spec)
	return s
