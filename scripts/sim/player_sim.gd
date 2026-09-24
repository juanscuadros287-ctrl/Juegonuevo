class_name PlayerSim
extends RefCounted
## Tu personaje: es un ciudadano más (envejece, enferma, muere), pero además
## conoce gente, corteja, se casa, tiene o adopta hijos, elige heredero y
## decide dónde vive. Parámetros en data/game.json → "player".


static func cfg() -> Dictionary:
	return GameData.game.get("player", {})


static func create_player(gs) -> void:
	var s: Dictionary = gs.settings
	var gender := str(s.get("player_gender", "M"))
	var c := PopulationSim.create_citizen(gs, gender, int(s.get("player_age", 25)), str(s.get("player_surname", "Cuadros")))
	c.first_name = str(s.get("player_name", "Sebastián"))
	c.skills["comercio"] = maxf(float(c.skills.get("comercio", 0.0)), 40.0)
	c.education = maxi(c.education, 1)
	c.health = 100.0
	c.happiness = 70.0
	c.money = 0.0
	var hut := PopulationSim.create_hut(gs)
	hut["owner"] = "jugador"
	hut["name"] = "Mi casa"
	ConstructionSim.apply_tier(hut, "normal")
	c.home_id = int(hut["id"])
	gs.player_id = c.id
	gs.player = {"relations": {}, "talked": {}, "family_planning": true, "doctor_until": -1,
		"try_child_until": -1, "heir_id": -1}
	DynastySim.ensure(gs)


static func migrate_v1_player(gs, old: Dictionary) -> void:
	var name := str(old.get("name", "Sebastián"))
	gs.settings["player_name"] = name
	create_player(gs)
	var p: Citizen = gs.player_citizen()
	p.birth_day = int(old.get("birth_day", p.birth_day))


# --- Relaciones ------------------------------------------------------------------------

static func affinity(gs, id: int) -> float:
	return float(gs.player.get("relations", {}).get(str(id), 0.0))


static func _add_affinity(gs, id: int, amount: float) -> float:
	var rel: Dictionary = gs.player.get("relations", {})
	var v := clampf(float(rel.get(str(id), 0.0)) + amount, 0.0, 100.0)
	rel[str(id)] = v
	gs.player["relations"] = rel
	return v


static func relation_label(gs, c: Citizen) -> String:
	var p: Citizen = gs.player_citizen()
	if p == null:
		return ""
	if p.spouse_id == c.id:
		return "Cónyuge"
	if p.children_ids.has(c.id):
		return "Hijo(a)"
	if p.parent_ids.has(c.id):
		return "Padre/Madre"
	var a := affinity(gs, c.id)
	if a >= 80:
		return "Muy cercano(a) (%d)" % int(a)
	if a >= 55:
		return "Amigo(a) (%d)" % int(a)
	if a >= 25:
		return "Conocido(a) (%d)" % int(a)
	if a > 0:
		return "Te conoce poco (%d)" % int(a)
	return "Desconocido(a)"


static func _is_related(p: Citizen, c: Citizen) -> bool:
	return p.children_ids.has(c.id) or p.parent_ids.has(c.id) or PopulationSim.is_related(p, c)


static func can_talk(gs, c: Citizen) -> String:
	if gs.is_player(c.id):
		return "Eres tú"
	if int(gs.player.get("talked", {}).get(str(c.id), -1)) == gs.today():
		return "Ya hablaron hoy"
	return ""


static func talk(gs, c: Citizen) -> String:
	var r := can_talk(gs, c)
	if r != "":
		return r
	var p: Citizen = gs.player_citizen()
	var g: Array = cfg().get("talk_gain", [3, 9])
	var gain: float = gs.rng.randf_range(float(g[0]), float(g[1])) * (0.7 + p.happiness / 100.0 * 0.6)
	gs.player["talked"][str(c.id)] = gs.today()
	var v := _add_affinity(gs, c.id, gain)
	return "Conversaste con %s. Relación: %d/100." % [c.first_name, int(v)]


static func can_court(gs, c: Citizen) -> String:
	var p: Citizen = gs.player_citizen()
	if p == null or gs.is_player(c.id):
		return "—"
	if c.gender == p.gender:
		return "Solo parejas de distinto sexo pueden tener hijos biológicos (puedes adoptar)"
	if c.age_years(gs.today()) < 18:
		return "Es menor de edad"
	if c.spouse_id >= 0:
		return "Está casado(a)"
	if p.spouse_id >= 0:
		return "Ya estás casado(a)"
	if _is_related(p, c):
		return "Es tu familiar"
	return ""


static func date(gs, c: Citizen) -> String:
	var r := can_court(gs, c)
	if r == "":
		r = can_talk(gs, c)
	if r != "":
		return r
	if affinity(gs, c.id) < float(cfg().get("date_min_affinity", 20)):
		return "Primero conózcanse mejor (relación %d/%d)" % [int(affinity(gs, c.id)), int(cfg().get("date_min_affinity", 20))]
	var cost: float = float(cfg().get("date_cost", 5)) * gs.price_mult()
	if gs.money < cost:
		return "No tienes dinero para la cita"
	gs.add_money(-cost)
	gs.player["talked"][str(c.id)] = gs.today()
	var g: Array = cfg().get("date_gain", [8, 15])
	var v := _add_affinity(gs, c.id, gs.rng.randf_range(float(g[0]), float(g[1])))
	return "Cita con %s. Relación: %d/100." % [c.first_name, int(v)]


static func propose(gs, c: Citizen) -> String:
	var r := can_court(gs, c)
	if r != "":
		return r
	var a := affinity(gs, c.id)
	var need := float(cfg().get("propose_min_affinity", 75))
	if a < need:
		return "Aún no es el momento (relación %d/%d)" % [int(a), int(need)]
	var chance := clampf((a - 50.0) / 50.0, 0.2, 0.95)
	if gs.rng.randf() > chance:
		_add_affinity(gs, c.id, -10.0)
		return "%s dijo que todavía no. Sigue intentándolo." % c.first_name
	var p: Citizen = gs.player_citizen()
	PopulationSim.marry(p, c)
	c.home_id = p.home_id
	if c.job_kind == "obra":
		c.job_id = -1
		c.job_kind = ""
	gs.count("marriages")
	gs.notify("¡Te casaste con %s!" % c.full_name(), "familia")
	EventBus.citizens_moved.emit()
	return "¡%s aceptó! Ahora viven juntos." % c.first_name


# --- Familia y hogar --------------------------------------------------------------------

static func player_home(gs) -> Dictionary:
	var p: Citizen = gs.player_citizen()
	return gs.get_building(p.home_id) if p != null else {}


static func try_child(gs) -> String:
	var p: Citizen = gs.player_citizen()
	if p.spouse_id < 0 or not gs.citizens.has(p.spouse_id):
		return "Necesitas pareja (o puedes adoptar)"
	var s: Citizen = gs.citizens[p.spouse_id]
	if s.home_id != p.home_id:
		return "Deben vivir en la misma casa"
	var mother: Citizen = p if p.gender == "F" else s
	var age: int = mother.age_years(gs.today())
	if age > int(GameData.citizens.get("fertile_max_age", 44)):
		return "Ya no es posible por edad. Pueden adoptar."
	gs.player["family_planning"] = true
	gs.player["try_child_until"] = gs.today() + int(cfg().get("try_child_days", 30))
	return "Están buscando un bebé. Más probabilidad durante %d días." % int(cfg().get("try_child_days", 30))


static func invite_to_live(gs, c: Citizen) -> String:
	var p: Citizen = gs.player_citizen()
	var home := player_home(gs)
	if home.is_empty():
		return "No tienes casa"
	if c.home_id == p.home_id:
		return "Ya vive contigo"
	var family: bool = p.spouse_id == c.id or p.children_ids.has(c.id) or p.parent_ids.has(c.id)
	if not family and affinity(gs, c.id) < float(cfg().get("invite_min_affinity", 50)):
		return "No tienen suficiente confianza (relación %d/%d)" % [int(affinity(gs, c.id)), int(cfg().get("invite_min_affinity", 50))]
	if gs.residents_of(int(home["id"])).size() >= gs.building_capacity(home):
		return "Tu casa está llena (%d personas). Mejórala o múdate." % gs.building_capacity(home)
	c.home_id = int(home["id"])
	c.unpaid_days = 0
	gs.notify("%s se mudó a tu casa." % c.full_name(), "familia")
	EventBus.citizens_moved.emit()
	return "%s ahora vive contigo." % c.first_name


static func ask_to_leave(gs, c: Citizen) -> String:
	var p: Citizen = gs.player_citizen()
	if c.home_id != p.home_id or gs.is_player(c.id):
		return "No vive contigo"
	if p.spouse_id == c.id:
		return "Es tu cónyuge"
	if p.children_ids.has(c.id) and c.age_years(gs.today()) < int(GameData.citizens.get("adult_age", 16)):
		return "Es tu hijo(a) menor de edad"
	c.home_id = -1
	_add_affinity(gs, c.id, -15.0)
	EventBus.citizens_moved.emit()
	return "%s se fue de tu casa." % c.first_name


static func _adopt(gs, child: Citizen) -> void:
	var p: Citizen = gs.player_citizen()
	var spouse: Citizen = gs.citizens.get(p.spouse_id) if p.spouse_id >= 0 else null
	var father := p if p.gender == "M" else spouse
	var mother := p if p.gender == "F" else spouse
	PopulationSim.link_parents(child, father, mother)
	child.home_id = p.home_id
	child.last_name = p.last_name


static func can_adopt_orphan(gs, c: Citizen) -> String:
	if c.age_years(gs.today()) >= int(GameData.citizens.get("adult_age", 16)):
		return "Solo se adoptan menores"
	for pid in c.parent_ids:
		if gs.citizens.has(pid):
			return "Tiene padres vivos"
	return ""


static func adopt_orphan(gs, c: Citizen) -> String:
	var r := can_adopt_orphan(gs, c)
	if r != "":
		return r
	var fee: float = float(cfg().get("adopt_orphan_fee", 100)) * gs.price_mult()
	if gs.money < fee:
		return "Necesitas %s" % Fmt.money(fee)
	gs.add_money(-fee)
	_adopt(gs, c)
	gs.notify("Adoptaste a %s." % c.full_name(), "familia")
	EventBus.citizens_moved.emit()
	return "Adoptaste a %s." % c.first_name


static func adopt_baby(gs) -> String:
	var fee: float = float(cfg().get("adopt_baby_fee", 400)) * gs.price_mult()
	if gs.money < fee:
		return "Necesitas %s" % Fmt.money(fee)
	var p: Citizen = gs.player_citizen()
	gs.add_money(-fee)
	var baby := PopulationSim.create_citizen(gs, "M" if gs.rng.randf() < 0.5 else "F", 0, p.last_name)
	baby.birth_day = gs.today() - gs.rng.randi_range(0, 200)
	baby.health = 95.0
	baby.happiness = 70.0
	_adopt(gs, baby)
	gs.count("births")
	gs.notify("Adoptaste un bebé de otro pueblo: %s." % baby.full_name(), "familia")
	EventBus.citizen_born.emit(baby.id)
	return "Bienvenido(a) %s a la familia." % baby.first_name


static func visit_doctor(gs) -> String:
	var fee: float = float(cfg().get("doctor_fee", 30)) * gs.price_mult()
	if gs.money < fee:
		return "Necesitas %s" % Fmt.money(fee)
	gs.add_money(-fee)
	gs.player["doctor_until"] = gs.today() + int(cfg().get("doctor_days", 10))
	var p: Citizen = gs.player_citizen()
	p.health = minf(100.0, p.health + 5.0)
	return "El médico te atendió: mejor recuperación durante %d días." % int(cfg().get("doctor_days", 10))


static func move_home(gs, b: Dictionary) -> String:
	if not gs.owned_by_player(b) or not Housing.is_home(b) or b["status"] == "construccion":
		return "Solo puedes vivir en una vivienda tuya terminada"
	var p: Citizen = gs.player_citizen()
	var old := p.home_id
	var family := [p]
	for c in gs.citizens.values():
		if c.home_id == old and c.id != p.id and (c.id == p.spouse_id or p.children_ids.has(c.id)):
			family.append(c)
	var others := 0
	for c in gs.residents_of(int(b["id"])):
		if not family.has(c):
			others += 1
	if others + family.size() > gs.building_capacity(b):
		return "No caben (%d lugares)" % gs.building_capacity(b)
	for c in family:
		c.home_id = int(b["id"])
	b["for_sale"] = false
	gs.notify("Te mudaste a %s." % gs.building_label(b), "familia")
	EventBus.citizens_moved.emit()
	return ""


static func heir_candidates(gs) -> Array:
	var p: Citizen = gs.player_citizen()
	var out := []
	if p == null:
		return out
	for id in p.children_ids:
		if gs.citizens.has(id):
			out.append(gs.citizens[id])
	out.sort_custom(func(a, b): return a.birth_day < b.birth_day)
	return out


# --- Ciclos ------------------------------------------------------------------------------

static func daily(gs) -> void:
	var p: Citizen = gs.player_citizen()
	if p == null:
		return
	if p.needs_met < 0.99 and gs.today() % 15 == 0:
		gs.notify("No te alcanza el dinero para tus necesidades: tu salud se deteriora. ¡Abre negocios rentables!", "jugador")
	if p.sick and int(gs.player.get("doctor_until", -1)) >= gs.today():
		if gs.rng.randf() < float(cfg().get("doctor_recover_bonus", 0.25)):
			p.sick = false
			gs.notify("Te recuperaste de tu enfermedad.", "jugador")


static func monthly(gs) -> void:
	var rel: Dictionary = gs.player.get("relations", {})
	var decay := float(cfg().get("affinity_monthly_decay", 1))
	for k in rel.keys():
		if not gs.citizens.has(int(k)):
			rel.erase(k)
		else:
			rel[k] = maxf(0.0, float(rel[k]) - decay)
	gs.player["talked"] = {}
	DynastySim.monthly(gs)


## Llamado cuando muere el personaje. Pasa el control al heredero o termina la partida.
static func on_player_death(gs, dead: Citizen) -> void:
	var heirs := []
	for id in dead.children_ids:
		if gs.citizens.has(id):
			heirs.append(gs.citizens[id])
	if heirs.is_empty():
		DynastySim.on_dynasty_end(gs, dead)
		gs.running = false
		gs.notify("Has muerto sin herederos. Fin de la dinastía.", "jugador")
		EventBus.player_died.emit()
		return
	var chosen: Citizen = null
	var designated := int(gs.player.get("heir_id", -1))
	for h in heirs:
		if h.id == designated:
			chosen = h
	if chosen == null:
		heirs.sort_custom(func(a, b): return a.birth_day < b.birth_day)
		chosen = heirs[0]
	gs.player_id = chosen.id
	gs.player["relations"] = {}
	gs.player["talked"] = {}
	gs.player["heir_id"] = -1
	gs.player["try_child_until"] = -1
	if chosen.job_id >= 0:
		chosen.job_id = -1
		chosen.job_kind = ""
		chosen.wage = 0.0
	# El heredero hereda empresas, dinero y deudas (los préstamos del jugador siguen a su nombre),
	# y paga el impuesto a la herencia (Fase 8).
	gs.money += chosen.money
	chosen.money = 0.0
	var inheritance := DynastySim.on_succession(gs, dead, chosen)
	gs.notify("%s murió. Tu heredero(a) %s (%d años) toma el control de la familia. %s" % [dead.full_name(), chosen.full_name(), chosen.age_years(gs.today()), inheritance], "jugador")
	EventBus.player_changed.emit()
