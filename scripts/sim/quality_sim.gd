class_name QualitySim
extends RefCounted
## Economía global — calidad de producto y reputación de marca (ver docs/ECONOMIA_GLOBAL.md).
##
## Calidad (0,4–1,8; 1 = normal) = media geométrica ponderada de cinco factores:
##   Q = L^0,30 × T^0,20 × M^0,15 × S^0,25 × I^0,10
##   L  nivel del edificio      = (0,85 + 0,15 × (nivel − 1)) × calidad del nivel (datos)
##   T  tecnología              = 0,85 + 0,10 × (época − 1) + 0,6 × (bono de producción del bien − 1)
##   M  maquinaria y mejoras    = (1 + 0,10 × mejoras de calidad compradas) × 1,10 si el nivel usa maquinaria o
##                                electricidad (× cobertura eléctrica)
##   S  personal                = productividad media de los empleados (habilidad, experiencia, estudios, salud)
##   I  insumos                 = calidad media de lo que produces de cada insumo de la receta (1 si se compra fuera)
## Marca (0–100, empieza en 50), una por empresa (edificio productor, tuyo o NPC). Cada mes:
##   marca += 6 × (Q − 1) + 0,3 si vendió (−0,5 si no vendió) − 5 por cada incumplimiento de contrato del bien
##   y se acerca un 3 % a 50 (hay que sostener la calidad).
## Precio aceptado: los clientes toleran hasta × accept_mult = 1 + 0,3 × (Q − 1) + 0,2 × (marca − 50) / 50
##   (entre 0,85 y 1,3). Gancho en MarketSim.purchase y ShopSim._buy.
## Estado: gs.world_econ["brand"] = {id: {q, rep, am, upg, parts}}, ["q_by_good"], ["breach_seen"].

const NON_GOODS := ["", "construccion", "credito", "servicio", "investigacion", "educacion", "transporte", "entrada", "alojamiento", "publicidad", "comercio"]


static func cfg() -> Dictionary:
	return GlobalEconSim.cfg().get("quality", {})


static func init_state(gs) -> void:
	var w: Dictionary = gs.world_econ
	for k in ["brand", "q_by_good", "breach_seen"]:
		if not w.has(k) or not (w[k] is Dictionary):
			w[k] = {}


static func _entry(gs, b: Dictionary) -> Dictionary:
	var br: Dictionary = gs.world_econ.get("brand", {})
	var key := str(int(b.get("id", -1)))
	if not br.has(key):
		br[key] = {"q": 1.0, "rep": float(cfg().get("brand", {}).get("start", 50.0)), "am": 1.0, "upg": 0, "parts": {}}
		gs.world_econ["brand"] = br
	return br[key]


## Negocios que fabrican o venden algo con marca: tuyos o de empresarios NPC.
static func is_producer(gs, b: Dictionary) -> bool:
	if not (gs.owned_by_player(b) or NpcBusinessSim.is_npc(b)):
		return false
	var def: Dictionary = gs.building_def(b)
	if str(def.get("category", "")) != "negocio":
		return false
	return not (str(def.get("product", "")) in NON_GOODS) or bool(def.get("shop", false))


static func _mechanized(def: Dictionary, ld: Dictionary) -> bool:
	var ins: Dictionary = ld.get("inputs", def.get("inputs", {}))
	for g in ["maquinaria", "motor", "herramientas"]:
		if ins.has(g):
			return true
	return EnergySim.level_power(def, ld) > 0.0 or bool(ld.get("requires_power", false))


## Factores de la calidad de un negocio: {level, tech, machines, staff, inputs, q}.
static func components(gs, b: Dictionary) -> Dictionary:
	var def: Dictionary = gs.building_def(b)
	var ld: Dictionary = gs.level_def(b)
	var product := str(def.get("product", ""))
	var lvl := int(b.get("level", 1))
	var L := clampf((0.85 + 0.15 * float(lvl - 1)) * float(ld.get("quality", 1.0)), 0.5, 2.0)
	var T := clampf(0.85 + 0.1 * float(gs.era() - 1) + 0.6 * (TechSim.mult(gs, "production", product) - 1.0), 0.7, 1.5)
	var upg := int(_entry(gs, b).get("upg", 0)) if gs.world_econ is Dictionary and gs.world_econ.has("brand") else 0
	var M := 1.0 + float(cfg().get("upgrade_step", 0.1)) * float(upg)
	if _mechanized(def, ld):
		M *= 1.1 * (0.85 + 0.15 * clampf(EnergySim.factor(gs, b), 0.0, 1.0))
	var skill := str(def.get("skill", ""))
	var total := 0.0
	var n := 0
	for c in gs.employees_of(int(b["id"])):
		if c.job_kind == "empleo" or c.job_kind == "dueño":
			total += BusinessSim.productivity(c, skill)
			n += 1
	var S := clampf(total / float(n), 0.5, 1.5) if n > 0 else 0.8
	var ins: Dictionary = ld.get("inputs", def.get("inputs", {}))
	var I := 1.0
	if not ins.is_empty():
		var qg: Dictionary = gs.world_econ.get("q_by_good", {}) if gs.world_econ is Dictionary else {}
		var s := 0.0
		for g in ins:
			s += float(qg.get(str(g), 1.0)) if gs.owned_by_player(b) else 1.0
		I = clampf(s / float(ins.size()), 0.5, 1.6)
	var w: Dictionary = cfg().get("weights", {})
	var lq := float(w.get("level", 0.3)) * log(L) + float(w.get("tech", 0.2)) * log(T) + float(w.get("machines", 0.15)) * log(M) \
		+ float(w.get("staff", 0.25)) * log(S) + float(w.get("inputs", 0.1)) * log(I)
	var q := clampf(exp(lq), 0.4, 1.8)
	return {"level": L, "tech": T, "machines": M, "staff": S, "inputs": I, "q": q}


## Calidad actual (calculada al cierre de mes; si aún no hay, se calcula ahora).
static func quality(gs, b: Dictionary) -> float:
	if not GlobalEconSim.ready(gs):
		return 1.0
	var br: Dictionary = gs.world_econ.get("brand", {})
	var e: Dictionary = br.get(str(int(b.get("id", -1))), {})
	if e.has("parts") and not (e["parts"] as Dictionary).is_empty():
		return float(e.get("q", 1.0))
	return float(components(gs, b)["q"])


static func brand(gs, b: Dictionary) -> float:
	if not GlobalEconSim.ready(gs):
		return 50.0
	var e: Dictionary = gs.world_econ.get("brand", {}).get(str(int(b.get("id", -1))), {})
	return float(e.get("rep", cfg().get("brand", {}).get("start", 50.0)))


static func compute_accept(q: float, rep: float) -> float:
	var ac: Dictionary = cfg().get("accept", {})
	return clampf(1.0 + float(ac.get("quality_weight", 0.3)) * (q - 1.0) + float(ac.get("brand_weight", 0.2)) * (rep - 50.0) / 50.0,
		float(ac.get("min", 0.85)), float(ac.get("max", 1.3)))


## Cuánto más (o menos) aceptan pagar los clientes a este negocio por su calidad y marca (1 = igual).
## Rápido: usa el valor guardado al cierre de mes (se llama en cada compra).
static func accept_mult(gs, b: Dictionary) -> float:
	var w = gs.world_econ
	if not (w is Dictionary) or not w.has("brand"):
		return 1.0
	var e = w["brand"].get(str(int(b.get("id", -1))))
	if e == null:
		return 1.0
	return float(e.get("am", 1.0))


## Recalcula la calidad y la marca de un negocio (y su precio aceptado).
static func refresh(gs, b: Dictionary) -> Dictionary:
	var e := _entry(gs, b)
	var parts := components(gs, b)
	e["q"] = float(parts["q"])
	e["parts"] = parts
	e["am"] = compute_accept(float(e["q"]), float(e.get("rep", 50.0)))
	return e


# --- Mejoras de calidad (control de calidad, maquinaria fina) ------------------------------------------

static func upgrade_cost(gs, b: Dictionary) -> float:
	return float(gs.level_def(b).get("cost", 300)) * gs.price_mult() * float(cfg().get("upgrade_cost_ratio", 0.2)) * (1.0 + 0.5 * float(int(_entry(gs, b).get("upg", 0))))


static func upgrade_block_reason(gs, b: Dictionary) -> String:
	if not gs.owned_by_player(b) or not is_producer(gs, b):
		return "Solo en tus negocios que producen o venden."
	if int(_entry(gs, b).get("upg", 0)) >= int(cfg().get("max_upgrades", 3)):
		return "Ya tiene todas las mejoras de calidad."
	var cost := upgrade_cost(gs, b)
	if gs.money < cost:
		return "Necesitas %s." % Fmt.money(cost)
	return ""


## Compra una mejora de calidad (maquinaria fina y control de calidad). El dinero va a proveedores
## del pueblo (artesanos desempleados) si los hay; si no, sale del pueblo como una importación.
static func buy_upgrade(gs, b: Dictionary) -> String:
	var why := upgrade_block_reason(gs, b)
	if why != "":
		return why
	var cost := upgrade_cost(gs, b)
	gs.add_money(-cost)
	BusinessSim.ledger_add(b, "obras", cost)
	GlobalEconSim.pay_local(gs, cost)
	var e := _entry(gs, b)
	e["upg"] = int(e.get("upg", 0)) + 1
	refresh(gs, b)
	gs.notify("Mejoraste la calidad de %s (maquinaria fina y control de calidad): calidad %.2f." % [gs.building_label(b), float(e["q"])], "negocio")
	return ""


# --- Cierre mensual --------------------------------------------------------------------------------------

static func monthly(gs) -> void:
	init_state(gs)
	var bc: Dictionary = cfg().get("brand", {})
	var breaches := _breaches_by_good(gs)
	var sums := {}
	var alive := {}
	for b in gs.buildings:
		if not is_producer(gs, b) or str(b.get("status", "")) == "construccion":
			continue
		alive[str(int(b["id"]))] = true
		var e := _entry(gs, b)
		var parts := components(gs, b)
		var q := float(parts["q"])
		e["q"] = q
		e["parts"] = parts
		var rep := float(e.get("rep", 50.0))
		var sold := BusinessSim.period_value(b, "last_month", "ventas") > 0.0
		rep += float(bc.get("quality_weight", 6.0)) * (q - 1.0)
		rep += float(bc.get("sales_bonus", 0.3)) if sold else float(bc.get("no_sales", -0.5))
		var product := str(gs.building_def(b).get("product", ""))
		if gs.owned_by_player(b):
			rep += float(bc.get("breach", -5.0)) * float(breaches.get(product, 0))
			var sm: Array = sums.get(product, [0.0, 0])
			sums[product] = [float(sm[0]) + q, int(sm[1]) + 1]
		rep += (50.0 - rep) * float(bc.get("drift", 0.03))
		e["rep"] = clampf(rep, 0.0, 100.0)
		e["am"] = compute_accept(q, float(e["rep"]))
	var qg := {}
	for g in sums:
		qg[g] = float(sums[g][0]) / maxf(1.0, float(sums[g][1]))
	gs.world_econ["q_by_good"] = qg
	var br: Dictionary = gs.world_econ["brand"]
	for k in br.keys():
		if not alive.has(k) and gs.get_building(int(k)).is_empty():
			br.erase(k)


## Incumplimientos NUEVOS del jugador en contratos, por bien (desde el último cierre).
static func _breaches_by_good(gs) -> Dictionary:
	var out := {}
	var seen: Dictionary = gs.world_econ.get("breach_seen", {})
	var now := {}
	for k in gs.market.get("contracts", []):
		if not (k is Dictionary) or not k.has("id"):
			continue
		var key := str(k["id"])
		var failed := int(k.get("failed", 0))
		now[key] = failed
		var delta := failed - int(seen.get(key, 0))
		if delta > 0:
			var g := str(k.get("good", ""))
			out[g] = int(out.get(g, 0)) + delta
	gs.world_econ["breach_seen"] = now
	return out


# --- Interfaz --------------------------------------------------------------------------------------------

static func quality_label(q: float) -> String:
	if q >= 1.3:
		return "excelente"
	if q >= 1.1:
		return "buena"
	if q >= 0.9:
		return "normal"
	if q >= 0.7:
		return "regular"
	return "mala"


static func brand_label(rep: float) -> String:
	if rep >= 80.0:
		return "marca prestigiosa"
	if rep >= 60.0:
		return "marca conocida"
	if rep >= 40.0:
		return "marca corriente"
	return "marca desprestigiada"


static func panel_lines(gs, b: Dictionary) -> String:
	if not is_producer(gs, b):
		return ""
	var e := _entry(gs, b)
	var p: Dictionary = e.get("parts", {})
	if p.is_empty():
		p = components(gs, b)
	var q := float(p["q"])
	var rep := float(e.get("rep", 50.0))
	var am := compute_accept(q, rep)
	var s := "Calidad: [b]%.2f[/b] (%s) · Marca: %d/100 (%s) · Precio aceptado ×%.2f\n" % [q, quality_label(q), int(rep), brand_label(rep), am]
	s += "[color=#aaa]Calidad = nivel %.2f^0,30 × tecnología %.2f^0,20 × maquinaria/mejoras %.2f^0,15 × personal %.2f^0,25 × insumos %.2f^0,10[/color]\n" % [
		float(p["level"]), float(p["tech"]), float(p["machines"]), float(p["staff"]), float(p["inputs"])]
	return s
