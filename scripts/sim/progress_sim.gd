class_name ProgressSim
extends RefCounted
## Misiones guía y logros (docs/MISIONES_ESCENARIOS.md). Datos en data/progreso.json.
##
## Estado en GameState.progress (se guarda con la partida; las partidas viejas lo crean al cargar):
##   missions{id: {done, day, reward, from_treasury, from_external, silent}}, hidden, collapsed,
##   start{techs, era}, achievements{id: {day, date}}, debt_free_months, rewards_log[].
## Misiones: opcionales, sin pop-ups. Se revisan cada 7 días (y al empezar cada mes). La recompensa es
## pequeña (× precios) y tiene origen registrado: sale del tesoro del pueblo (fondo de fomento) y, si no
## alcanza, de la cámara de comercio exterior (FlowSim.external_in, motivo "premio_mision_guia"), así la
## conservación del dinero se mantiene.
## Logros: se revisan cada mes. Se guardan en la partida y en el perfil global `profile_path`
## (user://logros.cfg, ConfigFile, sección "logros"). El perfil solo se escribe con `profile_enabled`
## (lo activa el menú principal al entrar a jugar, así las pruebas no ensucian el perfil del jugador).
## Avisos discretos: `pending` (cola que lee GuidePanel); no se emiten señales ni toasts del HUD.

static var profile_path := "user://logros.cfg"
static var profile_enabled := false
static var pending: Array = []          # [{kind: "logro"|"mision", id, label, text}]
static var _profile: ConfigFile = null


static func cfg() -> Dictionary:
	return GameData.extra("progreso")


static func missions() -> Array:
	return cfg().get("missions", [])


static func achievements() -> Array:
	return cfg().get("achievements", [])


static func achievement_def(id: String) -> Dictionary:
	for a in achievements():
		if str(a.get("id", "")) == id:
			return a
	return {}


static func mission_def(id: String) -> Dictionary:
	for m in missions():
		if str(m.get("id", "")) == id:
			return m
	return {}


# --- Estado ------------------------------------------------------------------------------------

## Crea o completa el estado. `fresh` = partida nueva (las viejas marcan como hechas, sin premio, las
## misiones que ya cumplían, para no regalar dinero al cargar).
static func init_state(gs, _fresh: bool) -> void:
	var p: Dictionary = gs.progress
	if not (p.get("missions") is Dictionary):
		p["missions"] = {}
	if not (p.get("achievements") is Dictionary):
		p["achievements"] = {}
	if not (p.get("rewards_log") is Array):
		p["rewards_log"] = []
	if not (p.get("start") is Dictionary):
		p["start"] = {"techs": gs.techs.size(), "era": gs.era()}
	p["hidden"] = bool(p.get("hidden", false))
	p["collapsed"] = bool(p.get("collapsed", false))
	p["debt_free_months"] = int(p.get("debt_free_months", 0))
	var ms: Dictionary = p["missions"]
	for m in missions():
		var id := str(m["id"])
		if not (ms.get(id) is Dictionary):
			ms[id] = {"done": false}
	# Lo que ya se cumple al empezar (p. ej., la granja heredada o una partida vieja) cuenta como hecho,
	# sin premio: las misiones son para orientarse, no para cobrar.
	for m in missions():
		var id := str(m["id"])
		if not bool(ms[id].get("done", false)) and mission_met(gs, id):
			ms[id] = {"done": true, "day": gs.today(), "reward": 0.0, "silent": true}


static func st(gs) -> Dictionary:
	if not (gs.progress.get("missions") is Dictionary):
		init_state(gs, false)
	return gs.progress


static func is_done(gs, id: String) -> bool:
	return bool(st(gs)["missions"].get(id, {}).get("done", false))


static func done_count(gs) -> int:
	var n := 0
	for m in missions():
		if is_done(gs, str(m["id"])):
			n += 1
	return n


static func has_achievement(gs, id: String) -> bool:
	return st(gs)["achievements"].has(id)


static func set_hidden(gs, v: bool) -> void:
	st(gs)["hidden"] = v


static func set_collapsed(gs, v: bool) -> void:
	st(gs)["collapsed"] = v


# --- Ciclo ---------------------------------------------------------------------------------------

## Lo llama GameState.simulate_country_day en el pase principal (país de origen cargado).
static func daily(gs, new_month: bool) -> void:
	if not gs.running:
		return
	var p := st(gs)
	if new_month or gs.today() % 7 == 0:
		_check_missions(gs)
	if new_month:
		_month_counters(gs, p)
		check_achievements(gs)


static func _check_missions(gs) -> void:
	var ms: Dictionary = st(gs)["missions"]
	for m in missions():
		var id := str(m["id"])
		if bool(ms.get(id, {}).get("done", false)):
			continue
		if mission_met(gs, id):
			_complete(gs, m)


static func _complete(gs, m: Dictionary) -> void:
	var id := str(m["id"])
	var amount := snappedf(float(m.get("reward", 100)) * gs.price_mult(), 1.0)
	var from_t := GovSim.treasury_pay(gs, amount)   # Fondo de fomento del pueblo.
	var from_ext := amount - from_t
	if from_ext > 0.0:
		FlowSim.external_in(gs, from_ext, str(cfg().get("mission_source_reason", "premio_mision_guia")))   # Cámara de comercio exterior.
	gs.add_money(amount)
	gs.add_counter("subsidies", amount)
	st(gs)["missions"][id] = {"done": true, "day": gs.today(), "reward": amount, "from_treasury": from_t, "from_external": from_ext}
	var log: Array = st(gs)["rewards_log"]
	log.append({"mission": id, "amount": amount, "from_treasury": from_t, "from_external": from_ext, "day": gs.today()})
	var origin := "el fondo de fomento del pueblo" if from_ext <= 0.0 else ("la cámara de comercio exterior" if from_t <= 0.0 else "el fondo de fomento y la cámara de comercio exterior")
	var text := "Misión guía cumplida: %s. Premio %s de %s." % [str(m.get("label", id)), Fmt.money(amount), origin]
	_log_quiet(gs, text, "jugador")
	pending.append({"kind": "mision", "id": id, "label": str(m.get("label", id)), "text": text})
	if done_count(gs) >= missions().size():
		check_achievements(gs)


## Aviso en el registro de notificaciones sin toast (las misiones no hostigan).
static func _log_quiet(gs, text: String, category: String) -> void:
	gs.notifications_log.append({"text": text, "category": category, "date": TimeManager.date_string(false)})
	if gs.notifications_log.size() > 300:
		gs.notifications_log.pop_front()


static func _month_counters(gs, p: Dictionary) -> void:
	if EconomySim.player_debt(gs) <= 0.01 and gs.money >= 0.0:
		p["debt_free_months"] = int(p.get("debt_free_months", 0)) + 1
	else:
		p["debt_free_months"] = 0


# --- Condiciones de las misiones --------------------------------------------------------------------

static func mission_met(gs, id: String) -> bool:
	match id:
		"primera_fabrica":
			return active_businesses(gs) >= 1
		"contratar":
			return employees(gs) >= 3
		"primer_contrato":
			return not ContractSim.contracts(gs).is_empty()
		"vehiculo_ruta":
			return not LogisticsSim.vehicles(gs).is_empty() and not LogisticsSim.routes(gs).is_empty()
		"venta_mayorista":
			if float(gs.trade.get("totals", {}).get("exports", 0.0)) > 0.0:
				return true
			for k in ContractSim.contracts(gs):
				if str(k.get("dir", ContractSim.DIR_SELL)) == ContractSim.DIR_SELL and float(k.get("paid", 0.0)) > 0.0:
					return true
			return false
		"investigar":
			return gs.techs.size() > int(st(gs)["start"].get("techs", 0))
		"heredero":
			return heirs(gs) >= 1
	return false


static func active_businesses(gs) -> int:
	var n := 0
	for b in gs.buildings:
		if gs.owned_by_player(b) and BusinessSim.is_business(b) and str(b.get("status", "")) == "activo":
			n += 1
	return n


static func employees(gs) -> int:
	var mine := {}
	for b in gs.buildings:
		if gs.owned_by_player(b):
			mine[int(b["id"])] = true
	var n := 0
	for c in gs.citizens.values():
		if c.job_kind == "empleo" and mine.has(c.job_id):
			n += 1
	return n


static func heirs(gs) -> int:
	var p: Citizen = gs.player_citizen()
	if p == null:
		return 0
	var n := 0
	for cid in p.children_ids:
		if gs.citizens.has(int(cid)):
			n += 1
	return n


## Texto de avance de una misión (para el panel): "1/3", "" si no aplica.
static func mission_progress(gs, id: String) -> String:
	match id:
		"contratar":
			return "%d/3" % mini(3, employees(gs))
	return ""


# --- Logros ------------------------------------------------------------------------------------------

static func check_achievements(gs) -> void:
	var got: Dictionary = st(gs)["achievements"]
	for a in achievements():
		var id := str(a["id"])
		if got.has(id):
			continue
		if achievement_met(gs, a):
			unlock(gs, id)


static func unlock(gs, id: String) -> void:
	var got: Dictionary = st(gs)["achievements"]
	if got.has(id):
		return
	var a := achievement_def(id)
	got[id] = {"day": gs.today(), "date": TimeManager.date_string(false)}
	var text := "Logro: %s — %s" % [str(a.get("label", id)), str(a.get("description", ""))]
	_log_quiet(gs, text, "importante")
	pending.append({"kind": "logro", "id": id, "label": str(a.get("label", id)), "text": text})
	_profile_add(gs, id)


static func _real_net_worth(gs) -> float:
	return EconomySim.net_worth(gs) / maxf(0.01, gs.price_level())


static func achievement_met(gs, a: Dictionary) -> bool:
	var id := str(a["id"])
	var value := float(a.get("value", 0.0))
	match id:
		"guia_completa":
			return done_count(gs) >= missions().size()
		"primer_negocio":
			return active_businesses(gs) >= 1
		"cinco_negocios":
			return active_businesses(gs) >= 5
		"veinte_negocios":
			return active_businesses(gs) >= 20
		"gran_empleador":
			return employees(gs) >= 50
		"diez_mil", "cien_mil", "primer_millon":
			return _real_net_worth(gs) >= value
		"tres_generaciones":
			return DynastySim.generation(gs) >= 3
		"cinco_generaciones":
			return DynastySim.generation(gs) >= 5
		"monopolio":
			return monopoly_good(gs) != ""
		"exportador":
			return float(gs.trade.get("totals", {}).get("exports", 0.0)) / maxf(0.01, gs.price_level()) >= value
		"cinco_paises":
			return CountriesSim.ready(gs) and CountriesSim.presence_ids(gs).size() >= 5
		"sin_deudas":
			return int(st(gs).get("debt_free_months", 0)) >= int(a.get("months", 120))
		"ilustrado":
			return gs.techs.size() - int(st(gs)["start"].get("techs", 0)) >= 10
		"nueva_epoca":
			return gs.era() > int(st(gs)["start"].get("era", 1))
		"era_moderna":
			return gs.era() >= 3 and int(st(gs)["start"].get("era", 1)) < 3
		"ciudad":
			return gs.citizens.size() >= 300
		"buen_pagador":
			return CreditSim.score(gs, "jugador") >= 800.0
		"remontada":
			if str(gs.settings.get("scenario", "normal")) != "quebrada" or gs.money < 0.0:
				return false
			for l in gs.loans:
				if str(l.get("purpose", "")) == ScenarioSim.INHERITED_PURPOSE:
					return false
			return true
		"desde_abajo":
			return str(gs.settings.get("scenario", "normal")) == "pobre" and _real_net_worth(gs) >= value
		"a_pulso":
			return str(gs.settings.get("difficulty", "normal")) in ["dificil", "extremo"] and _real_net_worth(gs) >= value
		"centenario":
			return gs.today() >= 100 * TimeManager.DAYS_PER_YEAR
	return false


## Bien del que el jugador es el único productor activo del país (≥ 2 negocios suyos), o "".
static func monopoly_good(gs) -> String:
	var mine := {}
	var others := {}
	for b in gs.buildings:
		if str(b.get("status", "")) != "activo" or not BusinessSim.is_business(b):
			continue
		var good := str(gs.building_def(b).get("product", ""))
		if good == "":
			continue
		if gs.owned_by_player(b):
			mine[good] = int(mine.get(good, 0)) + 1
		else:
			others[good] = true
	for g in mine:
		if int(mine[g]) >= 2 and not others.has(g):
			return str(g)
	return ""


# --- Perfil global (user://logros.cfg) -------------------------------------------------------------

static func profile() -> ConfigFile:
	if _profile == null:
		_profile = ConfigFile.new()
		if FileAccess.file_exists(profile_path):
			_profile.load(profile_path)
	return _profile


## Cambia el archivo del perfil (las pruebas usan uno propio).
static func use_profile(path: String, enabled: bool) -> void:
	profile_path = path
	profile_enabled = enabled
	_profile = null


static func profile_has(id: String) -> bool:
	return profile().has_section_key("logros", id)


static func profile_count() -> int:
	return profile().get_section_keys("logros").size() if profile().has_section("logros") else 0


static func _profile_add(gs, id: String) -> void:
	if not profile_enabled:
		return
	var cf := profile()
	if cf.has_section_key("logros", id):
		return
	cf.set_value("logros", id, {"unlocked_at": Time.get_datetime_string_from_system(false, true),
		"game_date": TimeManager.date_string(false), "player": gs.player_name(),
		"town": str(gs.settings.get("town_name", "")), "difficulty": str(gs.settings.get("difficulty", "normal")),
		"scenario": str(gs.settings.get("scenario", "normal"))})
	cf.save(profile_path)


## Pasa al perfil los logros de la partida cargada que aún no estén (al entrar a jugar).
static func sync_profile(gs) -> void:
	if not profile_enabled:
		return
	for id in st(gs)["achievements"]:
		_profile_add(gs, str(id))


static func pop_pending() -> Array:
	var out := pending
	pending = []
	return out
