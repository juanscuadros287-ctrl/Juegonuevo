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
	var md := LogisticsSim.mode_def(mode)
	var tipo := tipo_of(mode)
	var pm: float = gs.price_mult() if gs else 1.0
	var tech := str(md.get("tech", ""))
	var out := {"id": mode, "label": LogisticsSim.mode_label(mode), "unit": str(md.get("unit", mode)), "tipo": tipo,
			"capacity": float(md.get("capacity", 0.0)), "speed_full": float(md.get("speed", 0.0)),
			"speed_empty": float(md.get("speed", 0.0)) * (1.0 + float(rcfg().get("empty_speed_bonus", {}).get(tipo, 0.1))),
			"price": float(md.get("price", 0.0)) * pm, "upkeep": float(md.get("upkeep", 0.0)) * pm, "fuel_per_km": float(md.get("fuel_per_km", 0.0)) * pm,
			"crew": LogisticsSim.crew_per(mode), "tech": tech, "tech_label": GameData.tech_label(tech) if tech != "" else "",
			"unlocked": gs == null or gs.has_tech(tech), "road_kinds": LogisticsSim.road_kinds(mode), "purchasable": bool(md.get("vehicle", false))}
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
	var t := "%s · %s u./viaje · %s m/día vacío, %s a tope · %s" % [str(s["label"]), Fmt.thousands(float(s["capacity"])),
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
	return str(wagon_types().get(wt, {}).get("label", wt))


static func default_comp() -> Dictionary:
	return {"cerrado": 4}


## ¿Ese vagón lleva ese bien? "cerrado" lleva todo lo que no es granel especial, líquido ni refrigerado.
static func wagon_accepts(wt: String, good: String) -> bool:
	var d: Dictionary = wagon_types().get(wt, {})
	var g = d.get("goods", [])
	if g is String and str(g) == "*":
		for other in wagon_types():
			if str(other) in ["cisterna", "frigorifico"] and (wagon_types()[other].get("goods", []) as Array).has(good):
				return false
		return good != ""
	return (g as Array).has(good)


static func comp_wagons(comp: Dictionary) -> int:
	var n := 0
	for k in comp:
		n += int(comp[k])
	return n


## Capacidad del tren para un bien ("" = toda la carga que admite).
static func train_capacity(comp: Dictionary, good := "") -> float:
	var cap := 0.0
	for wt in comp:
		var d: Dictionary = wagon_types().get(str(wt), {})
		if good == "" or wagon_accepts(str(wt), good):
			cap += float(d.get("capacity", 0.0)) * int(comp[wt])
	return cap


static func train_mass(mode: String, comp: Dictionary, load: float) -> float:
	var m := float(LogisticsSim.mode_def(mode).get("mass", 80.0))
	for wt in comp:
		m += float(wagon_types().get(str(wt), {}).get("tare", 20.0)) * int(comp[wt])
	return m + load * float(rcfg().get("unit_mass", 0.1))


## Velocidad (m/día) según potencia y peso.
static func train_speed(mode: String, comp: Dictionary, load: float) -> float:
	var md := LogisticsSim.mode_def(mode)
	var ratio := clampf(float(md.get("power", 900.0)) / (train_mass(mode, comp, load) * 6.0), float(rcfg().get("min_speed_ratio", 0.3)), 1.0)
	return float(md.get("speed", 2400.0)) * ratio


static func comp_price(gs, comp: Dictionary) -> float:
	var p := 0.0
	for wt in comp:
		p += float(wagon_types().get(str(wt), {}).get("price", 300.0)) * int(comp[wt])
	return p * (gs.price_mult() if gs else 1.0)


## Estimación antes de comprar: {speed_empty, speed_full, capacity, capacity_by_type, price, wagons}.
static func train_estimate(gs, mode: String, comp: Dictionary) -> Dictionary:
	var cap := train_capacity(comp)
	var by := {}
	for wt in comp:
		if int(comp[wt]) > 0:
			by[str(wt)] = float(wagon_types().get(str(wt), {}).get("capacity", 0.0)) * int(comp[wt])
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
	return float(LogisticsSim.mode_def(mode).get("capacity", 10.0))


## Velocidad de un vehículo con esa carga.
static func speed_of(v: Dictionary, load: float) -> float:
	var mode := str(v.get("mode", ""))
	if is_train(mode):
		return train_speed(mode, comp_of(v), load)
	return float(LogisticsSim.mode_def(mode).get("speed", 180.0))


static func comp_text(comp: Dictionary) -> String:
	var parts := []
	for wt in comp:
		if int(comp[wt]) > 0:
			parts.append("%d %s" % [int(comp[wt]), wagon_label(str(wt)).to_lower()])
	return ", ".join(parts) if not parts.is_empty() else "sin vagones"
