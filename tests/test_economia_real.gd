extends Node
## Diagnóstico de la economía real: recorre TODAS las recetas y verifica que el valor producido
## supera los insumos + salarios + mantenimiento + electricidad estimados, con márgenes razonables,
## e imprime tablas de márgenes (por nivel y por cadena completa).
## godot --headless res://tests/test_economia_real.tscn
##
## Estimación por trabajador y día (productividad ≈ 1, salario ≈ base_wage; con título universitario
## el salario sube ×1,4 y la productividad ×1,3 si la profesión es de su rama):
##   ingreso = ppw × precio · insumos = ppw × Σ cantidad × precio · fijo = salario + mantenimiento/empleos
##   + electricidad (power × precio) · margen = (ingreso − insumos − fijo − costo unitario) / ingreso

const RECIPE_MIN := 0.05
const RECIPE_MAX := 0.50
const EXTRACTION_MAX := 0.85
const CAT_RANK := {"materia_prima": 0, "energia": 0, "intermedio": 1, "producto": 2, "servicio": 3}

var failures := 0
var warnings := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: diagnóstico de la economía real ==")
	_test_goods_catalog()
	_test_recipes()
	_test_extraction_and_plants()
	_test_chains()
	_test_levels()
	_test_technologies()
	_test_trade_prices()
	_test_price_order()
	print("  (%d avisos informativos fuera de 10–40 %%)" % warnings)
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- Estimaciones ---------------------------------------------------------------------------------

static func price(g: String) -> float:
	return float(GameData.goods.get(g, {}).get("base_price", 0.0))


static func tech_era(t: String) -> int:
	return int(GameData.technologies.get(t, {}).get("era", 1)) if t != "" else 1


static func is_plant(def: Dictionary) -> bool:
	return EnergySim.is_plant(def)


static func productivity(def: Dictionary, ld: Dictionary) -> float:
	var prof := str(ld.get("required_profession", ""))
	if prof != "" and str(GameData.professions.get("professions", {}).get(prof, {}).get("skill", "")) == str(def.get("skill", "")):
		return 1.3
	return 1.0


## {rev, inputs, fixed, margin, profit, payback_days} por trabajador y día.
static func estimate(def: Dictionary, ld: Dictionary) -> Dictionary:
	var eff := productivity(def, ld)
	var ppw := float(ld.get("prod_per_worker", 1.0)) * eff
	var p := price(str(def.get("product", "")))
	var rev := ppw * p
	var inp := 0.0
	var ins: Dictionary = ld.get("inputs", def.get("inputs", {}))
	for g in ins:
		inp += float(ins[g]) * price(g) * ppw
	var wage := float(def.get("base_wage", 2.0)) * (1.4 if str(ld.get("required_profession", "")) != "" else 1.0)
	var jobs := maxi(1, int(ld.get("jobs", 1)))
	var power := EnergySim.level_power(def, ld) * price("electricidad")
	var fixed := wage + float(ld.get("upkeep", 0.0)) / jobs + power + float(ld.get("unit_cost", 0.0)) * ppw
	var profit := rev - inp - fixed
	var daily := profit * jobs
	return {"rev": rev, "inputs": inp, "fixed": fixed, "margin": profit / rev if rev > 0.0 else 0.0, "profit": profit,
		"payback": float(ld.get("cost", 0.0)) / daily if daily > 0.0 else INF}


static func _pct(v: float) -> String:
	return "%3d%%" % int(round(v * 100.0))


static func _recipe_levels() -> Array:
	var out := []
	for t in GameData.businesses:
		var def: Dictionary = GameData.businesses[t]
		if str(t).begins_with("_") or is_plant(def) or price(str(def.get("product", ""))) <= 0.0:
			continue
		var levels: Array = def.get("levels", [])
		for i in range(levels.size()):
			if not levels[i].get("inputs", def.get("inputs", {})).is_empty():
				out.append([t, i + 1, def, levels[i]])
	return out


# --- Pruebas --------------------------------------------------------------------------------------

func _test_goods_catalog() -> void:
	var bad := []
	var n := 0
	for g in GameData.goods:
		var d: Dictionary = GameData.goods[g]
		if str(g).begins_with("_") or bool(d.get("internal", false)):
			continue
		n += 1
		if not CAT_RANK.has(str(d.get("category", ""))):
			bad.append("%s: categoría" % g)
		if int(d.get("era", 0)) < 1 or int(d.get("era", 0)) > 3:
			bad.append("%s: época" % g)
		if str(d.get("description", "")) == "":
			bad.append("%s: descripción" % g)
		if d.get("model", []).is_empty():
			bad.append("%s: modelo 3D" % g)
		var tech := str(d.get("tech", ""))
		if tech != "" and not GameData.technologies.has(tech):
			bad.append("%s: tecnología %s" % [g, tech])
	check(bad.is_empty(), "catálogo de %d bienes con categoría, época, descripción y modelo 3D %s" % [n, "" if bad.is_empty() else str(bad)])
	check(n >= 55, "catálogo amplio (%d bienes)" % n)
	for g in ["petroleo", "combustible", "electricidad", "carne", "pan", "zapatos", "muebles", "medicamentos", "electrodomesticos", "plasticos", "cobre"]:
		check(GameData.goods.has(g), "existe el bien '%s'" % g)
	check(not bool(GameData.goods["electricidad"].get("storable", true)), "la electricidad no se almacena")


func _test_recipes() -> void:
	print("  -- Márgenes por receta (por trabajador y día, precios base) --")
	print("     %-28s %-3s %-22s %8s %8s %8s %6s %9s" % ["negocio", "niv", "tecnología", "ingreso", "insumos", "fijo", "margen", "recupera"])
	var bad := []
	var no_value := []
	var rank_bad := []
	for row in _recipe_levels():
		var def: Dictionary = row[2]
		var ld: Dictionary = row[3]
		var e := estimate(def, ld)
		var m := float(e["margin"])
		var flag := ""
		if m < 0.10 or m > 0.40:
			flag = " ·"
			warnings += 1
		print("     %-28s %-3d %-22s %8.2f %8.2f %8.2f %6s %8.0fd%s" % [str(row[0]), int(row[1]), str(ld.get("tech", "")).substr(0, 22),
			float(e["rev"]), float(e["inputs"]), float(e["fixed"]), _pct(m), minf(99999.0, float(e["payback"])), flag])
		if m < RECIPE_MIN or m > RECIPE_MAX:
			bad.append("%s/%d %s" % [row[0], row[1], _pct(m)])
		var product := str(def.get("product", ""))
		var ins: Dictionary = ld.get("inputs", {})
		var in_value := 0.0
		for g in ins:
			in_value += float(ins[g]) * price(g)
			var gr := int(CAT_RANK.get(_rank_cat(str(g)), 0))
			if gr > int(CAT_RANK.get(_rank_cat(product), 2)):
				rank_bad.append("%s ← %s" % [product, g])
		if price(product) <= in_value:
			no_value.append("%s/%d" % [row[0], row[1]])
	check(bad.is_empty(), "todas las recetas tienen margen entre %d%% y %d%% %s" % [int(RECIPE_MIN * 100), int(RECIPE_MAX * 100), "" if bad.is_empty() else str(bad)])
	check(no_value.is_empty(), "en todas las recetas el producto vale más que sus insumos %s" % ("" if no_value.is_empty() else str(no_value)))
	check(rank_bad.is_empty(), "materia prima → intermedio → producto (ningún insumo es 'más elaborado' que su producto) %s" % ("" if rank_bad.is_empty() else str(rank_bad)))


## Los bienes marcados como intermedios (herramientas) cuentan como intermedios en la cadena.
static func _rank_cat(g: String) -> String:
	var d: Dictionary = GameData.goods.get(g, {})
	if bool(d.get("intermediate", false)):
		return "intermedio"
	return str(d.get("category", "producto"))


func _test_extraction_and_plants() -> void:
	print("  -- Extracción y centrales --")
	var bad := []
	for t in GameData.businesses:
		var def: Dictionary = GameData.businesses[t]
		if str(t).begins_with("_"):
			continue
		var levels: Array = def.get("levels", [])
		var extraction := bool(def.get("extraction", false)) or (not levels.is_empty() and str(levels[0].get("requires_deposit", "")) != "")
		if not extraction and not is_plant(def):
			continue
		var parts := []
		for i in range(levels.size()):
			var e := estimate(def, levels[i])
			parts.append(_pct(float(e["margin"])))
			if float(e["margin"]) <= 0.0 or float(e["margin"]) > EXTRACTION_MAX:
				bad.append("%s/%d %s" % [t, i + 1, _pct(float(e["margin"]))])
		print("     %-28s %s" % [t, " ".join(parts)])
	check(bad.is_empty(), "extracciones y centrales rentables sin márgenes absurdos (≤ %d%%) %s" % [int(EXTRACTION_MAX * 100), "" if bad.is_empty() else str(bad)])


## Costo total (mano de obra + mantenimiento + insumos no producibles) de 1 unidad producida
## desde las materias primas, usando el nivel `lvl` (1 = básico, 99 = el mejor) de cada etapa.
static func chain_cost(good: String, lvl: int, depth := 0) -> float:
	if depth > 8:
		return price(good)
	var best := {}
	var best_def := {}
	for t in GameData.businesses:
		var def: Dictionary = GameData.businesses[t]
		if str(t).begins_with("_") or str(def.get("product", "")) != good or bool(def.get("shop", false)):
			continue
		var levels: Array = def.get("levels", [])
		if levels.is_empty():
			continue
		var ld: Dictionary = levels[clampi(lvl - 1, 0, levels.size() - 1)]
		if best.is_empty() or float(ld.get("prod_per_worker", 0)) * price(good) > float(best.get("prod_per_worker", 0)) * price(good):
			if best.is_empty() or best_def.get("economia", false) or not def.get("economia", false):
				best = ld
				best_def = def
	if best.is_empty():
		return price(good)   # No se produce: se compra al precio de mercado.
	var ppw := float(best.get("prod_per_worker", 1.0)) * productivity(best_def, best)
	var e := estimate(best_def, best)
	var cost := float(e["fixed"]) / maxf(0.0001, ppw)
	var ins: Dictionary = best.get("inputs", best_def.get("inputs", {}))
	for g in ins:
		cost += float(ins[g]) * chain_cost(str(g), lvl, depth + 1)
	return cost


func _test_chains() -> void:
	print("  -- Cadenas completas (desde la materia prima; margen = (precio − costo total) / precio) --")
	print("     %-26s %9s %10s %8s %10s %8s" % ["producto", "precio", "c. básico", "margen", "c. mejor", "margen"])
	var bad := []
	for g in ["harina", "pan", "carne", "embutidos", "cuero", "zapatos", "tela", "ropa", "ropa_fina", "muebles", "herramientas", "utensilios",
			"velas_jabon", "loza", "vidrio", "remedios", "papel", "periodicos", "acero", "maquinaria", "motor", "conservas", "relojes",
			"quimicos", "combustible", "plasticos", "medicamentos", "componentes_electronicos", "electrodomesticos", "automovil_bien", "avion_bien", "joyas"]:
		var p := price(g)
		var c1 := chain_cost(g, 1)
		var c9 := chain_cost(g, 99)
		var m1 := (p - c1) / p
		var m9 := (p - c9) / p
		print("     %-26s %9.2f %10.2f %8s %10.2f %8s" % [g, p, c1, _pct(m1), c9, _pct(m9)])
		if m1 <= 0.0 or m9 <= 0.0 or m9 > 0.9:
			bad.append("%s %s/%s" % [g, _pct(m1), _pct(m9)])
	check(bad.is_empty(), "todas las cadenas completas son rentables y sin márgenes absurdos %s" % ("" if bad.is_empty() else str(bad)))


## Fábricas y talleres de la economía real y de la industria: 3–4 niveles, cada uno con su
## tecnología, más caros, más lentos de construir, con más empleos, producción y modelo más grande.
func _test_levels() -> void:
	var bad := []
	var count := 0
	for t in GameData.businesses:
		var def: Dictionary = GameData.businesses[t]
		if str(t).begins_with("_") or not (bool(def.get("economia", false)) or bool(def.get("industrial", false))):
			continue
		count += 1
		var levels: Array = def.get("levels", [])
		if levels.size() < 3 or levels.size() > 4:
			bad.append("%s: %d niveles" % [t, levels.size()])
		for i in range(levels.size()):
			var ld: Dictionary = levels[i]
			var tech := str(ld.get("tech", ""))
			if tech != "" and not GameData.technologies.has(tech):
				bad.append("%s/%d: tecnología %s" % [t, i + 1, tech])
			if ld.get("model", []).is_empty() or float(ld.get("cost", 0)) <= 0.0:
				bad.append("%s/%d: modelo/costo" % [t, i + 1])
			if i == 0:
				continue
			var prev: Dictionary = levels[i - 1]
			if tech == "":
				bad.append("%s/%d: sin tecnología" % [t, i + 1])
			if tech_era(tech) < tech_era(str(prev.get("tech", ""))):
				bad.append("%s/%d: tecnología de una época anterior" % [t, i + 1])
			if float(ld["cost"]) <= float(prev["cost"]) or int(ld["jobs"]) <= int(prev["jobs"]) or float(ld["prod_per_worker"]) <= float(prev["prod_per_worker"]):
				bad.append("%s/%d: costo/empleos/producción no suben" % [t, i + 1])
			if float(ld["build_days"]) < float(prev["build_days"]) * 1.5:
				bad.append("%s/%d: build_days ×%.2f" % [t, i + 1, float(ld["build_days"]) / float(prev["build_days"])])
			if _width(ld.get("model", [])) <= _width(prev.get("model", [])):
				bad.append("%s/%d: el modelo no crece" % [t, i + 1])
	check(count >= 50 and bad.is_empty(), "%d fábricas/talleres/tiendas/centrales con 3–4 niveles crecientes %s" % [count, "" if bad.is_empty() else str(bad)])


static func _width(parts: Array) -> float:
	var w := 0.0
	for p in parts:
		var s: Array = p.get("size", [1, 1, 1])
		var pos: Array = p.get("pos", [0, 0, 0])
		var sx := float(s[0])
		var sz := float(s[2])
		if str(p.get("s", "")) == "cyl":
			sx = maxf(float(s[0]), float(s[2])) * 2.0
			sz = sx
		w = maxf(w, maxf(absf(float(pos[0])) * 2.0 + sx, absf(float(pos[2])) * 2.0 + sz))
	return w


func _test_technologies() -> void:
	var data: Dictionary = GameData.extra("technologies_economia")
	var branches: Array = GameData.eras.get("branches", []).map(func(b): return str(b[0]))
	var bad := []
	for id in data:
		if str(id).begins_with("_"):
			continue
		var t: Dictionary = GameData.technologies.get(id, {})
		if t.is_empty() or not branches.has(str(t.get("branch", ""))):
			bad.append("%s: rama" % id)
		for r in t.get("requires", []):
			if not GameData.technologies.has(r) or tech_era(r) > int(t.get("era", 1)):
				bad.append("%s: requisito %s" % [id, r])
	check(bad.is_empty() and data.size() >= 15, "%d tecnologías nuevas encajan en épocas y ramas con prerrequisitos existentes %s" % [data.size() - 1, "" if bad.is_empty() else str(bad)])
	check(tech_era("petroleo") >= 2 and tech_era("energia_solar") == 3 and tech_era("energia_nuclear") == 3, "petróleo desde la industrial tardía; renovables y nuclear en la época moderna")


func _test_trade_prices() -> void:
	var tg: Dictionary = GameData.extra("trade").get("goods", {})
	var bad := []
	for g in tg:
		if str(g).begins_with("_"):
			continue
		var ratio := float(tg[g].get("base", 0.0)) / maxf(0.0001, price(g))
		if ratio < 0.9 or ratio > 1.6:
			bad.append("%s ×%.2f" % [g, ratio])
	check(bad.is_empty(), "precios de otros pueblos coherentes con el mercado local (0,9–1,6 ×) %s" % ("" if bad.is_empty() else str(bad)))
	var wages := []
	for t in GameData.businesses:
		var w := float(GameData.businesses[t].get("base_wage", 2.0)) if not str(t).begins_with("_") else 2.0
		if w < 1.7 or w > 3.8:
			wages.append("%s %.2f" % [t, w])
	check(wages.is_empty(), "salarios base entre 1,7 y 3,8 por día %s" % ("" if wages.is_empty() else str(wages)))


func _test_price_order() -> void:
	var by_cat := {}
	for g in GameData.goods:
		var d: Dictionary = GameData.goods[g]
		if str(g).begins_with("_") or bool(d.get("internal", false)):
			continue
		var cat := str(d.get("category", ""))
		if not by_cat.has(cat):
			by_cat[cat] = []
		by_cat[cat].append(price(g))
	var med := {}
	for c in by_cat:
		var arr: Array = by_cat[c]
		arr.sort()
		med[c] = float(arr[arr.size() / 2])
	print("  -- Precio mediano por categoría: %s" % str(med))
	check(float(med.get("materia_prima", 0)) < float(med.get("intermedio", 0)) and float(med.get("intermedio", 0)) < float(med.get("producto", 0)),
			"precio mediano: materia prima < intermedio < producto")
	check(price("avion_bien") > price("automovil_bien") and price("automovil_bien") > price("electrodomesticos") and price("electrodomesticos") > price("ropa"),
			"escalera de precios: avión > auto > electrodomésticos > ropa")
	check(price("carbon") < price("acero") and price("acero") < price("herramientas") * 2.0 and price("petroleo") < price("combustible") and price("combustible") < price("plasticos") * 1.5,
			"derivados más caros que su materia prima")
