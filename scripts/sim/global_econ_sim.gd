class_name GlobalEconSim
extends RefCounted
## Economía global (sección A de docs/PENDIENTES.md; ver docs/ECONOMIA_GLOBAL.md).
## Orquesta los sistemas nuevos y guarda su estado en GameState.world_econ:
##   - Ciclos económicos por país (auge, normal, recesión, crisis: pánico bancario o burbuja
##     inmobiliaria) con señales previas (indicadores) y efectos moderados y graduales.
##   - Moneda e inflación por país (data/countries.json: currency, base_inflation,
##     exchange_rate_to_ref). El tipo de cambio fluctúa y encarece o abarata el comercio exterior.
##   - StockSim (bolsa mundial), InsuranceSim (seguros) y QualitySim (calidad y marca).
## Generador aleatorio propio y guardado (no altera la secuencia de gs.rng).
## Parámetros en data/economia_global.json.


static func cfg() -> Dictionary:
	return GameData.extra("economia_global")


static func cycle_cfg() -> Dictionary:
	return cfg().get("cycles", {})


static func fx_cfg() -> Dictionary:
	return cfg().get("currency", {})


static func phase_def(phase: String) -> Dictionary:
	return cycle_cfg().get("phases", {}).get(phase, {})


static func phase_label(phase: String) -> String:
	return str(phase_def(phase).get("label", phase))


static func kind_label(kind: String) -> String:
	return str(cycle_cfg().get("crisis_kinds", {}).get(kind, {}).get("label", kind))


# --- Estado ------------------------------------------------------------------------------------

static func init_state(gs) -> void:
	var w: Dictionary = gs.world_econ
	if not w.has("rng_state"):
		var r := RandomNumberGenerator.new()
		r.seed = int(gs.settings.get("seed", 0)) * 4099 + 777
		w["rng_state"] = str(r.state)
	if not w.has("countries") or not (w["countries"] is Dictionary):
		w["countries"] = {}
	if not w.has("p_ref"):
		w["p_ref"] = 1.0
	if not w.has("home_p0"):
		w["home_p0"] = maxf(0.01, float(gs.price_level()))
	if not w.has("credit_hist"):
		w["credit_hist"] = []
	gs.world_econ = w
	_ensure_countries(gs)
	StockSim.init_state(gs)
	InsuranceSim.init_state(gs)
	QualitySim.init_state(gs)


static func ready(gs) -> bool:
	return gs.world_econ is Dictionary and gs.world_econ.has("countries")


## Países del archivo de países (si el mapa cambia la lista, se agregan los nuevos).
static func country_defs() -> Dictionary:
	if WorldData.is_real(MapSim.country_id(GameState)):
		return WorldData.real_defs()   # Mapa mundial: países reales (moneda, inflación y cambio reales).
	return GameData.extra("countries").get("countries", {})


static func country_ids() -> Array:
	var all := country_defs()
	var ids := all.keys().filter(func(k): return not str(k).begins_with("_"))
	ids.sort_custom(func(a, b): return int(all[a].get("order", 0)) < int(all[b].get("order", 0)) if int(all[a].get("order", 0)) != int(all[b].get("order", 0)) else str(a) < str(b))
	return ids


static func home_id(gs) -> String:
	return MapSim.country_id(gs)


static func _ensure_countries(gs) -> void:
	var cs: Dictionary = gs.world_econ["countries"]
	var home := home_id(gs)
	for id in country_ids():
		if cs.has(id):
			continue
		var d: Dictionary = country_defs()[id]
		var rate0 := maxf(0.0001, float(d.get("exchange_rate_to_ref", 1.0)))
		var months: Array = phase_def("normal").get("months", [12, 30])
		var dur := ri(gs, int(months[0]), int(months[1]))
		var mip := ri(gs, 0, dur - 1)
		if id == home:
			mip = 0
			dur = maxi(dur, int(cycle_cfg().get("min_first_change_months", 8)))
		cs[id] = {"phase": "normal", "kind": "", "months_in_phase": mip, "duration": dur, "next_phase": "", "next_kind": "",
			"lead_left": 0, "rate0": rate0, "rate": rate0, "plevel": 1.0, "infl": float(d.get("base_inflation", 0.03)),
			"real": 1.0, "eff": _targets("normal", ""), "ind": {"confianza": 55.0, "credito": 6.0, "vivienda": 2.0, "bolsa": 100.0},
			"hist": [], "warned": ""}
	gs.world_econ["countries"] = cs


static func country(gs, id: String) -> Dictionary:
	if not ready(gs):
		return {}
	return gs.world_econ["countries"].get(id, {})


static func home(gs) -> Dictionary:
	return country(gs, home_id(gs))


# --- Aleatoriedad propia ----------------------------------------------------------------------------

static func _r(gs) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.state = int(str(gs.world_econ.get("rng_state", "1")))
	return r


static func _save_r(gs, r: RandomNumberGenerator) -> void:
	gs.world_econ["rng_state"] = str(r.state)


static func rf(gs) -> float:
	var r := _r(gs)
	var v := r.randf()
	_save_r(gs, r)
	return v


static func rn(gs, sigma: float) -> float:
	var r := _r(gs)
	var v := r.randfn(0.0, sigma)
	_save_r(gs, r)
	return v


static func ri(gs, a: int, b: int) -> int:
	if b <= a:
		return a
	return mini(b, a + int(floorf(rf(gs) * float(b - a + 1))))


# --- Ciclo diario / mensual -------------------------------------------------------------------------

static func daily(gs) -> void:
	if not ready(gs):
		return
	InsuranceSim.daily(gs)


static func monthly(gs) -> void:
	if not ready(gs):
		init_state(gs)
	_ensure_countries(gs)
	_credit_heat(gs)
	var w: Dictionary = gs.world_econ
	w["p_ref"] = float(w.get("p_ref", 1.0)) * (1.0 + float(fx_cfg().get("world_inflation", 0.03)) / 12.0)
	var home := home_id(gs)
	for id in country_ids():
		var st: Dictionary = w["countries"][id]
		_cycle_step(gs, str(id), st, str(id) == home)
		_currency_step(gs, str(id), st, str(id) == home)
	QualitySim.monthly(gs)
	StockSim.monthly(gs)
	InsuranceSim.monthly(gs)


## Llamado desde GovSim.monthly: el gobierno estudia la ley de la bolsa de valores.
static func gov_monthly(gs) -> void:
	if not ready(gs):
		return
	StockSim.review_law(gs)


# --- Ciclos económicos --------------------------------------------------------------------------------

## Valores objetivo de los efectos para una fase (y tipo de crisis).
static func _targets(phase: String, kind: String) -> Dictionary:
	var p := phase_def(phase)
	var t := {"demand": float(p.get("demand", 1.0)), "credit_rate": float(p.get("credit_rate", 0.0)),
		"credit_limit": float(p.get("credit_limit", 1.0)), "property": float(p.get("property", 1.0)),
		"stock": float(p.get("stock", 1.0)), "pe": float(p.get("pe", 10.0)), "fx": float(p.get("fx", 0.0)),
		"growth": float(p.get("growth", 0.02))}
	var kd: Dictionary = cycle_cfg().get("crisis_kinds", {}).get(kind, {})
	if phase == "crisis" and not kd.is_empty():
		t["credit_limit"] = float(t["credit_limit"]) * float(kd.get("credit_limit_mult", 1.0))
		t["credit_rate"] = float(t["credit_rate"]) + float(kd.get("credit_rate_add", 0.0))
		t["property"] = float(t["property"]) * float(kd.get("property_mult", 1.0))
	return t


## Crecimiento anual del crédito del país del jugador (préstamos reales de la partida).
static func _credit_heat(gs) -> void:
	var h: Array = gs.world_econ.get("credit_hist", [])
	h.append(EconomySim.total_credit(gs))
	while h.size() > 13:
		h.pop_front()
	gs.world_econ["credit_hist"] = h


static func home_credit_growth(gs) -> float:
	var h: Array = gs.world_econ.get("credit_hist", [])
	if h.size() < 2:
		return 0.0
	var old := float(h[0])
	var now := float(h[h.size() - 1])
	var base := maxf(old, 0.02 * EconomySim.total_money(gs))
	if base <= 1.0:
		return 0.0
	return clampf((now - old) / base * 12.0 / float(h.size() - 1), -0.5, 1.0)


static func _pick_next(gs, phase: String, is_home: bool) -> String:
	var tr: Dictionary = cycle_cfg().get("transitions", {}).get(phase, {"normal": 1.0}).duplicate()
	if is_home and tr.has("crisis"):
		# Crédito recalentado en tu país: más probable un pánico bancario.
		var heat := home_credit_growth(gs) - float(cycle_cfg().get("home_credit_heat_limit", 0.25))
		if heat > 0.0:
			tr["crisis"] = float(tr["crisis"]) * (1.0 + minf(2.0, heat * 4.0))
	var total := 0.0
	for k in tr:
		total += float(tr[k])
	var x := rf(gs) * total
	for k in tr:
		x -= float(tr[k])
		if x <= 0.0:
			return str(k)
	return "normal"


static func _cycle_step(gs, id: String, st: Dictionary, is_home: bool) -> void:
	var cc := cycle_cfg()
	st["months_in_phase"] = int(st.get("months_in_phase", 0)) + 1
	if str(st.get("next_phase", "")) == "":
		if int(st["months_in_phase"]) >= int(st.get("duration", 12)):
			var nxt := _pick_next(gs, str(st["phase"]), is_home)
			var kind := ""
			if nxt == "crisis":
				var home_heat := is_home and home_credit_growth(gs) > float(cc.get("home_credit_heat_limit", 0.25))
				kind = "panico_bancario" if home_heat or rf(gs) < 0.5 else "burbuja_inmobiliaria"
			st["next_phase"] = nxt
			st["next_kind"] = kind
			var lead: Array = cc.get("lead_months", [3, 5])
			st["lead_left"] = ri(gs, int(lead[0]), int(lead[1]))
	else:
		st["lead_left"] = int(st.get("lead_left", 0)) - 1
		if int(st["lead_left"]) <= 0:
			var old := str(st["phase"])
			st["phase"] = str(st["next_phase"])
			st["kind"] = str(st.get("next_kind", ""))
			st["next_phase"] = ""
			st["next_kind"] = ""
			st["months_in_phase"] = 0
			var months: Array = phase_def(str(st["phase"])).get("months", [6, 12])
			st["duration"] = ri(gs, int(months[0]), int(months[1]))
			if is_home and old != str(st["phase"]):
				gs.notify(_phase_news(gs, id, st), "importante")
	_indicators(gs, id, st, is_home)
	# Efectos graduales (moderados): se acercan a los de la fase y, antes de una crisis, a sus señales.
	var tgt := _targets(str(st["phase"]), str(st.get("kind", "")))
	var nk := str(st.get("next_kind", ""))
	if str(st.get("next_phase", "")) == "crisis" and nk == "burbuja_inmobiliaria":
		tgt["property"] = float(cc.get("crisis_kinds", {}).get(nk, {}).get("bubble_peak", 1.12))
	elif str(st.get("next_phase", "")) == "crisis" and nk == "panico_bancario":
		tgt["credit_limit"] = maxf(float(tgt["credit_limit"]), 1.1)
	var s := float(cc.get("smoothing", 0.35))
	var eff: Dictionary = st.get("eff", {})
	for k in tgt:
		eff[k] = float(eff.get(k, tgt[k])) + (float(tgt[k]) - float(eff.get(k, tgt[k]))) * s
	st["eff"] = eff


const IND_TARGETS := {
	"auge": {"confianza": 72.0, "credito": 12.0, "vivienda": 6.0},
	"normal": {"confianza": 55.0, "credito": 6.0, "vivienda": 2.0},
	"recesion": {"confianza": 35.0, "credito": 1.0, "vivienda": -3.0},
	"crisis": {"confianza": 20.0, "credito": -5.0, "vivienda": -8.0},
}


## Indicadores adelantados: se mueven hacia la fase que viene ANTES de que llegue (señales previas).
static func _indicators(gs, id: String, st: Dictionary, is_home: bool) -> void:
	var ind: Dictionary = st.get("ind", {})
	var toward := str(st["phase"])
	var nxt := str(st.get("next_phase", ""))
	if nxt != "":
		toward = nxt
	var tg: Dictionary = IND_TARGETS.get(toward, IND_TARGETS["normal"]).duplicate()
	var nk := str(st.get("next_kind", ""))
	if nxt == "crisis":
		# Antes de la crisis, la señal propia: crédito disparado (pánico) o vivienda disparada (burbuja).
		if nk == "panico_bancario":
			tg["credito"] = 22.0
			tg["confianza"] = 48.0
		elif nk == "burbuja_inmobiliaria":
			tg["vivienda"] = 15.0
			tg["confianza"] = 50.0
	if str(st["phase"]) == "crisis" and str(st.get("kind", "")) == "burbuja_inmobiliaria":
		tg["vivienda"] = -12.0
	for k in ["confianza", "credito", "vivienda"]:
		var v := float(ind.get(k, tg[k]))
		ind[k] = v + (float(tg[k]) - v) * 0.4 + rn(gs, 1.5 if k == "confianza" else 0.8)
	if is_home:
		# En tu país el crédito medido pesa: préstamos reales de la partida.
		ind["credito"] = float(ind["credito"]) * 0.7 + home_credit_growth(gs) * 100.0 * 0.3
		ind["desempleo"] = EconomySim.unemployment(gs) * 100.0
	ind["confianza"] = clampf(float(ind["confianza"]), 0.0, 100.0)
	var target := 100.0 * float(st.get("eff", {}).get("stock", 1.0)) * float(st.get("plevel", 1.0))
	var bolsa := float(ind.get("bolsa", 100.0))
	ind["bolsa"] = maxf(10.0, bolsa + (target - bolsa) * 0.3 + bolsa * rn(gs, 0.02))
	st["ind"] = ind
	if is_home:
		var sig := signals(gs, id)
		var first := str(sig[0]) if not sig.is_empty() else ""
		if first != "" and first != str(st.get("warned", "")) and str(st["phase"]) != "crisis":
			gs.notify("Indicadores económicos: " + first, "importante")
		st["warned"] = first


static func _phase_news(gs, id: String, st: Dictionary) -> String:
	var name := country_label(id)
	match str(st["phase"]):
		"auge":
			return "%s entra en AUGE: la gente gasta más, el crédito se abarata y la bolsa sube." % name
		"recesion":
			return "%s entra en RECESIÓN: cae el consumo, el crédito se encarece y bajan las propiedades y la bolsa." % name
		"crisis":
			return "CRISIS en %s (%s): crédito escaso y caro, propiedades y bolsa a la baja, la moneda se deprecia." % [name, kind_label(str(st.get("kind", ""))).to_lower()]
	return "La economía de %s vuelve a la normalidad." % name


## Señales previas visibles (lo que dicen los indicadores), de la más grave a la más leve.
static func signals(gs, id: String) -> Array:
	var st := country(gs, id)
	if st.is_empty():
		return []
	var ind: Dictionary = st.get("ind", {})
	var out := []
	var phase := str(st["phase"])
	if float(ind.get("credito", 0.0)) > 15.0:
		out.append("el crédito crece muy rápido (+%d %%/año): riesgo de pánico bancario." % int(round(float(ind["credito"]))))
	if float(ind.get("vivienda", 0.0)) > 9.0:
		out.append("los precios de la vivienda suben %d %%/año: posible burbuja inmobiliaria." % int(round(float(ind["vivienda"]))))
	if float(ind.get("confianza", 50.0)) < 42.0 and phase in ["normal", "auge"]:
		out.append("la confianza empresarial cae (%d/100): se acerca una recesión." % int(float(ind["confianza"])))
	if float(ind.get("confianza", 50.0)) > 63.0 and phase in ["normal", "recesion", "crisis"]:
		out.append("la confianza se recupera (%d/100): se acerca %s." % [int(float(ind["confianza"])), "un auge" if phase == "normal" else "la recuperación"])
	return out


## Riesgo de crisis o recesión (0–100) según los indicadores (para la barra del ciclo).
static func risk(gs, id: String) -> float:
	var st := country(gs, id)
	if st.is_empty():
		return 0.0
	var ind: Dictionary = st.get("ind", {})
	var r := 0.0
	r += clampf((55.0 - float(ind.get("confianza", 55.0))) * 1.6, 0.0, 50.0)
	r += clampf((float(ind.get("credito", 6.0)) - 8.0) * 2.5, 0.0, 35.0)
	r += clampf((float(ind.get("vivienda", 2.0)) - 4.0) * 3.0, 0.0, 35.0)
	return clampf(r, 0.0, 100.0)


## Fuerza una fase (pruebas y escenarios). Aplica los efectos de inmediato.
static func force_phase(gs, id: String, phase: String, kind := "") -> void:
	var st := country(gs, id)
	if st.is_empty():
		return
	st["phase"] = phase
	st["kind"] = kind
	st["next_phase"] = ""
	st["next_kind"] = ""
	st["months_in_phase"] = 0
	var months: Array = phase_def(phase).get("months", [6, 12])
	st["duration"] = int(months[1])
	st["eff"] = _targets(phase, kind)


static func eff(gs, key: String, fallback := 1.0, id := "") -> float:
	var st := country(gs, home_id(gs) if id == "" else id)
	if st.is_empty():
		return fallback
	return float(st.get("eff", {}).get(key, fallback))


# --- Efectos (ganchos en otros sistemas) ------------------------------------------------------------

## Gasto discrecional de los vecinos (MarketSim.discretionary).
static func demand_mult(gs) -> float:
	return eff(gs, "demand", 1.0)


## Puntos de tasa de interés que se suman a los préstamos (LoanContract.era_rate_add).
static func credit_rate_add(gs) -> float:
	return eff(gs, "credit_rate", 0.0)


## Cupo de crédito del banco externo (BankSim.credit_limit).
static func credit_limit_mult(gs) -> float:
	return eff(gs, "credit_limit", 1.0)


## Precio de las propiedades (EconomySim.property_value y RealEstateSim.value_total).
static func property_mult(gs) -> float:
	return eff(gs, "property", 1.0)


# --- Monedas ------------------------------------------------------------------------------------------

static func country_label(id: String) -> String:
	return str(country_defs().get(id, {}).get("label", id))


static func currency_name(id: String) -> String:
	return str(country_defs().get(id, {}).get("currency", {}).get("name", "moneda"))


static func currency_symbol(id: String) -> String:
	return str(country_defs().get(id, {}).get("currency", {}).get("symbol", "$"))


## Unidades de la moneda del país por 1 unidad de referencia.
static func rate(gs, id: String) -> float:
	var st := country(gs, id)
	if st.is_empty():
		return maxf(0.0001, float(country_defs().get(id, {}).get("exchange_rate_to_ref", 1.0)))
	return maxf(0.0001, float(st.get("rate", 1.0)))


## Factor para convertir montos: amount_en_to = amount_en_from × fx(from, to).
static func fx(gs, from_id: String, to_id: String) -> float:
	return rate(gs, to_id) / rate(gs, from_id)


static func to_home(gs, amount: float, from_id: String) -> float:
	return amount * fx(gs, from_id, home_id(gs))


## "12,50 S/A (≈ $15)": un monto en moneda extranjera con su equivalente en tu moneda.
static func fmt_foreign(gs, amount: float, id: String) -> String:
	if id == home_id(gs):
		return Fmt.money2(amount)
	return "%s %s (≈ %s)" % [_num(amount), currency_symbol(id), Fmt.money2(to_home(gs, amount, id))]


static func _num(v: float) -> String:
	return ("%.2f" % v).replace(".", ",")


## Desvío real de la moneda del país (1 = paridad; > 1 = moneda débil / depreciada).
static func real_index(gs, id := "") -> float:
	var st := country(gs, home_id(gs) if id == "" else id)
	return float(st.get("real", 1.0)) if not st.is_empty() else 1.0


## Multiplicador de precios de comercio exterior con un pueblo (TradeSim.export_price/import_price).
## Si tu moneda se deprecia, importar cuesta más y exportar paga más (en tu moneda).
static func trade_fx_mult(gs, town_id: String) -> float:
	if not ready(gs):
		return 1.0
	var t := TradeSim.town(gs, town_id)
	var tc := str(t.get("country", ""))
	var home := home_id(gs)
	var fc := fx_cfg()
	if tc == "" or tc == home or country(gs, tc).is_empty():
		return 1.0 + float(fc.get("domestic_trade_share", 0.35)) * (real_index(gs) - 1.0)
	var rel := real_index(gs) / maxf(0.01, real_index(gs, tc))
	return 1.0 + float(fc.get("foreign_trade_share", 1.0)) * (rel - 1.0)


## Importaciones de los vecinos (MarketSim.purchase): parte del bien viene de fuera.
static func import_fx_mult(gs) -> float:
	if not ready(gs):
		return 1.0
	return 1.0 + float(fx_cfg().get("citizen_import_share", 0.5)) * (real_index(gs) - 1.0)


static func _currency_step(gs, id: String, st: Dictionary, is_home: bool) -> void:
	var fc := fx_cfg()
	var d: Dictionary = country_defs().get(id, {})
	if is_home:
		st["plevel"] = float(gs.price_level()) / maxf(0.01, float(gs.world_econ.get("home_p0", 1.0)))
		st["infl"] = EconomySim.annual_inflation(gs)
	else:
		var infl := float(d.get("base_inflation", 0.03)) + float(phase_def(str(st["phase"])).get("inflation_add", 0.0)) + rn(gs, float(fc.get("inflation_noise", 0.003)) * 12.0)
		infl = clampf(infl, -0.05, 0.4)
		st["infl"] = infl
		st["plevel"] = float(st.get("plevel", 1.0)) * (1.0 + infl / 12.0)
	var target := 1.0 + float(st.get("eff", {}).get("fx", 0.0))
	var real := float(st.get("real", 1.0))
	real += (target - real) * float(fc.get("real_revert", 0.15)) + rn(gs, float(fc.get("real_vol", 0.012)))
	st["real"] = clampf(real, float(fc.get("real_min", 0.8)), float(fc.get("real_max", 1.25)))
	st["rate"] = float(st.get("rate0", 1.0)) * float(st["plevel"]) / maxf(0.01, float(gs.world_econ.get("p_ref", 1.0))) * float(st["real"])
	var h: Array = st.get("hist", [])
	h.append({"day": gs.today(), "rate": st["rate"], "infl": st["infl"], "phase": st["phase"], "bolsa": float(st.get("ind", {}).get("bolsa", 100.0))})
	while h.size() > int(fc.get("history", 36)):
		h.pop_front()
	st["hist"] = h


## Variación del tipo de cambio de un país en los últimos `months` meses (+ = se deprecia).
static func rate_change(gs, id: String, months := 12) -> float:
	var st := country(gs, id)
	var h: Array = st.get("hist", [])
	if h.size() < 2:
		return 0.0
	var i := maxi(0, h.size() - 1 - months)
	return float(h[h.size() - 1]["rate"]) / maxf(0.0001, float(h[i]["rate"])) - 1.0


# --- Interfaz y utilidades -------------------------------------------------------------------------------

## Líneas para el panel de un edificio (calidad y marca, seguros).
static func panel_lines(gs, b: Dictionary) -> String:
	if not ready(gs):
		return ""
	return QualitySim.panel_lines(gs, b) + InsuranceSim.panel_lines(gs, b)


## Paga a vecinos del pueblo sin empleo (artesanos, proveedores); si no hay, al tesoro. El dinero no sale.
static func pay_local(gs, amount: float) -> void:
	if amount <= 0.0:
		return
	var today: int = gs.today()
	var adult := int(GameData.citizens.get("adult_age", 16))
	var pool := []
	for c in gs.citizens.values():
		if c.job_id < 0 and not gs.is_player(c.id) and c.age_years(today) >= adult and c.prison_until < 0:
			pool.append(c)
	if pool.is_empty():
		GovSim.add_treasury(gs, amount)
		return
	var n := mini(3, pool.size())
	var start := ri(gs, 0, pool.size() - 1)
	for i in range(n):
		var c: Citizen = pool[(start + i) % pool.size()]
		c.money += amount / float(n)


## Dinero fuera del pueblo que manejan estos sistemas (caja de la bolsa mundial y aseguradora externa).
static func outside_money(gs) -> float:
	if not ready(gs):
		return 0.0
	return StockSim.world_cash(gs) + InsuranceSim.external_cash(gs)


## Resumen corto del ciclo del país del jugador para la barra superior.
static func bar_text(gs) -> String:
	var st := home(gs)
	if st.is_empty():
		return ""
	var t := phase_label(str(st["phase"]))
	if str(st["phase"]) == "crisis" and str(st.get("kind", "")) != "":
		t = kind_label(str(st["kind"]))
	return "Economía: %s" % t
