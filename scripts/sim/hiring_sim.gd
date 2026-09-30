class_name HiringSim
extends RefCounted
## Contrataciones (pedido de Sebastián, ver docs/CONTRATACIONES.md).
##
## - Vacantes: al terminar la obra o la mejora de un negocio del jugador (también los de transporte y los
##   servicios públicos) se publica su vacante: puesto (operario, conductor, cargador, profesional),
##   puestos ocupados/total (MineSim.jobs), sueldo ofrecido (sugerido por mercado y editable), requisitos
##   (educación, profesión) y aviso "Tu negocio X está listo: tiene N vacantes".
## - Postulaciones: mientras la vacante está publicada llegan postulantes (desempleados, jornaleros y
##   empleados de otras empresas que buscan mejor sueldo). Llegan más —y mejores— con más sueldo frente
##   al mercado, mejor reputación como empleador y publicidad (campaña activa o medio propio).
## - Decidir: Contratar (BusinessSim.hire), Rechazar, Contraofertar (acepta si llega a su sueldo pedido;
##   entre el 90 y el 100 % quizá; debajo, se retira). Las postulaciones vencen a los `expire_days`.
##   Rechazos, vencimientos y contraofertas bajas bajan un poco la reputación; contratar la sube.
## - Auto-contratación por vacante: contrata al mejor que cumpla requisitos hasta el sueldo máximo fijado.
## - Transporte: al comprar un vehículo (LogisticsSim.buy_vehicle, TransitSim.buy_bus) se publica la
##   vacante de conductor; los vehículos sin conductor quedan detenidos (stopped_vehicles).
## Estado: GameState.labor["hiring"] (por país, se guarda con labor). RNG propio (semilla + día + sal).
## No mueve dinero: los sueldos los paga BusinessSim como siempre.

const ST_NEW := "nueva"
const ST_SEEN := "vista"
const PENDING := [ST_NEW, ST_SEEN]


static func cfg() -> Dictionary:
	return GameData.extra("contrataciones")


static func init_state(gs) -> void:
	if not (gs.labor is Dictionary):
		gs.labor = {}
	var h: Dictionary = gs.labor.get("hiring", {}) if gs.labor.get("hiring", {}) is Dictionary else {}
	if not h.has("vacancies") or not (h["vacancies"] is Dictionary):
		h["vacancies"] = {}
	if not h.has("apps") or not (h["apps"] is Array):
		h["apps"] = []
	if not h.has("left") or not (h["left"] is Dictionary):
		h["left"] = {}
	h["next_id"] = int(h.get("next_id", 1))
	h["reputation"] = float(h.get("reputation", float(cfg().get("reputation_start", 50.0))))
	gs.labor["hiring"] = h


static func state(gs) -> Dictionary:
	if not gs.labor.has("hiring"):
		init_state(gs)
	return gs.labor["hiring"]


static func _rng(gs, salt: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("hire|%d|%d|%s" % [int(gs.settings.get("seed", 0)), int(gs.today()), salt])
	return r


static func _next_id(gs) -> int:
	var h := state(gs)
	var id := int(h.get("next_id", 1))
	h["next_id"] = id + 1
	return id


# --- Consultas de puestos -----------------------------------------------------------------------

## ¿Tiene este edificio del jugador puestos que se contratan? (negocios, transporte y servicios públicos).
static func applies(gs, b: Dictionary) -> bool:
	return not b.is_empty() and gs.owned_by_player(b) and BusinessSim.is_business(b) and total_jobs(gs, b) > 0


static func total_jobs(gs, b: Dictionary) -> int:
	return MineSim.jobs(gs, b)


static func staff(gs, b: Dictionary) -> Array:
	return gs.employees_of(int(b["id"])).filter(func(c): return c.job_kind == "empleo")


static func occupied(gs, b: Dictionary) -> int:
	return staff(gs, b).size()


static func open_slots(gs, b: Dictionary) -> int:
	return maxi(0, total_jobs(gs, b) - occupied(gs, b))


static func is_station(gs, b: Dictionary) -> bool:
	return gs.level_def(b).has("transport_modes") or bool(gs.building_def(b).get("bus_company", false))


## Tipo de puesto: conductor (caballeriza, depósito, hangar, buses), cargador (central de transporte),
## profesional (el nivel exige título) u operario.
static func role(gs, b: Dictionary) -> String:
	if str(gs.level_def(b).get("required_profession", "")) != "":
		return "profesional"
	if bool(gs.building_def(b).get("bus_company", false)):
		return "conductor"
	var modes: Array = gs.level_def(b).get("transport_modes", [])
	if not modes.is_empty():
		for m in modes:
			if LogisticsSim.is_vehicle(str(m)):
				return "conductor" if str(b["type"]) != "central_transporte" else "cargador"
		return "cargador"
	return "operario"


static func role_label(r: String) -> String:
	return str(cfg().get("roles", {}).get(r, r.capitalize()))


static func req_education(gs, b: Dictionary) -> int:
	return int(gs.level_def(b).get("min_education", 0))


static func req_profession(gs, b: Dictionary) -> String:
	return str(gs.level_def(b).get("required_profession", ""))


static func requirements_text(gs, b: Dictionary) -> String:
	var parts := []
	var e := req_education(gs, b)
	if e > 0:
		parts.append("educación %s" % GameData.education_label(e))
	var p := req_profession(gs, b)
	if p != "":
		parts.append("título de %s" % GameData.profession_label(p).to_lower())
	return "sin requisitos" if parts.is_empty() else ", ".join(parts)


## ¿Cumple los requisitos del puesto? "" si sí; si no, el motivo corto.
static func unmet(gs, b: Dictionary, c: Citizen) -> String:
	if c.education < req_education(gs, b):
		return "le falta educación (%s)" % GameData.education_label(req_education(gs, b))
	var p := req_profession(gs, b)
	if p != "" and c.profession != p:
		return "no es %s" % GameData.profession_label(p).to_lower()
	return ""


static func meets(gs, b: Dictionary, c: Citizen) -> bool:
	return unmet(gs, b, c) == ""


## Sueldo de mercado sugerido para el puesto (lo que pide un postulante típico).
static func market_wage(gs, b: Dictionary) -> float:
	var def: Dictionary = gs.building_def(b)
	var f := 1.05 + 0.1 * req_education(gs, b) + (0.4 if req_profession(gs, b) != "" else 0.0)
	return snappedf(maxf(GovSim.min_wage(gs), float(def.get("base_wage", 2.0)) * f * gs.price_mult()), 0.05)


# --- Vacantes -------------------------------------------------------------------------------------

static func vacancy(gs, b: Dictionary) -> Dictionary:
	var v: Dictionary = state(gs)["vacancies"].get(str(int(b["id"])), {})
	return v


## Crea (si no existe) el registro de vacante del edificio, sin publicarlo.
static func ensure_vacancy(gs, b: Dictionary) -> Dictionary:
	var key := str(int(b["id"]))
	var vs: Dictionary = state(gs)["vacancies"]
	if not vs.has(key):
		var mw := market_wage(gs, b)
		vs[key] = {"bid": int(b["id"]), "wage": mw, "published": false, "auto": false, "auto_max": snappedf(mw * 1.15, 0.05), "opened": gs.today()}
	return vs[key]


static func publish(gs, b: Dictionary, on: bool) -> void:
	var v := ensure_vacancy(gs, b)
	v["published"] = on
	if on:
		v["opened"] = gs.today()


static func set_wage(gs, b: Dictionary, wage: float) -> void:
	ensure_vacancy(gs, b)["wage"] = maxf(GovSim.min_wage(gs), snappedf(wage, 0.05))


static func set_auto(gs, b: Dictionary, on: bool, max_wage := -1.0) -> void:
	var v := ensure_vacancy(gs, b)
	v["auto"] = on
	if max_wage > 0.0:
		v["auto_max"] = snappedf(max_wage, 0.05)


static func is_published(gs, b: Dictionary) -> bool:
	return bool(vacancy(gs, b).get("published", false))


## Estado de la vacante para la interfaz.
static func status_label(gs, b: Dictionary) -> String:
	if open_slots(gs, b) <= 0:
		return "Completa"
	if not is_published(gs, b):
		return "Pausada" if not vacancy(gs, b).is_empty() else "Sin publicar"
	return "Publicada · auto" if bool(vacancy(gs, b).get("auto", false)) else "Publicada"


## Edificios del jugador con puestos (para el panel): negocios, transporte y servicios públicos.
static func employers(gs) -> Array:
	var out := []
	for b in gs.buildings:
		if applies(gs, b) and str(b["status"]) != "construccion":
			out.append(b)
	return out


## Gancho de ConstructionSim._complete: al terminar la obra o la mejora se publican las vacantes.
static func on_building_ready(gs, b: Dictionary, upgraded := false) -> void:
	if not applies(gs, b):
		return
	var n := open_slots(gs, b)
	var v := ensure_vacancy(gs, b)
	v["wage"] = maxf(float(v.get("wage", 0.0)), market_wage(gs, b))   # Tras una mejora el sueldo sugerido puede subir.
	if n <= 0:
		return
	publish(gs, b, true)
	gs.notify("Tu negocio %s está listo%s: tiene %d vacante%s de %s (%s/día). Revisa los postulantes en Empresas → Contrataciones." % [
		gs.building_label(b), " tras la mejora" if upgraded else "", n, "" if n == 1 else "s", role_label(role(gs, b)).to_lower(),
		Fmt.money2(float(v["wage"]))], "negocio")


## Gancho de LogisticsSim.buy_vehicle / TransitSim.buy_bus: se abre la vacante de conductor.
static func on_vehicle_bought(gs, st: Dictionary, v: Dictionary = {}) -> void:
	if st.is_empty() or not applies(gs, st):
		return
	var need := vehicle_count(gs, st) - occupied(gs, st)
	if need <= 0 or open_slots(gs, st) <= 0:
		return
	ensure_vacancy(gs, st)
	var was := is_published(gs, st)
	publish(gs, st, true)
	if not was:
		gs.notify("Compraste %s: se publicó una vacante de %s en %s (faltan %d)." % [
			str(v.get("name", "un vehículo")), role_label(role(gs, st)).to_lower(), gs.building_label(st), mini(need, open_slots(gs, st))], "negocio")


# --- Vehículos y conductores -------------------------------------------------------------------------

## Vehículos de una estación (incluidos + comprados de todos los medios, o buses de la empresa de buses).
static func vehicle_count(gs, st: Dictionary) -> int:
	if bool(gs.building_def(st).get("bus_company", false)):
		return TransitSim.buses_of(gs, int(st["id"])).size()
	var n := LogisticsSim.vehicles_of(gs, int(st["id"])).size()   # Rutas y barcos: vehículos de cualquier compañía (compra central).
	for m in gs.level_def(st).get("transport_modes", []):
		if LogisticsSim.is_vehicle(str(m)):
			n += LogisticsSim.included_at(gs, st, str(m))
	return n


## Vehículos detenidos por falta de conductor (cada vehículo necesita un empleado presente).
static func stopped_vehicles(gs, st: Dictionary) -> int:
	if not is_station(gs, st):
		return 0
	return maxi(0, vehicle_count(gs, st) - LogisticsSim.crew_size(gs, st))


# --- Postulaciones ----------------------------------------------------------------------------------------

static func apps(gs) -> Array:
	return state(gs)["apps"]


static func pending(gs, b: Dictionary = {}) -> Array:
	return apps(gs).filter(func(a): return str(a["status"]) in PENDING and (b.is_empty() or int(a["bid"]) == int(b["id"])))


static func new_count(gs) -> int:
	var n := 0
	for a in apps(gs):
		if str(a["status"]) == ST_NEW:
			n += 1
	return n


static func mark_seen(gs, b: Dictionary = {}) -> void:
	for a in pending(gs, b):
		a["status"] = ST_SEEN


static func get_app(gs, id: int) -> Dictionary:
	for a in apps(gs):
		if int(a["id"]) == id:
			return a
	return {}


static func reputation(gs) -> float:
	return float(state(gs).get("reputation", 50.0))


static func _rep(gs, delta: float) -> void:
	var h := state(gs)
	h["reputation"] = clampf(float(h.get("reputation", 50.0)) + delta, 0.0, 100.0)


static func reputation_label(gs) -> String:
	var r := reputation(gs)
	if r >= 75.0:
		return "excelente"
	if r >= 58.0:
		return "buena"
	if r >= 42.0:
		return "normal"
	if r >= 25.0:
		return "regular"
	return "mala"


## Publicidad: campaña activa o medio de comunicación propio (periódico, radio, TV).
static func ad_mult(gs) -> float:
	var m := 1.0
	for c in AdvertisingSim.campaigns(gs):
		if AdvertisingSim.is_active(gs, c):
			m += float(cfg().get("ad_bonus_campaign", 0.25))
			break
	for b in gs.buildings:
		if gs.owned_by_player(b) and str(b["status"]) == "activo" and (str(b["type"]) == "medios" or str(b["type"]) == "imprenta_editorial"):
			m += float(cfg().get("ad_bonus_media", 0.2))
			break
	return m


static func wage_factor(gs, b: Dictionary) -> float:
	var v := vacancy(gs, b)
	var ratio := float(v.get("wage", market_wage(gs, b))) / maxf(0.01, market_wage(gs, b))
	var rg: Array = cfg().get("wage_factor_range", [0.15, 3.0])
	return clampf(pow(ratio, float(cfg().get("wage_power", 2.5))), float(rg[0]), float(rg[1]))


## Postulantes esperados por día para la vacante (para el panel y el cálculo diario).
static func daily_rate(gs, b: Dictionary) -> float:
	return float(cfg().get("base_rate", 0.7)) * wage_factor(gs, b) * (0.6 + reputation(gs) / 100.0 * 0.8) * ad_mult(gs) \
		* (0.6 + 0.4 * minf(3.0, float(open_slots(gs, b))))


## Sueldo que pide un postulante (el desempleado su sueldo de mercado; el empleado, +10 % sobre lo que gana).
static func asked_for(gs, b: Dictionary, c: Citizen) -> float:
	var a := maxf(GovSim.min_wage(gs), BusinessSim.asked_wage(gs, c, str(b["type"])))
	if c.job_kind == "empleo":
		a = maxf(a, c.wage * float(cfg().get("employed_min_raise", 1.1)))
	return snappedf(a, 0.05)


## Pool de postulantes posibles de hoy (una pasada por los ciudadanos).
static func _pool(gs) -> Dictionary:
	var today: int = gs.today()
	var adult := int(GameData.citizens.get("adult_age", 16))
	var retire := int(GameData.citizens.get("retirement_age", 65))
	var busy := {}
	for a in apps(gs):
		if str(a["status"]) in PENDING:
			busy[int(a["cid"])] = true
	var free := []
	var employed := []
	for c in gs.citizens.values():
		if gs.is_player(c.id) or c.job_kind == "dueño" or busy.has(c.id) or c.prison_until > today or c.school_id >= 0:
			continue
		var age: int = c.age_years(today)
		if age < adult or age >= retire:
			continue
		if c.job_kind == "empleo":
			var jb: Dictionary = gs.get_building(c.job_id)
			if jb.is_empty() or gs.owned_by_player(jb):
				continue   # Tus propios empleados no se postulan a tus vacantes.
			employed.append(c)
		else:
			free.append(c)
	return {"free": free, "employed": employed, "busy": busy}


static func daily(gs) -> void:
	var h := state(gs)
	var today: int = gs.today()
	_expire(gs, today)
	var vs: Dictionary = h["vacancies"]
	var pool := {}
	for key in vs.keys():
		var b: Dictionary = gs.get_building(int(key))
		if b.is_empty() or not gs.owned_by_player(b):
			vs.erase(key)
			continue
		var v: Dictionary = vs[key]
		if not bool(v.get("published", false)) or str(b["status"]) == "construccion" or str(b["status"]) == "cerrado":
			continue
		if open_slots(gs, b) <= 0:
			continue
		if pool.is_empty():
			pool = _pool(gs)
		_arrivals(gs, b, v, pool)
		if bool(v.get("auto", false)):
			auto_hire(gs, b)


## Llegan postulantes (Poisson simple con el RNG propio de la vacante).
static func _arrivals(gs, b: Dictionary, v: Dictionary, pool: Dictionary) -> int:
	var cap := maxi(int(cfg().get("max_pending_min", 4)), open_slots(gs, b) * int(cfg().get("max_pending_per_slot", 4)))
	var have := pending(gs, b).size()
	if have >= cap:
		return 0
	var r := _rng(gs, "arr%d" % int(b["id"]))
	var lam := daily_rate(gs, b)
	var n := int(floor(lam))
	if r.randf() < lam - floor(lam):
		n += 1
	var got := 0
	for i in n:
		if have + got >= cap:
			break
		var c := _pick(gs, b, v, pool, r)
		if c == null:
			break
		add_application(gs, b, c)
		pool["busy"][c.id] = true
		got += 1
	return got


## Elige un postulante: el mejor de k al azar (k crece con el sueldo y la reputación → mejores postulantes).
static func _pick(gs, b: Dictionary, v: Dictionary, pool: Dictionary, r: RandomNumberGenerator) -> Citizen:
	var offered := float(v.get("wage", market_wage(gs, b)))
	var skill := str(gs.building_def(b).get("skill", ""))
	var k := int(cfg().get("best_of_base", 1)) + int(floor(wage_factor(gs, b) * 1.5)) + (1 if reputation(gs) >= 65.0 else 0)
	var best: Citizen = null
	var best_s := -1.0
	var free: Array = pool["free"]
	var emp: Array = pool["employed"]
	for i in maxi(1, k) * 2:
		var from_emp := not emp.is_empty() and (free.is_empty() or r.randf() < float(cfg().get("employed_share", 0.35)))
		var src: Array = emp if from_emp else free
		if src.is_empty():
			continue
		var c: Citizen = src[r.randi() % src.size()]
		if pool["busy"].has(c.id) or c.job_kind == "empleo" and c.job_id >= 0 and gs.owned_by_player(gs.get_building(c.job_id)):
			continue
		if from_emp and offered < c.wage * float(cfg().get("employed_min_raise", 1.1)):
			continue   # Empleado: solo se postula si gana bastante más.
		if offered < asked_for(gs, b, c) * float(cfg().get("apply_min_ratio", 0.8)):
			continue   # Pide mucho más de lo que ofreces.
		var s := float(c.skills.get(skill, 0.0)) + LaborSim.years(c, skill) * 4.0 + c.education * 8.0 + (25.0 if meets(gs, b, c) else 0.0)
		if s > best_s:
			best_s = s
			best = c
		if i + 1 >= k and best != null:
			break
	return best


static func add_application(gs, b: Dictionary, c: Citizen) -> Dictionary:
	var today: int = gs.today()
	var skill := str(gs.building_def(b).get("skill", ""))
	var prev := ""
	var from_label := ""
	if c.job_kind == "empleo" and c.job_id >= 0:
		prev = "empleado"
		from_label = gs.building_label(gs.get_building(c.job_id))
	elif c.job_kind == "obra":
		prev = "jornalero"
	var left: Dictionary = state(gs)["left"].get(str(c.id), {})
	if prev == "" and not left.is_empty():
		prev = str(left.get("kind", ""))
		from_label = str(left.get("from", ""))
	var a := {"id": _next_id(gs), "bid": int(b["id"]), "cid": c.id, "name": c.full_name(), "day": today,
		"expires": today + int(cfg().get("expire_days", 14)), "asked": asked_for(gs, b, c),
		"prev": prev, "from": from_label, "cur_wage": c.wage if c.job_kind == "empleo" else 0.0,
		"skill": int(c.skills.get(skill, 0.0)), "status": ST_NEW}
	apps(gs).append(a)
	return a


static func _expire(gs, today: int) -> void:
	for a in apps(gs):
		if not (str(a["status"]) in PENDING):
			continue
		var c: Citizen = gs.citizens.get(int(a["cid"]))
		var b: Dictionary = gs.get_building(int(a["bid"]))
		if c == null or b.is_empty() or not gs.owned_by_player(b):
			a["status"] = "retirada"
		elif c.job_kind == "empleo" and c.job_id >= 0 and gs.owned_by_player(gs.get_building(c.job_id)):
			a["status"] = "retirada"   # Ya trabaja para ti en otro negocio.
		elif today >= int(a["expires"]):
			a["status"] = "vencida"
			_rep(gs, float(cfg().get("rep_expired", -0.35)))
	_trim(gs)


## Quita del historial las postulaciones cerradas más viejas.
static func _trim(gs) -> void:
	var arr := apps(gs)
	var limit := int(cfg().get("max_pending_total", 250))
	if arr.size() <= limit:
		return
	var keep := []
	var closed := []
	for a in arr:
		if str(a["status"]) in PENDING:
			keep.append(a)
		else:
			closed.append(a)
	var room := maxi(0, limit - keep.size())
	var out := closed.slice(maxi(0, closed.size() - room))
	out.append_array(keep)
	state(gs)["apps"] = out


# --- Decisiones ------------------------------------------------------------------------------------------------

## Sueldo al que se contrata con "Contratar": el publicado si alcanza lo que pide; si no, lo que pide.
static func hire_wage(gs, a: Dictionary) -> float:
	var b: Dictionary = gs.get_building(int(a["bid"]))
	var offered := float(vacancy(gs, b).get("wage", 0.0)) if not b.is_empty() else 0.0
	return maxf(GovSim.min_wage(gs), offered if offered >= float(a["asked"]) else float(a["asked"]))


## Contrata al postulante (si trabaja en otra empresa, renuncia allí). Devuelve "" o el motivo.
static func hire_app(gs, id: int, wage := -1.0) -> String:
	var a := get_app(gs, id)
	if a.is_empty() or not (str(a["status"]) in PENDING):
		return "La postulación ya no está vigente."
	var c: Citizen = gs.citizens.get(int(a["cid"]))
	var b: Dictionary = gs.get_building(int(a["bid"]))
	if c == null or b.is_empty():
		a["status"] = "retirada"
		return "La postulación ya no está vigente."
	if wage < 0.0:
		wage = hire_wage(gs, a)
	var why := unmet(gs, b, c)
	if why != "":
		return "%s %s: no cumple los requisitos." % [c.full_name(), why]
	var old_id := c.job_id
	var old_kind := c.job_kind
	var old_wage := c.wage
	if c.job_kind == "empleo":
		NpcBusinessSim.release(gs, c)   # Deja su empleo actual (empresa NPC o gobierno).
	var err := BusinessSim.hire(gs, b, c, wage)
	if err != "":
		c.job_id = old_id
		c.job_kind = old_kind
		c.wage = old_wage
		if old_kind == "empleo":
			NpcBusinessSim.staff_index(gs)
		return err
	a["status"] = "contratada"
	a["wage"] = c.wage
	state(gs)["left"].erase(str(c.id))
	_rep(gs, float(cfg().get("rep_hire", 0.4)))
	return ""


static func reject_app(gs, id: int) -> String:
	var a := get_app(gs, id)
	if a.is_empty() or not (str(a["status"]) in PENDING):
		return "La postulación ya no está vigente."
	a["status"] = "rechazada"
	var b: Dictionary = gs.get_building(int(a["bid"]))
	var c: Citizen = gs.citizens.get(int(a["cid"]))
	var unq := c != null and not b.is_empty() and not meets(gs, b, c)
	_rep(gs, float(cfg().get("rep_reject_unqualified" if unq else "rep_reject", -0.25)))
	if c != null:
		c.happiness = maxf(0.0, c.happiness - 1.0)
	return ""


## Rechaza a todos los que no cumplen los requisitos (de un edificio o de todos). Devuelve cuántos.
static func reject_unqualified(gs, b: Dictionary = {}) -> int:
	var n := 0
	for a in pending(gs, b):
		var bb: Dictionary = gs.get_building(int(a["bid"]))
		var c: Citizen = gs.citizens.get(int(a["cid"]))
		if c == null or bb.is_empty() or not meets(gs, bb, c):
			reject_app(gs, int(a["id"]))
			n += 1
	return n


## Contraoferta: acepta si llega a lo que pide; entre el 90 y el 100 % puede aceptar (más cerca, más
## probable); debajo, rechaza y retira su postulación. Devuelve {"accepted": bool, "text": String}.
static func counter_offer(gs, id: int, wage: float) -> Dictionary:
	var a := get_app(gs, id)
	if a.is_empty() or not (str(a["status"]) in PENDING):
		return {"accepted": false, "text": "La postulación ya no está vigente."}
	wage = snappedf(wage, 0.05)
	if wage < GovSim.min_wage(gs):
		return {"accepted": false, "text": "El salario mínimo legal es %s/día." % Fmt.money2(GovSim.min_wage(gs))}
	var asked := float(a["asked"])
	var floor_r := float(cfg().get("counter_accept_floor", 0.9))
	var ratio := wage / maxf(0.01, asked)
	var ok := ratio >= 1.0
	if not ok and ratio >= floor_r:
		ok = _rng(gs, "counter%d" % id).randf() < (ratio - floor_r) / maxf(0.001, 1.0 - floor_r)
	var name := str(a["name"])
	if not ok:
		a["status"] = "retirada"
		a["counter"] = wage
		_rep(gs, float(cfg().get("rep_counter_rejected", -0.3)))
		return {"accepted": false, "text": "%s rechazó tu contraoferta de %s/día (pedía %s) y retiró su postulación." % [name, Fmt.money2(wage), Fmt.money2(asked)]}
	var err := hire_app(gs, id, wage)
	if err != "":
		return {"accepted": false, "text": err}
	return {"accepted": true, "text": "%s aceptó tu contraoferta de %s/día." % [name, Fmt.money2(wage)]}


## Auto-contratación: el mejor postulante que cumpla requisitos y pida hasta el máximo fijado.
static func auto_hire(gs, b: Dictionary) -> int:
	var v := vacancy(gs, b)
	var max_w := float(v.get("auto_max", 0.0))
	var skill := str(gs.building_def(b).get("skill", ""))
	var n := 0
	while open_slots(gs, b) > 0:
		var best := {}
		var best_p := -1.0
		for a in pending(gs, b):
			var c: Citizen = gs.citizens.get(int(a["cid"]))
			if c == null or not meets(gs, b, c) or float(a["asked"]) > max_w:
				continue
			var p := BusinessSim.productivity(c, skill)
			if p > best_p:
				best_p = p
				best = a
		if best.is_empty():
			break
		var w := clampf(float(v.get("wage", 0.0)), float(best["asked"]), max_w)
		if hire_app(gs, int(best["id"]), w) != "":
			best["status"] = "retirada"
			continue
		n += 1
	if n > 0 and open_slots(gs, b) <= 0:
		v["published"] = false   # Completa: deja de recibir postulantes.
	return n


# --- Personal ---------------------------------------------------------------------------------------------------

## Riesgo de que un empleado se vaya: "alto", "medio" o "bajo" (sueldo frente a lo que pide, ofertas NPC, felicidad).
static func quit_risk(gs, c: Citizen) -> String:
	var b: Dictionary = gs.get_building(c.job_id)
	if b.is_empty():
		return "—"
	var asked := BusinessSim.asked_wage(gs, c, str(b["type"]))
	var ratio := float(GameData.citizens.get("quit_wage_ratio", 0.8))
	if c.wage < asked * ratio or LaborSim.pending_offers(gs).any(func(o): return int(o["cid"]) == c.id):
		return "alto"
	if c.wage < asked or c.happiness < 35.0 or c.age_years(gs.today()) >= int(GameData.citizens.get("retirement_age", 65)) - 1:
		return "medio"
	return "bajo"


## Despido desde el panel (queda anotado para su próxima postulación).
static func fire(gs, c: Citizen) -> void:
	BusinessSim.fire(gs, c, "Despediste a %s." % c.full_name())


## Gancho de BusinessSim.fire: anota que dejó (renuncia/jubilación) o perdió (despido) su empleo.
static func note_left(gs, c: Citizen, from_id: int, message: String) -> void:
	if c == null or from_id < 0 or not (gs.labor is Dictionary):
		return
	var b: Dictionary = gs.get_building(from_id)
	var kind := "despedido"
	if message.contains("renunció"):
		kind = "renunció"
	elif message.contains("jubiló"):
		return
	state(gs)["left"][str(c.id)] = {"kind": kind, "from": gs.building_label(b) if not b.is_empty() else "", "day": gs.today()}


static func change_wage(gs, c: Citizen, delta: float) -> void:
	c.wage = maxf(maxf(0.1, GovSim.min_wage(gs)), snappedf(c.wage + delta, 0.05))


# --- Reputación mensual ------------------------------------------------------------------------------------------

static func monthly(gs) -> void:
	var h := state(gs)
	var sum := 0.0
	var happy := 0.0
	var n := 0
	for c in gs.citizens.values():
		if c.job_kind != "empleo" or c.job_id < 0:
			continue
		var b: Dictionary = gs.get_building(c.job_id)
		if b.is_empty() or not gs.owned_by_player(b):
			continue
		sum += c.wage / maxf(0.01, BusinessSim.asked_wage(gs, c, str(b["type"])))
		happy += c.happiness
		n += 1
	if n > 0:
		var target := 50.0 + clampf((sum / n - 1.0) * float(cfg().get("rep_wage_weight", 60.0)), -30.0, 30.0) \
			+ clampf((happy / n - 60.0) * float(cfg().get("rep_happy_weight", 0.3)), -10.0, 10.0)
		var cur := reputation(gs)
		h["reputation"] = clampf(cur + (target - cur) * float(cfg().get("rep_monthly_drift", 0.15)), 0.0, 100.0)
	var today: int = gs.today()
	var mem := int(cfg().get("left_memory_days", 730))
	var left: Dictionary = h["left"]
	for k in left.keys():
		if today - int(left[k].get("day", 0)) > mem or not gs.citizens.has(int(k)):
			left.erase(k)


## Texto de la ficha "fue despedido o dejó otro empleo".
static func prev_text(a: Dictionary) -> String:
	match str(a.get("prev", "")):
		"empleado":
			return "trabaja en %s (%s/día): busca mejor sueldo" % [str(a.get("from", "")), Fmt.money2(float(a.get("cur_wage", 0.0)))]
		"jornalero":
			return "jornalero de obra"
		"despedido":
			return "fue despedido de %s" % str(a.get("from", "")) if str(a.get("from", "")) != "" else "fue despedido"
		"renunció":
			return "dejó su empleo en %s" % str(a.get("from", "")) if str(a.get("from", "")) != "" else "dejó su empleo anterior"
	return "desempleado"
