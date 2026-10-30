extends Node
## Capturas de la vida social (docs/SOCIAL.md):
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 tests/screenshot_social.tscn -- docs/capturas/social

var out := "user://"


func _shot(name: String, frames := 30) -> void:
	for i in range(frames):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("captura: ", name)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://"
	DirAccess.make_dir_recursive_absolute(out)
	var gs = GameState
	gs.new_game({"map_type": "interior", "seed": 77, "difficulty": "facil", "town_name": "San Rafael"})
	gs.money += 30000.0
	var farm: Dictionary = ConstructionSim.start_construction(gs, "granja", 30, -8, 0.3, "Granja Cuadros")["building"]
	TimeManager.advance_days(60)
	for c in BusinessSim.candidates(gs, farm).slice(0, 2):
		BusinessSim.hire(gs, farm, c, BusinessSim.asked_wage(gs, c, farm["type"]))
	TimeManager.advance_days(70)
	TimeManager.total_hours += 10 - TimeManager.hour()
	# Gente conocida, recuerdos, cartas y un socio en desacuerdo.
	var people: Array = gs.citizens.values().filter(func(c): return not gs.is_player(c.id) and c.age_years(gs.today()) >= 20)
	var friend: Citizen = people[0]
	var investor: Citizen = people[1]
	var sad: Citizen = people[2]
	for c in people.slice(0, 7):
		SocialSim.greet(gs, c)
	PlayerSim._add_affinity(gs, friend.id, 55.0)
	SocialSim.remember(gs, friend, "visita", 1, "Cenó en tu casa")
	SocialSim.remember(gs, friend, "negocios", 1, "Hablaron de negocios")
	SocialSim.contact(gs, friend.id)["owed"] = 1
	investor.money = 1200.0
	PlayerSim._add_affinity(gs, investor.id, 70.0)
	PartnersSim.propose(gs, farm, investor, "capital", 400.0, 0.2, 0.0)
	var p: Dictionary = PartnersSim.partners_of(gs, farm)[0]
	p["paid"] = 86.0
	p["last_pay"] = 21.5
	p["sat"] = 24.0
	p["dispute"] = {"reason": "reparto", "since": gs.today(), "months": 1}
	sad.happiness = 18.0
	PlayerSim._add_affinity(gs, sad.id, 25.0)
	for c in people.slice(3, 6):
		SocialSim.send(gs, c, "carta")
	TimeManager.advance_days(12)
	SocialSim.state(gs)["last_offer"] = -100000
	var rich: Citizen = people[6]
	rich.money = 900.0
	PlayerSim._add_affinity(gs, rich.id, 85.0)
	SocialSim._msg(gs, rich.id, "oferta", "Quisiera invertir $300 en Granja Cuadros a cambio del 8%% de sus utilidades. ¿Qué me dice? — %s" % rich.first_name, gs.today(),
		{"type": "inversion", "bid": int(farm["id"]), "capital": 300.0, "share": 0.08})
	TimeManager.total_hours += 10 - TimeManager.hour()
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	TimeManager.set_speed(0)
	var hud: Hud = world.hud
	await get_tree().process_frame
	# 1. Ficha de una persona que camina: ánimo, emociones, memoria y acciones.
	EventBus.citizen_selected.emit(friend.id)
	if world.has_method("focus_citizen"):
		world.focus_citizen(friend.id)
	await _shot("ficha_persona", 50)
	# 2. Conversación con varias respuestas.
	EventBus.citizen_selected.emit(sad.id)
	hud.social_ui.open_conversation(sad.id)
	await get_tree().process_frame
	hud.social_ui._pick_option(sad.id, "trabajo", "Preguntarle cómo le va")
	await _shot("conversacion")
	hud.social_ui.close_conversation()
	# 3. Dispositivo: contactos y buzón (época colonial: cartas).
	EventBus.citizen_selected.emit(-1)
	hud.close_dock()
	hud.social_ui.open_device(0)
	await _shot("dispositivo_carta_contactos")
	hud.social_ui.open_device(1)
	await _shot("dispositivo_buzon")
	# 4. Celular con chat (época moderna).
	for t in ["telegrafo", "electricidad", "electronica"]:
		gs.techs.append(t)
	gs.player["talked"] = {}
	SocialSim.send(gs, friend, "chat", "¿Tomamos un café?")
	hud.social_ui._chat_with = friend.id
	hud.social_ui.open_device(2)
	await _shot("dispositivo_celular_chat")
	hud.social_ui.toggle_device()
	for t in ["telegrafo", "electricidad", "electronica"]:
		gs.techs.erase(t)
	# 5. Pestaña Socios con un desacuerdo.
	hud.open_building(int(farm["id"]))
	await get_tree().process_frame
	for i in range(hud.building_panel.tabs.get_tab_count()):
		if hud.building_panel.tabs.get_tab_title(i) == "Socios":
			hud.building_panel.tabs.current_tab = i
	await _shot("socios_desacuerdo")
	# 6. Proponer sociedad y ofrecer trabajo.
	hud.social_ui.open_partner_proposal(friend.id, int(farm["id"]))
	await _shot("proponer_sociedad")
	hud.social_ui.partner_modal["root"].visible = false
	var jobless: Citizen = null
	for c in people:
		if c.job_id < 0:
			jobless = c
			break
	if jobless != null:
		hud.social_ui.open_job_offer(jobless.id)
		await _shot("ofrecer_trabajo")
		hud.social_ui.job_modal["root"].visible = false
	# 7. Tu propio personaje.
	EventBus.citizen_selected.emit(gs.player_id)
	if world.has_method("focus_citizen"):
		world.focus_citizen(gs.player_id)
	await _shot("mi_personaje", 40)
	get_tree().quit()
