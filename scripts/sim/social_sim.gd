class_name SocialSim
extends RefCounted
## Vida social del jugador (docs/SOCIAL.md): emociones y personalidad de cada persona, saludos,
## conversaciones con varias respuestas y memoria, favores, ofertas de trabajo, visitas a casa,
## regalos y el dispositivo de la época (carta → telégrafo → teléfono → celular) con contactos,
## mensajes que tardan en llegar y chat. Parámetros en data/social.json.
##
## Estado en GameState.player["social"] (todo con valores por defecto para partidas antiguas):
##   contacts {id: {met, last, greet, gift, mem[{d,k,o,t}], emo{alegria,enojo,tristeza,confianza}, owed}}
##   inbox [{id, from, kind, text, day, read, offer{}}], outbox [{to, kind, topic, sent, arrive}],
##   chats {id: [{d, me, t}]}, next_msg, last_note, last_offer, convo{cid, turns, used[]}
## La relación (0-100) sigue siendo la de siempre: GameState.player["relations"] (PlayerSim.affinity).
## Moderado: a lo sumo un aviso social cada `notify_every_days` días; el resto queda en el buzón.
## Todo gasto va a un bolsillo del pueblo: correo y telégrafo al tesoro, cenas y regalos a
## proveedores locales (FlowSim.pay_local). No se crea ni se destruye dinero.

const EMOTIONS := ["alegria", "enojo", "tristeza", "confianza"]
const TRAITS := ["sociable", "ambicioso", "orgulloso", "sensible"]
const DEVICE_ORDER := ["celular", "telefono", "telegrafo", "carta"]
const MEM_MAX := 8

const LINES := {
	"familia": {"ok": ["Mi familia está bien, gracias por preguntar. %s", "¡Qué amable! %s", "Los míos están sanos, gracias a Dios. %s"],
		"fail": ["Prefiero no hablar de mi familia.", "Eso es asunto mío, si me disculpa."]},
	"trabajo": {"ok": ["%s", "Ahí vamos. %s"], "fail": ["No quiero aburrirle con eso."]},
	"negocios": {"ok": ["¡Me encanta hablar de negocios! %s", "Usted sí sabe de esto. %s"],
		"fail": ["De negocios no entiendo mucho, la verdad.", "Siempre hablando de dinero…"]},
	"broma": {"ok": ["¡Ja, ja! Hacía tiempo que no me reía así.", "¡Qué ocurrencia! Usted es muy gracioso(a)."],
		"fail": ["No le veo la gracia.", "Hmm… no sé si eso fue un chiste."], "offended": ["¿Se está burlando de mí?"]},
	"pueblo": {"ok": ["%s", "Sí, todo el mundo comenta. %s"], "fail": ["No me gusta el chisme."]},
	"consejo": {"ok": ["Si quiere mi consejo: %s", "Le diré lo que pienso: %s"], "fail": ["No sé qué decirle, de verdad."]},
	"consolar": {"ok": ["Gracias… necesitaba oír eso.", "Me hace bien hablar con usted."],
		"fail": ["Estoy bien, no se preocupe.", "No necesito que me consuelen."]},
	"calmar": {"ok": ["Perdone, es que %s. Ya me siento mejor.", "Gracias por escucharme: %s."],
		"fail": ["¡Déjeme en paz!", "No es asunto suyo."]},
	"despedir": ["Que le vaya bien.", "Hasta pronto.", "Cuídese mucho."],
}


static func cfg() -> Dictionary:
	return GameData.extra("social")


static func ccfg() -> Dictionary:
	return cfg().get("conversation", {})


# --- Estado ----------------------------------------------------------------------------------------

static func state(gs) -> Dictionary:
	var s: Dictionary = gs.player.get("social", {}) if gs.player.get("social", {}) is Dictionary else {}
	for k in ["contacts", "chats", "convo"]:
		if not (s.get(k) is Dictionary):
			s[k] = {}
	for k in ["inbox", "outbox"]:
		if not (s.get(k) is Array):
			s[k] = []
	for k in ["next_msg", "last_note", "last_offer"]:
		s[k] = int(s.get(k, 1 if k == "next_msg" else -100000))
	gs.player["social"] = s
	return s


## Ficha social de una persona (se crea al primer trato).
static func contact(gs, id: int, create := true) -> Dictionary:
	var cs: Dictionary = state(gs)["contacts"]
	var key := str(id)
	if not cs.has(key):
		if not create:
			return {}
		cs[key] = {"met": gs.today(), "last": gs.today(), "greet": -1, "gift": -100000, "mem": [], "emo": {}, "owed": 0}
	var ct: Dictionary = cs[key]
	if not (ct.get("mem") is Array):
		ct["mem"] = []
	if not (ct.get("emo") is Dictionary):
		ct["emo"] = {}
	ct["owed"] = int(ct.get("owed", 0))
	return ct


static func _cit(gs, id: int) -> Citizen:
	return gs.citizens.get(id) if gs.citizens.has(id) else null


static func _adult(gs, c: Citizen) -> bool:
	return c.age_years(gs.today()) >= int(GameData.citizens.get("adult_age", 16))


static func _pick(gs, arr: Array) -> String:
	return str(arr[gs.rng.randi() % arr.size()]) if not arr.is_empty() else ""


static func _add_aff(gs, c: Citizen, amount: float) -> float:
	contact(gs, c.id)["last"] = gs.today()
	return PlayerSim._add_affinity(gs, c.id, amount)


# --- Personalidad y emociones ------------------------------------------------------------------------

## Rasgos de personalidad (0-1), fijos para cada persona (salen de su semilla).
static func traits(c: Citizen) -> Dictionary:
	var out := {}
	for t in TRAITS:
		out[t] = float(absi(hash("%d:rasgo:%s" % [c.visual_seed, t])) % 101) / 100.0
	return out


static func main_trait(c: Citizen) -> String:
	var tr := traits(c)
	var best: String = TRAITS[0]
	for t in TRAITS:
		if float(tr[t]) > float(tr[best]):
			best = t
	return best


static func trait_label(t: String) -> String:
	return str(cfg().get("traits", {}).get("labels", {}).get(t, t.capitalize()))


static func trait_likes(t: String) -> String:
	return str(cfg().get("traits", {}).get("likes", {}).get(t, ""))


static func emotion_label(e: String) -> String:
	return str(cfg().get("emotions", {}).get("labels", {}).get(e, e.capitalize()))


## Emociones (0-100): una base que sale de su vida (felicidad, salud, trabajo, deudas) más lo que
## dejaron tus interacciones (se desvanece con los meses).
static func emotions(gs, c: Citizen) -> Dictionary:
	var me: bool = gs.is_player(c.id)
	var aff := 70.0 if me else PlayerSim.affinity(gs, c.id)
	var age: int = c.age_years(gs.today())
	var unemployed: bool = not me and _adult(gs, c) and age < int(GameData.citizens.get("retirement_age", 65)) and c.job_id < 0
	var ct: Dictionary = {} if me else contact(gs, c.id, false)
	var owed := int(ct.get("owed", 0))
	var e := {
		"alegria": c.happiness * 0.75 + c.needs_met * 15.0 - (15.0 if c.sick else 0.0),
		"tristeza": (100.0 - c.happiness) * 0.55 + (20.0 if c.sick else 0.0) + (12.0 if unemployed else 0.0) + (10.0 if c.needs_met < 0.6 else 0.0),
		"enojo": maxf(0.0, 55.0 - c.happiness) * 0.6 + (15.0 if c.unpaid_days > 0 else 0.0) + (25.0 if c.prison_until >= 0 else 0.0),
		"confianza": 15.0 + aff * 0.75 + owed * 4.0,
	}
	var off: Dictionary = ct.get("emo", {})
	for k in EMOTIONS:
		e[k] = snappedf(clampf(float(e[k]) + float(off.get(k, 0.0)), 0.0, 100.0), 0.1)
	return e


static func _emo_add(gs, c: Citizen, deltas: Dictionary) -> void:
	var off: Dictionary = contact(gs, c.id)["emo"]
	for k in deltas:
		off[k] = clampf(float(off.get(k, 0.0)) + float(deltas[k]), -60.0, 60.0)


## Ánimo dominante: {id, label}. Si ninguna emoción pasa el umbral, está tranquilo(a).
static func mood(gs, c: Citizen) -> Dictionary:
	var e := emotions(gs, c)
	var best := "alegria"
	for k in ["alegria", "enojo", "tristeza"]:
		if float(e[k]) > float(e[best]):
			best = k
	var f := c.gender == "F"
	if float(e[best]) < float(cfg().get("emotions", {}).get("calm_threshold", 55)):
		return {"id": "calma", "label": "Tranquila" if f else "Tranquilo"}
	var labels := {"alegria": "Alegre", "enojo": "Enojada" if f else "Enojado", "tristeza": "Triste"}
	return {"id": best, "label": labels[best]}


# --- Memoria -----------------------------------------------------------------------------------------

## Recuerda una interacción: k = tema, o = +1 bien / 0 neutro / −1 mal, t = texto corto.
static func remember(gs, c: Citizen, k: String, o: int, t: String) -> void:
	var ct := contact(gs, c.id)
	var mem: Array = ct["mem"]
	mem.append({"d": gs.today(), "k": k, "o": o, "t": t})
	while mem.size() > MEM_MAX:
		mem.pop_front()
	ct["last"] = gs.today()


static func memories(gs, c: Citizen) -> Array:
	return contact(gs, c.id, false).get("mem", [])


static func memory_lines(gs, c: Citizen, n := 3) -> Array:
	var out := []
	var mem := memories(gs, c)
	for i in range(mem.size() - 1, maxi(-1, mem.size() - 1 - n), -1):
		var m: Dictionary = mem[i]
		out.append("%s — %s" % [TimeManager.date_from_day(int(m.get("d", 0)), TimeManager.start_year()), str(m.get("t", ""))])
	return out


static func _recent(gs, c: Citizen, k: String) -> int:
	var n := 0
	var days := int(ccfg().get("repeat_days", 30))
	for m in memories(gs, c):
		if str(m.get("k", "")) == k and gs.today() - int(m.get("d", 0)) <= days:
			n += 1
	return n


# --- Saludar, regalar, visitas -----------------------------------------------------------------------

static func can_greet(gs, c: Citizen) -> String:
	if c == null or gs.player_citizen() == null:
		return "—"
	if gs.is_player(c.id):
		return "Eres tú"
	if c.prison_until >= 0:
		return "Está en la cárcel"
	if int(contact(gs, c.id, false).get("greet", -1)) == gs.today():
		return "Ya se saludaron hoy"
	return ""


static func greet(gs, c: Citizen) -> String:
	var r := can_greet(gs, c)
	if r != "":
		return r
	var stranger := PlayerSim.affinity(gs, c.id) <= 0.0
	var g: Array = cfg().get("greet", {}).get("stranger_gain" if stranger else "gain", [1, 3])
	var ct := contact(gs, c.id)
	ct["greet"] = gs.today()
	var m := mood(gs, c)
	var gain: float = gs.rng.randf_range(float(g[0]), float(g[1]))
	if str(m["id"]) == "enojo":
		gain *= 0.4
	var v := _add_aff(gs, c, gain)
	_emo_add(gs, c, {"alegria": 2})
	if stranger:
		remember(gs, c, "saludo", 1, "Se conocieron en la calle")
		return "Saludaste a %s y se presentaron. Relación: %d/100." % [c.first_name, int(v)]
	var reply := {"alegria": "te devuelve una gran sonrisa", "enojo": "responde de mala gana", "tristeza": "saluda con desgano", "calma": "te saluda con cortesía"}
	return "Saludaste a %s, que %s. Relación: %d/100." % [c.first_name, reply.get(str(m["id"]), "te saluda"), int(v)]


static func gift_cost(gs) -> float:
	return float(cfg().get("gift", {}).get("cost", 10.0)) * gs.price_mult()


static func can_gift(gs, c: Citizen) -> String:
	if c == null or gs.is_player(c.id):
		return "—"
	if gs.today() - int(contact(gs, c.id, false).get("gift", -100000)) < 30:
		return "Ya le hiciste un regalo este mes"
	if gs.money < gift_cost(gs):
		return "Necesitas %s" % Fmt.money(gift_cost(gs))
	return ""


## Regalo: lo compras a un proveedor del pueblo. Sube la relación y te queda debiendo un favor.
static func give_gift(gs, c: Citizen) -> String:
	var r := can_gift(gs, c)
	if r != "":
		return r
	var cost := gift_cost(gs)
	gs.add_money(-cost)
	FlowSim.pay_local(gs, cost)
	var ct := contact(gs, c.id)
	ct["gift"] = gs.today()
	ct["owed"] = mini(3, int(ct["owed"]) + 1)
	var v := _add_aff(gs, c, float(cfg().get("gift", {}).get("gain", 6.0)))
	_emo_add(gs, c, {"alegria": 10, "confianza": 4})
	remember(gs, c, "regalo", 1, "Le hiciste un regalo")
	return "%s agradece tu regalo. Relación: %d/100." % [c.first_name, int(v)]


static func visit_cost(gs) -> float:
	return float(cfg().get("visit", {}).get("cost", 4.0)) * gs.price_mult()


static func can_visit(gs, c: Citizen) -> String:
	var p: Citizen = gs.player_citizen()
	if c == null or p == null or gs.is_player(c.id):
		return "—"
	if p.home_id < 0:
		return "No tienes casa"
	if c.prison_until >= 0:
		return "Está en la cárcel"
	if c.home_id == p.home_id:
		return "Ya vive contigo"
	if PlayerSim.affinity(gs, c.id) < float(cfg().get("visit", {}).get("min_affinity", 10)) and not _is_family(gs, c):
		return "Aún no se conocen lo suficiente (salúdale o conversa primero)"
	if gs.money < visit_cost(gs):
		return "Necesitas %s para la cena" % Fmt.money(visit_cost(gs))
	return ""


static func invite_chance(gs, c: Citizen) -> float:
	var e := emotions(gs, c)
	return clampf(0.45 + PlayerSim.affinity(gs, c.id) * 0.006 + float(traits(c)["sociable"]) * 0.3 - float(e["enojo"]) * 0.004, 0.1, 0.97)


## Invitación a cenar a tu casa (en persona: la respuesta es inmediata). La cena se compra en el pueblo.
static func invite_home(gs, c: Citizen, roll := -1.0) -> String:
	var r := can_visit(gs, c)
	if r != "":
		return r
	if roll < 0.0:
		roll = gs.rng.randf()
	if roll >= invite_chance(gs, c):
		remember(gs, c, "visita", 0, "No pudo aceptar tu invitación a cenar")
		return "%s te agradece, pero hoy no puede ir. Quizá otro día." % c.first_name
	return _host_visit(gs, c)


static func _host_visit(gs, c: Citizen) -> String:
	var cost := visit_cost(gs)
	if gs.money < cost:
		return "No te alcanzó para la cena con %s." % c.first_name
	gs.add_money(-cost)
	FlowSim.pay_local(gs, cost)   # Comida y bebida de los proveedores del pueblo.
	var g: Array = cfg().get("visit", {}).get("gain", [6, 12])
	var v := _add_aff(gs, c, gs.rng.randf_range(float(g[0]), float(g[1])))
	_emo_add(gs, c, {"alegria": 8, "confianza": 6})
	remember(gs, c, "visita", 1, "Cenó en tu casa")
	return "%s cenó en tu casa. Relación: %d/100." % [c.first_name, int(v)]


static func _is_family(gs, c: Citizen) -> bool:
	return HeirsSim.family_members(gs).has(c)


# --- Conversación -------------------------------------------------------------------------------------

## Empieza una conversación (una por persona y día, como "Conversar"). Devuelve
## {ok, error, line, options[{id,label}], mood}.
static func start_conversation(gs, c: Citizen) -> Dictionary:
	var r := PlayerSim.can_talk(gs, c)
	if r == "" and c.prison_until >= 0:
		r = "Está en la cárcel"
	if r != "":
		return {"ok": false, "error": r}
	gs.player["talked"][str(c.id)] = gs.today()
	var st := state(gs)
	st["convo"] = {"cid": c.id, "turns": int(ccfg().get("turns", 3)), "used": []}
	contact(gs, c.id)
	return {"ok": true, "error": "", "line": _opening(gs, c), "options": _options(gs, c), "mood": mood(gs, c)}


static func _opening(gs, c: Citizen) -> String:
	var mem := memories(gs, c)
	var m := mood(gs, c)
	var aff := PlayerSim.affinity(gs, c.id)
	var s := ""
	if mem.is_empty() or aff <= 0.0:
		s = "Buenas. Creo que no nos conocemos: soy %s." % c.full_name()
	else:
		var last: Dictionary = mem[mem.size() - 1]
		var o := int(last.get("o", 0))
		var t := str(last.get("t", "")).to_lower()
		if o > 0:
			s = "¡Qué gusto verle otra vez! Todavía me acuerdo: %s." % t
		elif o < 0:
			s = "Ah, es usted… No he olvidado que %s." % t
		else:
			s = "Hola de nuevo. ¿Cómo ha estado?"
	match str(m["id"]):
		"alegria":
			s += " ¡Hoy es un buen día!"
		"enojo":
			s += " Disculpe si estoy de mal humor."
		"tristeza":
			s += " Ando un poco decaído(a)…"
	return s


static func _convo(gs, c: Citizen) -> Dictionary:
	var cv: Dictionary = state(gs)["convo"]
	if int(cv.get("cid", -1)) != c.id:
		return {}
	return cv


static func _options(gs, c: Citizen) -> Array:
	var cv := _convo(gs, c)
	var used: Array = cv.get("used", [])
	var e := emotions(gs, c)
	var topics: Dictionary = ccfg().get("topics", {})
	var out := []
	var add := func(id: String):
		if not used.has(id) and topics.has(id):
			out.append({"id": id, "label": str(topics[id].get("label", id))})
	if float(e["tristeza"]) >= 50.0:
		add.call("consolar")
	if float(e["enojo"]) >= 45.0:
		add.call("calmar")
	var pool := ["familia", "trabajo", "negocios", "broma", "pueblo", "consejo"]
	var start: int = (gs.today() + c.id) % pool.size()
	var n := 0
	for i in range(pool.size()):
		if n >= 3:
			break
		var id: String = pool[(start + i) % pool.size()]
		if not used.has(id):
			add.call(id)
			n += 1
	if PlayerSim.affinity(gs, c.id) >= float(cfg().get("favors", {}).get("min_affinity", 40)):
		add.call("favor")
	out.append({"id": "despedir", "label": "Despedirse"})
	return out


static func _success_chance(gs, c: Citizen, topic: String) -> float:
	var t: Dictionary = ccfg().get("topics", {}).get(topic, {})
	var tr := traits(c)
	var e := emotions(gs, c)
	var p := float(ccfg().get("base_success", 0.55))
	var trait_id := str(t.get("trait", ""))
	if trait_id != "":
		p += (float(tr.get(trait_id, 0.5)) - 0.5) * 0.5
	p += PlayerSim.affinity(gs, c.id) * 0.002 + (float(e["alegria"]) - 50.0) * 0.003
	if float(e["enojo"]) > 30.0:
		p -= (float(e["enojo"]) - 30.0) * 0.004
	p -= _recent(gs, c, topic) * 0.2
	match topic:
		"consolar":
			if float(e["tristeza"]) < 35.0:
				p -= 0.3
		"negocios":
			if _owns_npc(gs, c):
				p += 0.1
		"calmar":
			p += 0.1
	return clampf(p, 0.05, 0.95)


static func _owns_npc(gs, c: Citizen) -> bool:
	return not MarriageSim.businesses_of(gs, c).is_empty()


## Elige una respuesta. Devuelve {line, effect, options, ended, action}. `action` le dice a la
## interfaz si debe abrir algo ("job": ofrecer trabajo, "partner": proponer sociedad).
static func choose(gs, c: Citizen, opt: String, roll := -1.0) -> Dictionary:
	var cv := _convo(gs, c)
	if cv.is_empty():
		return {"line": "", "effect": "La conversación terminó.", "options": [], "ended": true, "action": ""}
	if roll < 0.0:
		roll = gs.rng.randf()
	if opt == "despedir":
		state(gs)["convo"] = {}
		return {"line": _pick(gs, LINES["despedir"]), "effect": "", "options": [], "ended": true, "action": ""}
	if opt.begins_with("favor_"):
		return _favor(gs, c, opt, roll)
	if opt == "ofrecer_trabajo":
		return _end_or_continue(gs, c, {"line": "¿De verdad? Cuénteme.", "effect": "", "action": "job"})
	if opt == "proponer_sociedad":
		return _end_or_continue(gs, c, {"line": "Me interesa. ¿Qué tiene en mente?", "effect": "", "action": "partner"})
	if opt == "cambiar":
		return _end_or_continue(gs, c, {"line": "Bueno, hablemos de otra cosa.", "effect": "", "action": ""}, false)
	var topics: Dictionary = ccfg().get("topics", {})
	if not topics.has(opt):
		return {"line": "", "effect": "", "options": _options(gs, c), "ended": false, "action": ""}
	var used: Array = cv["used"]
	used.append(opt)
	if opt == "favor":
		cv["turns"] = int(cv["turns"]) - 1
		return {"line": "Dígame, ¿en qué le puedo ayudar?", "effect": "", "ended": false, "action": "",
			"options": [{"id": "favor_contacto", "label": "Que te presente a alguien de confianza"},
				{"id": "favor_dato", "label": "Que te cuente qué se está vendiendo bien"},
				{"id": "favor_trabajador", "label": "Que te recomiende a un buen trabajador"},
				{"id": "cambiar", "label": "Mejor no, olvídelo"}]}
	var t: Dictionary = topics[opt]
	var tr := traits(c)
	var rep := _recent(gs, c, opt)
	var ok := roll < _success_chance(gs, c, opt)
	var res := {"line": "", "effect": "", "action": ""}
	var follow := []
	if ok:
		var gain := float(t.get("gain", 3.0)) * (1.0 + float(tr.get(str(t.get("trait", "")), 0.5)) * 0.5)
		if rep > 0:
			gain *= 0.5
		var v := _add_aff(gs, c, gain)
		_emo_add(gs, c, t.get("emo", {}))
		res["line"] = _ok_line(gs, c, opt, follow)
		res["effect"] = "Relación %+.0f → %d/100" % [gain, int(v)]
		if opt == "consolar":
			contact(gs, c.id)["owed"] = mini(3, int(contact(gs, c.id)["owed"]) + 1)
			res["effect"] += " · te tiene gratitud"
		remember(gs, c, opt, 1, _mem_text(opt, true))
	else:
		var offended := opt == "broma" and float(tr["orgulloso"]) > 0.7
		var loss := 4.0 if offended else 1.5
		var v2 := _add_aff(gs, c, -loss)
		_emo_add(gs, c, {"enojo": 10 if offended else 5})
		res["line"] = _pick(gs, LINES[opt]["offended"] if offended else LINES[opt]["fail"])
		if rep > 0:
			res["line"] += " Ya hablamos de eso hace poco."
		res["effect"] = "Relación −%.0f → %d/100" % [loss, int(v2)]
		remember(gs, c, opt, -1, _mem_text(opt, false))
	cv["turns"] = int(cv["turns"]) - 1
	if not follow.is_empty():
		res["options"] = follow + [{"id": "cambiar", "label": "Cambiar de tema"}]
		res["ended"] = false
		return res
	return _end_or_continue(gs, c, res, false)


static func _end_or_continue(gs, c: Citizen, res: Dictionary, spend_turn := true) -> Dictionary:
	var cv := _convo(gs, c)
	if spend_turn and not cv.is_empty():
		cv["turns"] = int(cv["turns"]) - 1
	if cv.is_empty() or int(cv.get("turns", 0)) <= 0 or res.get("action", "") != "":
		state(gs)["convo"] = {}
		res["options"] = []
		res["ended"] = true
		if res.get("action", "") == "":
			res["line"] = str(res.get("line", "")) + " Bueno, me tengo que ir. " + _pick(gs, LINES["despedir"])
		return res
	res["options"] = _options(gs, c)
	res["ended"] = false
	return res


static func _mem_text(topic: String, ok: bool) -> String:
	var good := {"familia": "Le preguntaste por su familia", "trabajo": "Le preguntaste por su trabajo", "negocios": "Hablaron de negocios",
		"broma": "Le hiciste reír", "pueblo": "Comentaron las noticias del pueblo", "consejo": "Le pediste su consejo",
		"consolar": "Le diste ánimos cuando estaba triste", "calmar": "Le escuchaste cuando estaba enojado(a)"}
	var bad := {"familia": "Le incomodaste preguntando por su familia", "trabajo": "No quiso hablar de su trabajo", "negocios": "Le aburriste hablando de dinero",
		"broma": "Tu chiste no le gustó", "pueblo": "No quiso chismear", "consejo": "No supo aconsejarte",
		"consolar": "No quiso tu consuelo", "calmar": "Discutieron"}
	return str((good if ok else bad).get(topic, topic))


static func _ok_line(gs, c: Citizen, topic: String, follow: Array) -> String:
	var extra := ""
	match topic:
		"familia":
			var kids := c.children_ids.filter(func(id): return gs.citizens.has(id)).size()
			if c.spouse_id >= 0 and gs.citizens.has(c.spouse_id):
				extra = "%s y yo estamos bien%s." % [gs.citizens[c.spouse_id].first_name, " con nuestros %d hijos" % kids if kids > 0 else ""]
			elif kids > 0:
				extra = "Mis %d hijos me dan mucha alegría." % kids
			else:
				extra = "Vivo solo(a), pero no me quejo."
		"trabajo":
			if c.job_kind == "dueño":
				extra = "Atiendo mi propio negocio; es duro pero es mío."
			elif c.job_id >= 0:
				extra = "Trabajo en %s y gano %s al día." % [gs.building_label(gs.get_building(c.job_id)), Fmt.money2(c.wage)]
			elif _adult(gs, c) and c.age_years(gs.today()) < int(GameData.citizens.get("retirement_age", 65)):
				extra = "La verdad, ando sin trabajo y me vendría bien uno."
				if not vacancies(gs).is_empty():
					follow.append({"id": "ofrecer_trabajo", "label": "Ofrecerle trabajo en uno de tus negocios"})
				if not _convo(gs, c).get("used", []).has("consolar"):
					follow.append({"id": "consolar", "label": "Darle ánimos"})
			else:
				extra = "Ya no trabajo; ahora me toca descansar."
		"negocios":
			extra = "Creo que %s" % _market_tip(gs)
			if (c.money >= 150.0 * gs.price_mult() or float(traits(c)["ambicioso"]) > 0.6) and _adult(gs, c) and not PartnersSim.eligible_businesses(gs).is_empty():
				follow.append({"id": "proponer_sociedad", "label": "Proponerle ser socio(a) de una empresa"})
		"pueblo":
			var un := EconomySim.unemployment(gs)
			extra = "Dicen que %d de cada 10 vecinos no tienen trabajo fijo, y que %s" % [int(round(un * 10.0)), _market_tip(gs)]
		"consejo":
			extra = _market_tip(gs) + " Y nunca preste dinero a quien no conoce."
		"calmar":
			var e := emotions(gs, c)
			extra = "las cosas no van bien en casa" if c.unpaid_days > 0 or c.needs_met < 0.7 else ("me siento enfermo(a)" if c.sick else "tuve un mal día")
			if float(e["enojo"]) > 60.0:
				_emo_add(gs, c, {"enojo": -5})
	var tpl := _pick(gs, LINES[topic]["ok"])
	return tpl % extra if tpl.contains("%s") else tpl


## Dato de mercado: el bien que hoy se vende más caro respecto a su precio normal.
static func _market_tip(gs) -> String:
	var best := ""
	var best_r := 0.0
	for g in GameData.goods:
		var gd: Dictionary = GameData.goods[g]
		if float(gd.get("base_price", 0.0)) <= 0.0 or int(gd.get("era", 1)) > gs.era():
			continue
		var r := EconomySim.good_factor(gs, str(g)) * EconomySim.fluct(gs, str(g))
		if r > best_r:
			best_r = r
			best = str(g)
	if best == "":
		return "el comercio anda tranquilo."
	return "%s se está vendiendo caro (%s, ×%.2f de lo normal)." % [GameData.good_label(best), Fmt.money2(EconomySim.market_price(gs, best)), best_r]


static func favor_chance(gs, c: Citizen) -> float:
	var ct := contact(gs, c.id, false)
	if int(ct.get("owed", 0)) > 0:
		return 0.95
	var e := emotions(gs, c)
	return clampf(0.3 + PlayerSim.affinity(gs, c.id) * 0.006 + float(e["confianza"]) * 0.003 - float(traits(c)["orgulloso"]) * 0.15, 0.05, 0.9)


static func _favor(gs, c: Citizen, opt: String, roll: float) -> Dictionary:
	var ct := contact(gs, c.id)
	var owed := int(ct["owed"]) > 0
	if roll >= favor_chance(gs, c):
		var v := _add_aff(gs, c, -3.0)
		remember(gs, c, "favor", -1, "Le pediste un favor y se negó")
		return _end_or_continue(gs, c, {"line": "Lo siento, eso no puedo hacerlo.", "effect": "Relación −3 → %d/100" % int(v), "action": ""}, false)
	if owed:
		ct["owed"] = int(ct["owed"]) - 1
	else:
		_emo_add(gs, c, {"confianza": -float(cfg().get("favors", {}).get("trust_cost", 8.0))})
	var res := {"line": "", "effect": "", "action": ""}
	match opt:
		"favor_contacto":
			var who := introduce(gs, c)
			if who == null:
				res["line"] = "Quisiera, pero ya conoce a toda la gente que yo conozco."
			else:
				res["line"] = "Le presentaré a %s; es de mi entera confianza." % who.full_name()
				res["effect"] = "Nuevo contacto: %s" % who.full_name()
		"favor_dato":
			res["line"] = "Se lo digo solo a usted: " + _market_tip(gs)
		"favor_trabajador":
			var best := _best_worker(gs, c)
			if best == null:
				res["line"] = "No conozco a nadie que esté buscando trabajo."
			else:
				res["line"] = "Hable con %s: es trabajador(a) y busca empleo (%s)." % [best.full_name(), GameData.skill_label(best.best_skill())]
				_add_aff(gs, best, 8.0)
				remember(gs, best, "presentado", 1, "%s te habló bien de él/ella" % c.first_name)
				res["effect"] = "Nuevo contacto: %s" % best.full_name()
	remember(gs, c, "favor", 1, "Te hizo un favor" + (" (te lo debía)" if owed else ""))
	if res["effect"] == "":
		res["effect"] = "Favor cumplido" + (" (te lo debía)" if owed else ": ahora confía un poco menos")
	return _end_or_continue(gs, c, res, false)


## Presentación: alguien de su familia o de su trabajo que aún no conoces bien. Sube la relación.
static func introduce(gs, c: Citizen) -> Citizen:
	var pool := []
	for id in c.children_ids + c.parent_ids + [c.spouse_id]:
		if gs.citizens.has(id):
			pool.append(gs.citizens[id])
	if c.job_id >= 0:
		for e in gs.employees_of(c.job_id):
			pool.append(e)
	var best: Citizen = null
	var best_s := -INF
	for o in pool:
		if gs.is_player(o.id) or o.id == c.id or not _adult(gs, o) or PlayerSim.affinity(gs, o.id) >= 30.0:
			continue
		var s: float = o.money + (500.0 if _owns_npc(gs, o) else 0.0) + o.education * 50.0
		if s > best_s:
			best_s = s
			best = o
	if best == null:
		for o in gs.citizens.values():
			if not gs.is_player(o.id) and o.id != c.id and _adult(gs, o) and PlayerSim.affinity(gs, o.id) < 30.0 and _owns_npc(gs, o):
				best = o
				break
	if best != null:
		_add_aff(gs, best, float(cfg().get("favors", {}).get("contact_gain", 15.0)))
		remember(gs, best, "presentado", 1, "Te lo/la presentó %s" % c.full_name())
	return best


static func _best_worker(gs, c: Citizen) -> Citizen:
	var best: Citizen = null
	var best_s := -INF
	for o in gs.citizens.values():
		if gs.is_player(o.id) or o.id == c.id or o.job_id >= 0 or not _adult(gs, o) or o.prison_until >= 0:
			continue
		if o.age_years(gs.today()) >= int(GameData.citizens.get("retirement_age", 65)):
			continue
		var sk := 0.0
		for k in o.skills:
			sk = maxf(sk, float(o.skills[k]))
		var s: float = sk + o.experience + o.education * 10.0
		if s > best_s:
			best_s = s
			best = o
	return best


# --- Ofrecer trabajo -------------------------------------------------------------------------------

## Negocios del jugador con vacantes: [{building, free}].
static func vacancies(gs) -> Array:
	var out := []
	for b in gs.buildings:
		if not gs.owned_by_player(b) or not BusinessSim.is_business(b) or str(b.get("status", "")) != "activo":
			continue
		var used := 0
		for e in gs.employees_of(int(b["id"])):
			if e.job_kind == "empleo":
				used += 1
		var free := MineSim.jobs(gs, b) - used
		if free > 0:
			out.append({"building": b, "free": free})
	return out


static func _hire_block(gs, b: Dictionary, c: Citizen, wage: float) -> String:
	if c.education < int(gs.level_def(b).get("min_education", 0)):
		return "%s no tiene la educación que pide el puesto (%s)." % [c.first_name, GameData.education_label(int(gs.level_def(b).get("min_education", 0)))]
	var prof := str(gs.level_def(b).get("required_profession", ""))
	if prof != "" and c.profession != prof:
		return "El puesto exige ser %s." % GameData.profession_label(prof).to_lower()
	if wage < GovSim.min_wage(gs):
		return "El salario mínimo legal es %s/día." % Fmt.money2(GovSim.min_wage(gs))
	return ""


static func job_chance(gs, c: Citizen, b: Dictionary, wage: float) -> float:
	var asked := BusinessSim.asked_wage(gs, c, str(b["type"]))
	var jc: Dictionary = cfg().get("job_offer", {})
	if c.job_kind == "dueño":
		return 0.0
	if c.job_kind == "empleo":
		if wage >= c.wage * float(jc.get("switch_ratio", 1.15)) or (PlayerSim.affinity(gs, c.id) >= 60.0 and wage >= c.wage):
			return clampf(0.55 + PlayerSim.affinity(gs, c.id) * 0.004, 0.0, 0.95)
		return 0.05
	return clampf(float(jc.get("accept_base", 0.45)) + (wage / maxf(0.01, asked) - 0.8) * 0.8 + PlayerSim.affinity(gs, c.id) * 0.004, 0.05, 0.97)


## Ofrecer trabajo en persona. wage < 0: el sueldo que pide.
static func offer_job(gs, c: Citizen, b: Dictionary, wage := -1.0, roll := -1.0) -> String:
	if c == null or gs.is_player(c.id) or not _adult(gs, c):
		return "No puedes ofrecerle trabajo"
	if c.job_id == int(b.get("id", -2)):
		return "%s ya trabaja ahí." % c.first_name
	if wage < 0.0:
		wage = BusinessSim.asked_wage(gs, c, str(b["type"]))
	var block := _hire_block(gs, b, c, wage)
	if block != "":
		return block
	if c.job_kind == "dueño":
		return "%s atiende su propio negocio y no quiere dejarlo." % c.first_name
	if roll < 0.0:
		roll = gs.rng.randf()
	if roll >= job_chance(gs, c, b, wage):
		_add_aff(gs, c, -1.0)
		remember(gs, c, "trabajo_oferta", 0, "Rechazó tu oferta de trabajo en %s" % gs.building_label(b))
		return "%s lo pensó y rechazó la oferta (%s/día)." % [c.first_name, Fmt.money2(wage)]
	var old_job := c.job_id
	var old_kind := c.job_kind
	if c.job_kind == "empleo":
		c.job_id = -1
		c.job_kind = ""
	var err := BusinessSim.hire(gs, b, c, wage)
	if err != "":
		c.job_id = old_job
		c.job_kind = old_kind
		return err
	if old_job >= 0 and old_kind == "empleo":
		HiringSim.note_left(gs, c, old_job, "")
	var ct := contact(gs, c.id)
	ct["owed"] = mini(3, int(ct["owed"]) + 1)
	_add_aff(gs, c, 5.0)
	_emo_add(gs, c, {"alegria": 12, "tristeza": -10, "confianza": 6})
	remember(gs, c, "trabajo_oferta", 1, "Le diste trabajo en %s" % gs.building_label(b))
	return "%s aceptó trabajar en %s (%s/día). Te queda agradecido(a)." % [c.first_name, gs.building_label(b), Fmt.money2(wage)]


# --- Dispositivo por época ----------------------------------------------------------------------

static func device_def(id: String) -> Dictionary:
	return cfg().get("devices", {}).get(id, {})


## Mejor dispositivo disponible según las tecnologías investigadas.
static func device_id(gs) -> String:
	for id in DEVICE_ORDER:
		var t := str(device_def(id).get("tech", ""))
		if t == "" or gs.has_tech(t):
			return id
	return "carta"


static func device(gs) -> Dictionary:
	var d := device_def(device_id(gs)).duplicate()
	d["id"] = device_id(gs)
	return d


static func send_cost(gs) -> float:
	return float(device(gs).get("cost", 0.5)) * gs.price_mult()


static func _delay(gs) -> int:
	var r: Array = device(gs).get("delay", [0, 0])
	return gs.rng.randi_range(int(r[0]), int(r[1]))


## Contactos: familia y toda persona viva con relación > 0. [{citizen, affinity, family}], mejor primero.
static func contacts(gs) -> Array:
	var out := []
	var seen := {}
	for m in HeirsSim.family_members(gs):
		out.append({"citizen": m, "affinity": PlayerSim.affinity(gs, m.id), "family": true})
		seen[m.id] = true
	var rel: Dictionary = gs.player.get("relations", {})
	for k in rel:
		var id := int(k)
		if seen.has(id) or float(rel[k]) <= 0.0 or not gs.citizens.has(id) or gs.is_player(id):
			continue
		out.append({"citizen": gs.citizens[id], "affinity": float(rel[k]), "family": false})
	out.sort_custom(func(a, b): return (1000.0 if a["family"] else 0.0) + float(a["affinity"]) > (1000.0 if b["family"] else 0.0) + float(b["affinity"]))
	return out


static func is_contact(gs, c: Citizen) -> bool:
	return c != null and not gs.is_player(c.id) and (PlayerSim.affinity(gs, c.id) > 0.0 or _is_family(gs, c))


static func can_send(gs, c: Citizen, kind: String) -> String:
	if c == null or gs.is_player(c.id):
		return "—"
	if not is_contact(gs, c):
		return "No es tu contacto: salúdale primero"
	var d := device(gs)
	if kind == "llamada" and not bool(d.get("call", false)):
		return "Aún no hay teléfono (época de %s)" % str(d.get("label", "")).to_lower()
	if kind == "chat" and not bool(d.get("chat", false)):
		return "El chat llega con el celular"
	if kind == "llamada" and int(gs.player.get("talked", {}).get(str(c.id), -1)) == gs.today():
		return "Ya hablaron hoy"
	if kind == "chat" and int(contact(gs, c.id, false).get("chat_day", -1)) == gs.today():
		return "Ya chatearon hoy"
	if gs.money < send_cost(gs):
		return "Necesitas %s" % Fmt.money2(send_cost(gs))
	return ""


static func _charge(gs) -> void:
	var cost := send_cost(gs)
	gs.add_money(-cost)
	GovSim.add_treasury(gs, cost)   # Correo, telégrafo y telefonía: servicio del Estado.


## Envía por el dispositivo: kind = "carta" (saludo escrito), "invitacion" (a cenar), "llamada", "chat".
## Con carta o telégrafo llega días después y la respuesta tarda otro tanto. Devuelve un texto.
static func send(gs, c: Citizen, kind: String, text := "") -> String:
	var r := can_send(gs, c, kind)
	if r == "" and kind == "invitacion":
		r = can_visit(gs, c)
	if r != "":
		return r
	_charge(gs)
	var d := device(gs)
	match kind:
		"llamada":
			gs.player["talked"][str(c.id)] = gs.today()
			var g: float = gs.rng.randf_range(2.0, 5.0) * (0.5 if str(mood(gs, c)["id"]) == "enojo" else 1.0)
			var v := _add_aff(gs, c, g)
			remember(gs, c, "llamada", 1, "Hablaron por teléfono")
			return "Llamaste a %s: %s Relación: %d/100." % [c.first_name, _phone_line(gs, c), int(v)]
		"chat":
			var ct := contact(gs, c.id)
			ct["chat_day"] = gs.today()
			_chat_add(gs, c, true, text if text != "" else "¿Cómo estás?")
			var reply := _chat_reply(gs, c, text)
			_chat_add(gs, c, false, reply)
			var v2 := _add_aff(gs, c, gs.rng.randf_range(1.0, 2.5))
			return "%s respondió: «%s» (relación %d/100)." % [c.first_name, reply, int(v2)]
	var delay := _delay(gs)
	var item := {"to": c.id, "kind": kind, "topic": text, "sent": gs.today(), "arrive": gs.today() + delay}
	if delay <= 0:
		_deliver(gs, item)
		return "Enviaste %s a %s." % ["una invitación" if kind == "invitacion" else "un mensaje", c.first_name]
	state(gs)["outbox"].append(item)
	var what := "un telegrama" if str(d.get("id", "")) == "telegrafo" else "una carta"
	if kind == "invitacion":
		what = "una invitación por " + ("telegrama" if str(d.get("id", "")) == "telegrafo" else "carta")
	return "Enviaste %s a %s: llegará en %d día(s)." % [what, c.first_name, delay]


static func _phone_line(gs, c: Citizen) -> String:
	match str(mood(gs, c)["id"]):
		"alegria":
			return "estaba de muy buen humor y charlaron largo rato."
		"enojo":
			return "estaba de mal humor y la llamada fue corta."
		"tristeza":
			return "estaba triste; le hizo bien oírte."
	return "charlaron un rato."


static func _chat_add(gs, c: Citizen, me: bool, t: String) -> void:
	var chats: Dictionary = state(gs)["chats"]
	var key := str(c.id)
	if not (chats.get(key) is Array):
		chats[key] = []
	var arr: Array = chats[key]
	arr.append({"d": gs.today(), "me": me, "t": t})
	while arr.size() > int(cfg().get("chat_max", 30)):
		arr.pop_front()


static func chat_of(gs, c: Citizen) -> Array:
	return state(gs)["chats"].get(str(c.id), [])


const CHAT_PRESETS := ["¿Cómo estás?", "¿Tomamos un café?", "Gracias por todo", "Tengo una idea de negocio"]


static func _chat_reply(gs, c: Citizen, t: String) -> String:
	var m := str(mood(gs, c)["id"])
	match t:
		"¿Tomamos un café?":
			return "¡Claro! Cuando quieras." if m != "enojo" else "Hoy no, otro día."
		"Gracias por todo":
			return "Gracias a ti, de verdad."
		"Tengo una idea de negocio":
			return "Cuéntame, me interesa." if float(traits(c)["ambicioso"]) > 0.5 else "Ah… ya me contarás en persona."
	return {"alegria": "¡Muy bien! ¿Y tú?", "enojo": "Ahí, con un día complicado.", "tristeza": "No muy bien, la verdad…"}.get(m, "Bien, gracias. ¿Y tú?")


static func _msg(gs, from_id: int, kind: String, text: String, day: int, offer := {}) -> Dictionary:
	var st := state(gs)
	var m := {"id": int(st["next_msg"]), "from": from_id, "kind": kind, "text": text, "day": day, "read": false, "offer": offer}
	st["next_msg"] = int(st["next_msg"]) + 1
	var inbox: Array = st["inbox"]
	inbox.append(m)
	while inbox.size() > int(cfg().get("inbox_max", 40)):
		inbox.pop_front()
	return m


## Llega un envío del jugador a su destinatario.
static func _deliver(gs, item: Dictionary) -> void:
	var c := _cit(gs, int(item.get("to", -1)))
	if c == null:
		return
	var back := _delay(gs)
	var dname := str(device(gs).get("label", "Carta"))
	match str(item.get("kind", "")):
		"invitacion":
			if gs.rng.randf() < invite_chance(gs, c) and can_visit(gs, c) == "":
				var txt := _host_visit(gs, c)
				_msg(gs, c.id, "visita", "%s aceptó tu invitación. %s" % [c.first_name, txt], gs.today())
			else:
				remember(gs, c, "visita", 0, "No pudo aceptar tu invitación")
				_msg(gs, c.id, dname.to_lower(), "Gracias por la invitación, pero estos días no puedo. Con cariño, %s." % c.first_name, gs.today() + back)
		_:
			var v := _add_aff(gs, c, gs.rng.randf_range(2.0, 4.0))
			remember(gs, c, "carta", 1, "Recibió tu %s" % dname.to_lower())
			var lines := {"alegria": "¡Qué alegría recibir noticias suyas!", "enojo": "Recibí su mensaje. Ando con muchos problemas, pero gracias.",
				"tristeza": "Su mensaje me alegró un día difícil.", "calma": "Gracias por acordarse de mí."}
			_msg(gs, c.id, dname.to_lower(), "%s Saludos, %s. (relación %d/100)" % [lines.get(str(mood(gs, c)["id"]), "Gracias."), c.first_name, int(v)], gs.today() + back)


static func inbox(gs) -> Array:
	var out := []
	for m in state(gs)["inbox"]:
		if int(m.get("day", 0)) <= gs.today():
			out.append(m)
	return out


static func unread_count(gs) -> int:
	var n := 0
	for m in inbox(gs):
		if not bool(m.get("read", false)):
			n += 1
	return n


static func mark_all_read(gs) -> void:
	for m in inbox(gs):
		m["read"] = true


static func pending_outbox(gs) -> Array:
	return state(gs)["outbox"]


static func _find_msg(gs, msg_id: int) -> Dictionary:
	for m in state(gs)["inbox"]:
		if int(m.get("id", -1)) == msg_id:
			return m
	return {}


## Responde a una oferta del buzón (inversión, pedido de trabajo, presentación).
static func answer_offer(gs, msg_id: int, accept: bool) -> String:
	var m := _find_msg(gs, msg_id)
	var offer: Dictionary = m.get("offer", {})
	if m.is_empty() or offer.is_empty() or bool(offer.get("done", false)):
		return "Esa oferta ya no está disponible"
	var c := _cit(gs, int(m.get("from", -1)))
	if c == null:
		offer["done"] = true
		return "Esa persona ya no vive en el pueblo"
	m["read"] = true
	if not accept:
		offer["done"] = true
		_add_aff(gs, c, -1.0)
		remember(gs, c, "oferta", 0, "Rechazaste su propuesta")
		return "Le respondiste a %s que no, gracias." % c.first_name
	var out := ""
	match str(offer.get("type", "")):
		"inversion":
			var b: Dictionary = gs.get_building(int(offer.get("bid", -1)))
			var r := PartnersSim.propose(gs, b, c, "capital", float(offer.get("capital", 0.0)), float(offer.get("share", 0.0)), 0.0)
			out = str(r.get("msg", ""))
			if not bool(r.get("ok", false)):
				return out
		"empleo":
			var vac := vacancies(gs)
			if vac.is_empty():
				return "No tienes vacantes para %s ahora." % c.first_name
			out = offer_job(gs, c, vac[0]["building"], -1.0, 0.0)
		_:
			out = "Aceptaste."
	offer["done"] = true
	return out


# --- Ciclos -------------------------------------------------------------------------------------

static func _soft_notify(gs, text: String) -> void:
	var st := state(gs)
	if gs.today() - int(st["last_note"]) < int(cfg().get("notify_every_days", 15)):
		return
	st["last_note"] = gs.today()
	gs.notify(text, "social")


static func daily(gs) -> void:
	if not gs.player.has("social"):
		return   # Nadie ha usado la vida social todavía: nada que procesar.
	var st := state(gs)
	var out: Array = st["outbox"]
	if not out.is_empty():
		var keep := []
		for item in out:
			if int(item.get("arrive", 0)) <= gs.today():
				_deliver(gs, item)
			else:
				keep.append(item)
		st["outbox"] = keep
	# Aviso moderado de lo que llegó hoy (cartas que vuelven).
	for m in st["inbox"]:
		if int(m.get("day", 0)) == gs.today() and not bool(m.get("read", false)) and not bool(m.get("noted", false)):
			m["noted"] = true
			var c := _cit(gs, int(m.get("from", -1)))
			_soft_notify(gs, "Te llegó %s de %s." % ["una respuesta" if str(m.get("kind", "")) != "oferta" else "una propuesta", c.full_name() if c != null else "un conocido"])


static func monthly(gs) -> void:
	if not gs.player.has("social"):
		return
	var st := state(gs)
	var decay := float(cfg().get("emotions", {}).get("monthly_decay", 0.4))
	var cs: Dictionary = st["contacts"]
	for k in cs.keys():
		if not gs.citizens.has(int(k)):
			cs.erase(k)
			st["chats"].erase(k)
			continue
		var off: Dictionary = cs[k].get("emo", {})
		for e in off.keys():
			off[e] = float(off[e]) * (1.0 - decay)
			if absf(float(off[e])) < 0.5:
				off.erase(e)
	_spontaneous_offer(gs)


## Rara vez, un buen contacto te escribe con una propuesta: invertir en tu empresa, pedirte
## trabajo o presentarte a alguien. A lo sumo una cada `offer_every_days` días.
static func _spontaneous_offer(gs, roll := -1.0) -> Dictionary:
	var st := state(gs)
	if gs.today() - int(st["last_offer"]) < int(cfg().get("offer_every_days", 45)):
		return {}
	if roll < 0.0:
		roll = gs.rng.randf()
	if roll >= float(cfg().get("offer_chance", 0.25)):
		return {}
	var best: Citizen = null
	for entry in contacts(gs):
		var c: Citizen = entry["citizen"]
		if entry["family"] or float(entry["affinity"]) < 60.0 or not _adult(gs, c) or c.prison_until >= 0:
			continue
		if float(emotions(gs, c)["confianza"]) < 55.0:
			continue
		best = c
		break
	if best == null:
		return {}
	st["last_offer"] = gs.today()
	var c := best
	var day: int = gs.today() + _delay(gs)
	var biz := PartnersSim.eligible_businesses(gs)
	var m := {}
	if not biz.is_empty() and c.money >= 100.0 * gs.price_mult() and float(traits(c)["ambicioso"]) >= 0.4:
		var b: Dictionary = biz[0]
		var cap := snappedf(minf(c.money * 0.5, PartnersSim.valuation(gs, b) * 0.3), 1.0)
		var share := snappedf(clampf(PartnersSim.fair_share(gs, b, cap), PartnersSim.min_share(), PartnersSim.room(gs, b)), 0.01)
		if cap > 0.0 and share >= PartnersSim.min_share():
			m = _msg(gs, c.id, "oferta", "Quisiera invertir %s en %s a cambio del %d%% de sus utilidades. ¿Qué me dice? — %s" % [Fmt.money(cap), gs.building_label(b), int(round(share * 100.0)), c.first_name], day,
				{"type": "inversion", "bid": int(b["id"]), "capital": cap, "share": share})
	if m.is_empty() and c.job_id < 0 and not vacancies(gs).is_empty():
		m = _msg(gs, c.id, "oferta", "Ando buscando trabajo y me gustaría trabajar con usted, si tiene un puesto. — %s" % c.first_name, day, {"type": "empleo"})
	if m.is_empty():
		var who := introduce(gs, c)
		if who != null:
			m = _msg(gs, c.id, "carta", "Le presento a %s, buena persona y de confianza. Ya le hablé de usted. — %s" % [who.full_name(), c.first_name], day)
	return m


## Sucesión: el heredero NO hereda las relaciones del difunto, solo las de su familia.
static func on_succession(gs, old_relations: Dictionary) -> void:
	var keep := {}
	var fam_ids := {}
	var fmin := float(cfg().get("succession_family_min", 50.0))
	for m in HeirsSim.family_members(gs):
		keep[str(m.id)] = maxf(float(old_relations.get(str(m.id), 0.0)), fmin)
		fam_ids[str(m.id)] = true
	gs.player["relations"] = keep
	if not gs.player.has("social"):
		return
	var st := state(gs)
	var cs: Dictionary = st["contacts"]
	for k in cs.keys():
		if not fam_ids.has(k):
			cs.erase(k)
	for k in st["chats"].keys():
		if not fam_ids.has(k):
			st["chats"].erase(k)
	st["inbox"] = st["inbox"].filter(func(m): return fam_ids.has(str(m.get("from", -1))))
	st["outbox"] = st["outbox"].filter(func(m): return fam_ids.has(str(m.get("to", -1))))
	st["convo"] = {}
