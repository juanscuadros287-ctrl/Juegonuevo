extends Node
## Pruebas de la vida social (docs/SOCIAL.md): socios (capital y habilidades, utilidades, comprar y
## vender participación, desacuerdos, herencia), emociones, conversaciones con memoria, favores,
## ofertas de trabajo, cenas, dispositivo por época con demoras, sucesión (solo relaciones
## familiares), avisos moderados, guardado y la interfaz.
## godot --headless res://tests/test_social.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Vida social: socios, conversaciones y dispositivo ==")
	_test_device_by_era()
	_test_greet_and_emotions()
	_test_conversation_memory()
	_test_favors_and_contacts()
	_test_job_offer_and_visit()
	_test_messages_delay()
	_test_partners_capital()
	_test_partners_skill_and_disputes()
	_test_partner_death_and_emigration()
	_test_spontaneous_offer()
	_test_succession()
	_test_moderation()
	_test_save_load()
	_test_conservation_run()
	await _test_ui()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- Utilidades -----------------------------------------------------------------------------------

func _new_town(seed_v: int) -> void:
	GameState.new_game({"seed": seed_v, "difficulty": "facil"})
	GameState.money = 20000.0


func _npc(age := 30, money := 0.0) -> Citizen:
	var c := PopulationSim.create_citizen(GameState, "M" if GameState.rng.randf() < 0.5 else "F", age, PopulationSim.random_surname(GameState))
	c.money = money
	c.prison_until = -1
	return c


func _farm(x := 60.0) -> Dictionary:
	var b: Dictionary = ConstructionSim.make_building(GameState, "granja", 1, x, 60.0, 0.0, "jugador")
	GameState.add_building(b)
	BusinessSim.ledger_add(b, "obras", 600.0)   # Lo invertido le da valor.
	return b


func _total() -> float:
	return FlowSim.conserved_total(GameState)


# --- Dispositivo por época ------------------------------------------------------------------------

func _test_device_by_era() -> void:
	_new_town(401)
	var gs = GameState
	check(SocialSim.device_id(gs) == "carta", "colonia: el dispositivo es la carta")
	gs.techs.append("telegrafo")
	check(SocialSim.device_id(gs) == "telegrafo", "con el telégrafo investigado: telégrafo")
	gs.techs.append("electricidad")
	check(SocialSim.device_id(gs) == "telefono" and bool(SocialSim.device(gs)["call"]), "con la electricidad: teléfono (permite llamar)")
	gs.techs.append("electronica")
	check(SocialSim.device_id(gs) == "celular" and bool(SocialSim.device(gs)["chat"]), "con la electrónica: celular (permite chatear)")


# --- Saludar, emociones y personalidad -------------------------------------------------------------

func _test_greet_and_emotions() -> void:
	_new_town(402)
	var gs = GameState
	var c := _npc()
	check(SocialSim.is_contact(gs, c) == false, "un desconocido no es contacto")
	var t := SocialSim.greet(gs, c)
	check(PlayerSim.affinity(gs, c.id) > 0.0 and SocialSim.is_contact(gs, c), "saludar presenta y crea el contacto: %s" % t)
	check(SocialSim.can_greet(gs, c) != "", "solo un saludo por día")
	var e := SocialSim.emotions(gs, c)
	var in_range := true
	for k in SocialSim.EMOTIONS:
		in_range = in_range and float(e[k]) >= 0.0 and float(e[k]) <= 100.0
	check(in_range and e.size() == 4, "cuatro emociones en 0-100: %s" % str(e))
	c.happiness = 15.0
	c.sick = true
	var m := SocialSim.mood(gs, c)
	check(str(m["id"]) == "tristeza" or str(m["id"]) == "enojo", "infeliz y enfermo: ánimo %s" % str(m["label"]))
	c.happiness = 95.0
	c.sick = false
	c.needs_met = 1.0
	check(str(SocialSim.mood(gs, c)["id"]) == "alegria", "feliz: ánimo alegre")
	check(SocialSim.traits(c) == SocialSim.traits(c) and SocialSim.TRAITS.has(SocialSim.main_trait(c)), "la personalidad es fija (%s)" % SocialSim.trait_label(SocialSim.main_trait(c)))
	var me: Citizen = gs.player_citizen()
	check(not SocialSim.mood(gs, me).is_empty() and SocialSim.can_greet(gs, me) == "Eres tú", "tu personaje también tiene ánimo")


# --- Conversaciones con varias respuestas y memoria ------------------------------------------------

func _test_conversation_memory() -> void:
	_new_town(403)
	var gs = GameState
	var c := _npc()
	var r := SocialSim.start_conversation(gs, c)
	check(bool(r["ok"]) and str(r["line"]).contains(c.full_name()), "primera conversación: se presenta («%s»)" % str(r.get("line", "")))
	var opts: Array = r["options"]
	check(opts.size() >= 3 and opts[opts.size() - 1]["id"] == "despedir", "varias respuestas posibles (%d) y despedirse" % opts.size())
	var a0 := PlayerSim.affinity(gs, c.id)
	var first := str(opts[0]["id"])
	var res := SocialSim.choose(gs, c, first, 0.0)
	check(PlayerSim.affinity(gs, c.id) > a0 and str(res["effect"]).begins_with("Relación +"), "una buena respuesta sube la relación (%s: %s)" % [first, str(res["effect"])])
	check(SocialSim.memories(gs, c).size() == 1 and int(SocialSim.memories(gs, c)[0]["o"]) == 1, "la conversación queda en su memoria")
	check(not SocialSim.start_conversation(gs, c)["ok"], "una conversación por persona y día")
	# Termina tras pocas respuestas.
	var guard := 0
	while not bool(res.get("ended", false)) and guard < 6:
		var o: Array = res["options"]
		res = SocialSim.choose(gs, c, str(o[0]["id"]) if str(o[0]["id"]) != "favor" else "despedir", 0.0)
		guard += 1
	check(bool(res["ended"]), "la conversación termina sola (%d respuestas más)" % guard)
	# Al día siguiente recuerda lo anterior.
	TimeManager.advance_days(1)
	var r2 := SocialSim.start_conversation(gs, c)
	check(bool(r2["ok"]) and str(r2["line"]).contains("acuerdo"), "recuerda la última vez: «%s»" % str(r2["line"]))
	# Una mala respuesta baja la relación y se recuerda.
	var a1 := PlayerSim.affinity(gs, c.id)
	var bad := SocialSim.choose(gs, c, str(r2["options"][0]["id"]), 0.999)
	check(PlayerSim.affinity(gs, c.id) < a1 and int(SocialSim.memories(gs, c)[-1]["o"]) == -1, "una mala respuesta baja la relación: %s" % str(bad["effect"]))
	# Repetir el mismo tema rinde menos.
	check(SocialSim._success_chance(gs, c, first) < SocialSim._success_chance(gs, c, "consejo" if first != "consejo" else "pueblo") + 0.3, "repetir un tema reciente baja la probabilidad")
	# Consolar a alguien triste: emociones y gratitud (favor debido).
	var sad := _npc()
	sad.happiness = 10.0
	sad.sick = true
	PlayerSim._add_affinity(gs, sad.id, 20.0)
	var rs := SocialSim.start_conversation(gs, sad)
	var has_cons: bool = rs["options"].any(func(o): return o["id"] == "consolar")
	var t0 := float(SocialSim.emotions(gs, sad)["tristeza"])
	SocialSim.choose(gs, sad, "consolar", 0.0)
	check(has_cons and float(SocialSim.emotions(gs, sad)["tristeza"]) < t0 and int(SocialSim.contact(gs, sad.id)["owed"]) == 1, "consolar a alguien triste baja su tristeza y te queda agradecido")


# --- Favores y contactos ----------------------------------------------------------------------------

func _test_favors_and_contacts() -> void:
	_new_town(404)
	var gs = GameState
	var c := _npc(35, 50.0)
	var kid := _npc(20)
	PopulationSim.link_parents(kid, c if c.gender == "M" else null, c if c.gender == "F" else null)
	PlayerSim._add_affinity(gs, c.id, 70.0)
	var r := SocialSim.start_conversation(gs, c)
	check(r["options"].any(func(o): return o["id"] == "favor"), "con buena relación se puede pedir un favor")
	var f := SocialSim.choose(gs, c, "favor", 0.0)
	check(f["options"].size() >= 3, "el favor ofrece opciones (contacto, dato, trabajador)")
	var before := PlayerSim.affinity(gs, kid.id)
	var fr := SocialSim.choose(gs, c, "favor_contacto", 0.0)
	check(PlayerSim.affinity(gs, kid.id) > before, "te presenta a alguien de confianza: %s" % str(fr["line"]))
	check(SocialSim.memories(gs, kid)[-1]["k"] == "presentado", "el nuevo contacto recuerda quién te presentó")
	# Regalo: cuesta, va a proveedores del pueblo y deja un favor debido.
	var t0 := _total()
	var m0: float = gs.money
	var g := SocialSim.give_gift(gs, c)
	check(gs.money < m0 and absf(_total() - t0) < 0.01, "el regalo se paga a proveedores del pueblo (sin crear dinero): %s" % g)
	check(int(SocialSim.contact(gs, c.id)["owed"]) >= 1 and SocialSim.can_gift(gs, c) != "", "te debe un favor y no hay otro regalo este mes")
	check(SocialSim.favor_chance(gs, c) >= 0.95, "con un favor debido, casi seguro te ayuda")


# --- Ofrecer trabajo y cenas ------------------------------------------------------------------------

func _test_job_offer_and_visit() -> void:
	_new_town(405)
	var gs = GameState
	var farm := _farm()
	var c := _npc(28)
	c.job_id = -1
	c.job_kind = ""
	check(not SocialSim.vacancies(gs).is_empty(), "tu granja tiene vacantes")
	var low := SocialSim.job_chance(gs, c, farm, BusinessSim.asked_wage(gs, c, "granja") * 0.5)
	var fair := SocialSim.job_chance(gs, c, farm, BusinessSim.asked_wage(gs, c, "granja"))
	check(fair > low, "un mejor sueldo sube la probabilidad (%.2f > %.2f)" % [fair, low])
	var t := SocialSim.offer_job(gs, c, farm, -1.0, 0.0)
	check(c.job_id == int(farm["id"]) and c.job_kind == "empleo", "ofrecer trabajo en persona: %s" % t)
	check(int(SocialSim.contact(gs, c.id)["owed"]) == 1, "quien recibe trabajo te debe un favor")
	var boss := _npc(40)
	boss.job_kind = "dueño"
	check(SocialSim.job_chance(gs, boss, farm, 50.0) == 0.0, "un dueño de negocio no deja el suyo")
	# Cena en tu casa.
	var friend := _npc(30)
	PlayerSim._add_affinity(gs, friend.id, 30.0)
	var t0 := _total()
	var a0 := PlayerSim.affinity(gs, friend.id)
	var v := SocialSim.invite_home(gs, friend, 0.0)
	check(PlayerSim.affinity(gs, friend.id) > a0 and absf(_total() - t0) < 0.01, "cena en casa: sube la relación y la comida se compra en el pueblo: %s" % v)
	var no := SocialSim.invite_home(gs, _npc(30), 0.0)
	check(no != "" and not no.contains("cenó"), "a un desconocido no se le invita a cenar: %s" % no)


# --- Cartas y telegramas que tardan ----------------------------------------------------------------

func _test_messages_delay() -> void:
	_new_town(406)
	var gs = GameState
	var c := _npc()
	check(SocialSim.send(gs, c, "carta") != "" and SocialSim.pending_outbox(gs).is_empty(), "no se escribe a quien no conoces")
	SocialSim.greet(gs, c)
	var t0 := _total()
	var a0 := PlayerSim.affinity(gs, c.id)
	var t := SocialSim.send(gs, c, "carta")
	check(SocialSim.pending_outbox(gs).size() == 1 and t.contains("llegará"), "la carta queda en camino: %s" % t)
	check(absf(_total() - t0) < 0.01, "el franqueo va al tesoro (sin crear dinero)")
	check(SocialSim.send(gs, c, "llamada") != "" and SocialSim.send(gs, c, "chat") != "", "en la colonia no se puede llamar ni chatear")
	var arrive := int(SocialSim.pending_outbox(gs)[0]["arrive"])
	check(arrive - gs.today() >= 3, "la carta tarda días en llegar (%d)" % (arrive - gs.today()))
	TimeManager.advance_days(arrive - gs.today())
	check(SocialSim.pending_outbox(gs).is_empty() and PlayerSim.affinity(gs, c.id) > a0 - 1.0, "la carta llegó a %s" % c.first_name)
	var back: Array = SocialSim.state(gs)["inbox"]
	check(back.size() == 1 and int(back[0]["day"]) > gs.today() and SocialSim.unread_count(gs) == 0, "la respuesta también tarda en volver")
	TimeManager.advance_days(int(back[0]["day"]) - gs.today())
	check(SocialSim.unread_count(gs) == 1, "llegó la respuesta al buzón")
	SocialSim.mark_all_read(gs)
	check(SocialSim.unread_count(gs) == 0, "leer el buzón")
	# Telégrafo: 1 día. Teléfono y celular: al instante.
	gs.techs.append("telegrafo")
	SocialSim.send(gs, c, "carta")
	check(int(SocialSim.pending_outbox(gs)[0]["arrive"]) == gs.today() + 1, "el telegrama llega al día siguiente")
	gs.techs.append("electricidad")
	gs.techs.append("electronica")
	gs.player["talked"] = {}
	var call := SocialSim.send(gs, c, "llamada")
	check(call.begins_with("Llamaste"), "con teléfono se llama al instante: %s" % call)
	var chat := SocialSim.send(gs, c, "chat", "¿Cómo estás?")
	check(SocialSim.chat_of(gs, c).size() == 2 and chat.contains("respondió"), "el celular permite chatear: %s" % chat)
	# Invitación por el dispositivo.
	PlayerSim._add_affinity(gs, c.id, 40.0)
	var inv := SocialSim.send(gs, c, "invitacion")
	check(inv != "" and SocialSim.inbox(gs).size() >= 2, "invitar a casa por el celular: %s" % inv)


# --- Socios con capital ------------------------------------------------------------------------------

func _test_partners_capital() -> void:
	_new_town(407)
	var gs = GameState
	var farm := _farm()
	var c := _npc(40, 800.0)
	PlayerSim._add_affinity(gs, c.id, 50.0)
	var val := PartnersSim.valuation(gs, farm)
	var fair := PartnersSim.fair_share(gs, farm, 300.0)
	check(val > 0.0 and fair > 0.0 and fair < 1.0, "valor del negocio %s y parte justa de 300: %d %%" % [Fmt.money(val), int(fair * 100.0)])
	check(PartnersSim.accept_chance(gs, farm, c, "capital", 300.0, fair * 1.5) > PartnersSim.accept_chance(gs, farm, c, "capital", 300.0, fair * 0.5), "ofrecer más parte sube la probabilidad")
	check(not PartnersSim.propose(gs, farm, c, "capital", 300.0, 0.6, 0.0)["ok"], "no se puede ceder el control (máximo 49 %)")
	var t0 := _total()
	var m0: float = gs.money
	var r := PartnersSim.propose(gs, farm, c, "capital", 300.0, maxf(PartnersSim.min_share(), snappedf(fair, 0.01)), 0.0)
	check(bool(r["ok"]) and absf(gs.money - m0 - 300.0) < 0.01 and absf(c.money - 500.0) < 0.01, "el socio aporta 300 de su bolsillo: %s" % str(r["msg"]))
	check(absf(_total() - t0) < 0.01, "el aporte no crea ni destruye dinero")
	var rej := PartnersSim.propose(gs, farm, _npc(30, 10.0), "capital", 300.0, 0.1, 0.0)
	check(not rej["ok"], "sin dinero no puede aportar: %s" % str(rej["msg"]))
	# Reparto de utilidades del mes cerrado.
	var p: Dictionary = PartnersSim.partners_of(gs, farm)[0]
	farm["ledger"]["last_month"] = {"ventas": 400.0, "salarios": 100.0}
	t0 = _total()
	var cm: float = c.money
	PartnersSim.monthly(gs)
	var expect := 300.0 * float(p["share"])
	check(absf(c.money - cm - expect) < 0.02 and absf(float(p["paid"]) - expect) < 0.02, "el socio cobra su %d %% de la utilidad (%s)" % [int(float(p["share"]) * 100.0), Fmt.money(expect)])
	check(absf(_total() - t0) < 0.01, "el reparto de utilidades conserva el dinero")
	var cm2: float = c.money
	PartnersSim.monthly(gs)
	check(is_equal_approx(c.money, cm2), "no se paga dos veces el mismo mes")
	farm["ledger"]["last_month"] = {"salarios": 100.0}
	TimeManager.advance_days(31)
	check(float(p["last_pay"]) == 0.0, "con pérdidas no hay reparto")
	# Venderle más y comprarle su parte.
	var sh0 := float(p["share"])
	c.money = 5000.0
	var s := PartnersSim.sell_more(gs, int(p["id"]), 0.05, 0.0)
	check(float(p["share"]) > sh0, "venderle 5 %% más: %s" % s)
	t0 = _total()
	var price := PartnersSim.buyout_price(gs, p)
	var low := PartnersSim.buy_out(gs, int(p["id"]), 0.7, 0.999)
	check(not PartnersSim.partners_of(gs, farm).is_empty() and low.contains("rechazó"), "una oferta baja puede ser rechazada: %s" % low)
	var b := PartnersSim.buy_out(gs, int(p["id"]), 1.0)
	check(PartnersSim.partners_of(gs, farm).is_empty() and absf(_total() - t0) < 0.01, "comprarle su parte por %s: %s" % [Fmt.money(price), b])


# --- Socios con habilidades y desacuerdos --------------------------------------------------------

func _test_partners_skill_and_disputes() -> void:
	_new_town(408)
	var gs = GameState
	var farm := _farm()
	var c := _npc(45, 0.0)
	c.skills["agricultura"] = 10.0
	check(PartnersSim.can_be_partner(gs, farm, c, "habilidad") != "", "sin habilidad útil no aporta habilidades")
	c.skills["agricultura"] = 80.0
	var r := PartnersSim.propose(gs, farm, c, "habilidad", 0.0, PartnersSim.fair_skill_share(gs, c, farm), 0.0)
	check(bool(r["ok"]) and PartnersSim.output_mult(gs, farm) > 1.0, "un socio experto sube la producción ×%.2f" % PartnersSim.output_mult(gs, farm))
	var p: Dictionary = PartnersSim.partners_of(gs, farm)[0]
	# Desacuerdo por pérdidas.
	p["sat"] = 5.0
	farm["ledger"]["last_month"] = {"salarios": 50.0}
	var opened := false
	for i in range(30):
		p["last_month"] = -1
		PartnersSim.monthly(gs)
		if not (p["dispute"] as Dictionary).is_empty():
			opened = true
			break
		p["sat"] = 5.0
	check(opened and str(p["dispute"]["reason"]) == "perdidas", "un socio descontento abre un desacuerdo: %s" % PartnersSim.dispute_text(gs, p))
	check(PartnersSim.output_mult(gs, farm) < 1.0 + PartnersSim.skill_bonus(gs, c, farm), "el desacuerdo baja la producción")
	var pid := int(p["id"])
	var bad := PartnersSim.resolve(gs, pid, "negociar", 0.999)
	check(not (p["dispute"] as Dictionary).is_empty(), "negociar puede salir mal: %s" % bad)
	var ig := PartnersSim.resolve(gs, pid, "ignorar")
	check(ig.contains("Ignoraste"), "ignorar empeora: %s" % ig)
	var t0 := _total()
	var comp := PartnersSim.resolve(gs, pid, "compensar")
	check((p["dispute"] as Dictionary).is_empty() and absf(_total() - t0) < 0.01, "compensar resuelve el desacuerdo (sin crear dinero): %s" % comp)
	p["dispute"] = {"reason": "reparto", "since": gs.today(), "months": 0}
	var sh := float(p["share"])
	PartnersSim.resolve(gs, pid, "ceder")
	check(float(p["share"]) > sh and (p["dispute"] as Dictionary).is_empty(), "ceder un poco de participación lo resuelve")
	p["dispute"] = {"reason": "reparto", "since": gs.today(), "months": 0}
	check(PartnersSim.resolve(gs, pid, "negociar", 0.0).contains("acuerdo"), "negociar con éxito lo resuelve")
	# Si se ignora meses, exige que le compres.
	p["dispute"] = {"reason": "reparto", "since": gs.today(), "months": int(PartnersSim.cfg().get("dispute_force_months", 4)) - 1}
	p["last_month"] = -1
	t0 = _total()
	PartnersSim.monthly(gs)
	check(PartnersSim.partners_of(gs, farm).is_empty() and absf(_total() - t0) < 0.01, "tras meses de desacuerdo te exige comprar su parte")
	# Si el negocio deja de ser tuyo, la sociedad se disuelve.
	var c2 := _npc(30, 500.0)
	PartnersSim.propose(gs, farm, c2, "capital", 100.0, 0.1, 0.0)
	farm["owner"] = "pueblo"
	PartnersSim.monthly(gs)
	check(PartnersSim.partners_of(gs, farm).is_empty(), "al vender o perder el negocio la sociedad termina")


func _test_partner_death_and_emigration() -> void:
	_new_town(409)
	var gs = GameState
	var farm := _farm()
	var c := _npc(50, 500.0)
	var heir := _npc(25)
	PopulationSim.link_parents(heir, c if c.gender == "M" else null, c if c.gender == "F" else null)
	PartnersSim.propose(gs, farm, c, "capital", 200.0, 0.15, 0.0)
	PopulationSim.die(gs, c, "prueba")
	var ps := PartnersSim.partners_of(gs, farm)
	check(ps.size() == 1 and int(ps[0]["cid"]) == heir.id, "al morir un socio, su parte la hereda su hijo(a)")
	PopulationSim._remove(gs, heir, "emigró")
	check(PartnersSim.partners_of(gs, farm).is_empty(), "si el socio emigra, su parte vuelve a ti")


# --- Propuestas espontáneas (pocas) ---------------------------------------------------------------

func _test_spontaneous_offer() -> void:
	_new_town(410)
	var gs = GameState
	var farm := _farm()
	farm["ledger"]["last_month"] = {"ventas": 300.0}
	var c := _npc(40, 1500.0)
	while float(SocialSim.traits(c)["ambicioso"]) < 0.5:
		c = _npc(40, 1500.0)   # Un inversionista: alguien ambicioso.
	c.job_id = -1
	PlayerSim._add_affinity(gs, c.id, 90.0)
	SocialSim.contact(gs, c.id)["emo"]["confianza"] = 30.0
	var m := SocialSim._spontaneous_offer(gs, 0.0)
	check(str(m.get("offer", {}).get("type", "")) == "inversion", "la propuesta es invertir en tu empresa")
	check(not m.is_empty(), "un buen contacto te escribe con una propuesta: %s" % str(m.get("text", "")))
	check(SocialSim._spontaneous_offer(gs, 0.0).is_empty(), "no llega otra propuesta enseguida (una cada %d días)" % int(SocialSim.cfg().get("offer_every_days", 45)))
	if not m.is_empty() and str(m.get("offer", {}).get("type", "")) == "inversion":
		TimeManager.advance_days(maxi(0, int(m["day"]) - gs.today()))
		var t0 := _total()
		var a := SocialSim.answer_offer(gs, int(m["id"]), true)
		check(PartnersSim.partners_of(gs, farm).size() == 1 and absf(_total() - t0) < 0.01, "aceptar la inversión crea la sociedad: %s" % a)
		check(SocialSim.answer_offer(gs, int(m["id"]), true) != "" and PartnersSim.partners_of(gs, farm).size() == 1, "una oferta no se acepta dos veces")


# --- Sucesión: solo relaciones familiares ---------------------------------------------------------

func _test_succession() -> void:
	_new_town(411)
	var gs = GameState
	var p: Citizen = gs.player_citizen()
	var wife := PopulationSim.create_citizen(gs, "F" if p.gender == "M" else "M", 26, "Prueba")
	PopulationSim.marry(p, wife)
	var kid := PopulationSim.create_citizen(gs, "M", 20, p.last_name)
	PopulationSim.link_parents(kid, p if p.gender == "M" else wife, wife if p.gender == "M" else p)
	var friend := _npc(30)
	PlayerSim._add_affinity(gs, friend.id, 80.0)
	PlayerSim._add_affinity(gs, wife.id, 90.0)
	SocialSim.greet(gs, friend)
	SocialSim.state(gs)["inbox"].append({"id": 99, "from": friend.id, "kind": "carta", "text": "hola", "day": gs.today(), "read": false, "offer": {}})
	PopulationSim.die(gs, p, "prueba")
	check(gs.player_id == kid.id, "hereda el hijo")
	check(PlayerSim.affinity(gs, friend.id) == 0.0, "el heredero NO hereda los amigos del difunto")
	check(PlayerSim.affinity(gs, wife.id) >= 90.0, "conserva la relación con su madre/padre (familia): %d" % int(PlayerSim.affinity(gs, wife.id)))
	check(SocialSim.contact(gs, friend.id, false).is_empty() and SocialSim.inbox(gs).is_empty(), "los contactos y mensajes de no familiares se borran")
	check(SocialSim.contacts(gs).any(func(e): return e["citizen"] == wife), "la familia sigue en los contactos")


# --- Avisos moderados -------------------------------------------------------------------------------

func _test_moderation() -> void:
	_new_town(412)
	var gs = GameState
	var n0: int = gs.notifications_log.filter(func(e): return e["category"] == "social").size()
	for i in range(5):
		var c := _npc()
		SocialSim.greet(gs, c)
		SocialSim.send(gs, c, "carta")
	TimeManager.advance_days(20)
	var n: int = gs.notifications_log.filter(func(e): return e["category"] == "social").size() - n0
	check(n <= 2, "5 cartas con respuesta en 20 días: solo %d aviso(s) social(es)" % n)
	check(SocialSim.unread_count(gs) >= 3, "las respuestas quedan en el buzón (%d sin leer)" % SocialSim.unread_count(gs))


# --- Guardado ---------------------------------------------------------------------------------------

func _test_save_load() -> void:
	_new_town(413)
	var gs = GameState
	var farm := _farm()
	var c := _npc(40, 900.0)
	SocialSim.greet(gs, c)
	SocialSim.send(gs, c, "carta")
	PartnersSim.propose(gs, farm, c, "capital", 200.0, 0.1, 0.0)
	var d: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.load_dict(d)
	check(PartnersSim.partners_of(gs, gs.get_building(int(farm["id"]))).size() == 1, "los socios se guardan (JSON)")
	var p: Dictionary = PartnersSim.partners_of(gs, gs.get_building(int(farm["id"])))[0]
	check(typeof(p["cid"]) == TYPE_INT and int(p["cid"]) == c.id, "los ids de socios vuelven como enteros")
	check(SocialSim.pending_outbox(gs).size() == 1 and SocialSim.memories(gs, gs.citizens[c.id]).size() >= 1, "las cartas en camino y la memoria se guardan")
	SaveManager.save_game("test_social")
	SaveManager.load_game("test_social")
	check(PartnersSim.partners_of(gs, gs.get_building(int(farm["id"]))).size() == 1 and SocialSim.pending_outbox(gs).size() == 1, "guardar y cargar (binario)")
	SaveManager.delete_save("test_social")
	# Partida antigua sin datos sociales.
	var old := gs.to_dict()
	old["player"].erase("social")
	old["player"].erase("socios")
	gs.load_dict(old)
	check(not gs.player.has("socios") and SocialSim.contacts(gs) is Array and PartnersSim.output_mult(gs, gs.get_building(int(farm["id"]))) == 1.0, "una partida vieja carga con valores por defecto")
	check(SocialSim.unread_count(gs) == 0 and SocialSim.device_id(gs) == "carta", "buzón vacío y dispositivo según la época")
	TimeManager.advance_days(40)
	check(gs.running, "la simulación sigue tras cargar una partida vieja")


# --- Conservación en marcha -------------------------------------------------------------------------

func _test_conservation_run() -> void:
	_new_town(414)
	var gs = GameState
	var farm := _farm()
	for c in BusinessSim.candidates(gs, farm).slice(0, 2):
		BusinessSim.hire(gs, farm, c, BusinessSim.asked_wage(gs, c, "granja"))
	var partner := _npc(40, 1000.0)
	PartnersSim.propose(gs, farm, partner, "capital", 400.0, 0.2, 0.0)
	var t0 := _total()
	for m in range(4):
		for c in gs.citizens.values().slice(0, 6):
			if not gs.is_player(c.id):
				SocialSim.greet(gs, c)
				SocialSim.send(gs, c, "carta")
		TimeManager.advance_days(30)
	var drift := _total() - t0
	check(absf(drift) < 0.5, "4 meses con socio, cartas y cenas: deriva del total %.3f" % drift)


# --- Interfaz -----------------------------------------------------------------------------------------

func _buttons(root: Node) -> Array:
	var out := []
	for n in root.find_children("*", "Button", true, false):
		out.append((n as Button).text)
	return out


func _test_ui() -> void:
	_new_town(415)
	var gs = GameState
	var farm := _farm()
	var c := _npc(30, 600.0)
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var hud: Hud = world.hud
	check(hud.social_ui != null and hud.social_ui.device_btn.visible, "botón del dispositivo visible")
	await get_tree().process_frame
	var vr: Rect2 = hud.social_ui.get_global_rect()
	var br: Rect2 = hud.social_ui.device_btn.get_global_rect()
	check(vr.size.x > 100.0 and vr.encloses(br) and br.end.x > vr.size.x - 20.0 and br.end.y > vr.size.y - 20.0 and hud.social_ui.anchor_right == 1.0, "el botón queda abajo a la derecha, dentro de la pantalla (%s en %s)" % [str(br), str(vr.size)])
	EventBus.citizen_selected.emit(c.id)
	await get_tree().process_frame
	var texts := _buttons(hud.citizen_actions)
	check(texts.has("Saludar") and texts.has("Conversar…") and texts.has("Ofrecer trabajo…") and texts.has("Invitar a cenar") and texts.has("Proponer sociedad…"), "la ficha ofrece saludar, conversar, trabajo, cena y sociedad: %s" % str(texts))
	check(_buttons(hud._cit_meters).size() >= 0 and hud._cit_meters.find_children("*", "Label", true, false).any(func(l): return (l as Label).text.begins_with("Ánimo")), "la ficha muestra el ánimo y las emociones")
	for n in hud.citizen_actions.find_children("*", "Button", true, false):
		if (n as Button).text == "Saludar":
			(n as Button).pressed.emit()
			break
	await get_tree().process_frame
	check(PlayerSim.affinity(gs, c.id) > 0.0, "pulsar Saludar funciona")
	hud.social_ui.open_conversation(c.id)
	await get_tree().process_frame
	check(hud.social_ui.convo_modal["root"].visible and hud.social_ui._convo_opts.get_child_count() >= 3, "se abre la conversación con varias respuestas")
	var agent = world.agents.get(c.id)
	check(agent == null or agent.hold, "la persona se detiene a conversar")
	(hud.social_ui._convo_opts.get_child(0) as Button).pressed.emit()
	await get_tree().process_frame
	check(hud.social_ui._convo_log.get_parsed_text().contains("Tú:"), "elegir una respuesta la agrega a la conversación")
	hud.social_ui.close_conversation()
	check(agent == null or not agent.hold, "al terminar sigue caminando")
	hud.social_ui.open_job_offer(c.id)
	await get_tree().process_frame
	check(_buttons(hud.social_ui.job_modal["body"]).has("Ofrecer"), "ventana de oferta de trabajo")
	hud.social_ui.job_modal["root"].visible = false
	hud.social_ui.open_partner_proposal(c.id, int(farm["id"]))
	await get_tree().process_frame
	check(_buttons(hud.social_ui.partner_modal["body"]).has("Proponer"), "formulario de sociedad")
	hud.social_ui.partner_modal["root"].visible = false
	hud.social_ui.open_device(0)
	await get_tree().process_frame
	check(hud.social_ui.device_panel.visible and _buttons(hud.social_ui._contacts_box).has("Escribir"), "el dispositivo lista contactos con «Escribir»")
	hud.social_ui.open_device(1)
	hud.social_ui.toggle_device()
	check(not hud.social_ui.device_panel.visible, "el dispositivo se cierra")
	# Pestaña Socios del negocio.
	PartnersSim.propose(gs, farm, c, "capital", 100.0, 0.1, 0.0)
	hud.open_building(int(farm["id"]))
	await get_tree().process_frame
	var has_tab := false
	for i in range(hud.building_panel.tabs.get_tab_count()):
		has_tab = has_tab or hud.building_panel.tabs.get_tab_title(i) == "Socios"
	check(has_tab, "el negocio tiene la pestaña Socios")
	check(_buttons(hud.building_panel.tabs).any(func(t): return str(t).begins_with("Comprar su parte")), "la pestaña permite comprar la parte del socio")
	hud.social_ui.open_partner_picker(int(farm["id"]))
	await get_tree().process_frame
	check(hud.social_ui.pick_modal["root"].visible, "lista de candidatos a socio")
	hud.social_ui.close_top()
	# Tu propio personaje también es interactuable.
	EventBus.citizen_selected.emit(gs.player_id)
	await get_tree().process_frame
	check(_buttons(hud.citizen_actions).has("Mi carta"), "tu personaje: botón «Mi carta»")
	world.queue_free()
	await get_tree().process_frame
