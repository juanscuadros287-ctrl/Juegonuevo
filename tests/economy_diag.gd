extends Node
## Diagnóstico económico: godot --headless res://tests/economy_diag.tscn

func _ready() -> void:
	GameState.new_game({"seed": 31, "difficulty": "normal"})
	var farm: Dictionary = ConstructionSim.start_construction(GameState, "granja", 30, -8, 0.0)["building"]
	TimeManager.advance_days(40)
	for c in BusinessSim.candidates(GameState, farm).slice(0, 4):
		BusinessSim.hire(GameState, farm, c, BusinessSim.asked_wage(GameState, c, "granja"))
	for y in range(30):
		GameState.money = maxf(GameState.money, 20000.0)
		for m in range(12):
			TimeManager.advance_days(30)
			if not GameState.running:
				break
		if not GameState.running:
			print("fin: jugador murió"); break
		if y % 3 == 0 or y == 29:
			var e: Dictionary = GameState.economy
			print("año %d · nivel precios %.3f · inflación %.1f%% · comida x%.2f agua x%.2f leña x%.2f · desempleo %.0f%% · pobl %d · granja %s precio %.2f" % [
				TimeManager.year(), e["price_level"], EconomySim.annual_inflation(GameState) * 100.0,
				EconomySim.good_factor(GameState, "comida"), EconomySim.good_factor(GameState, "agua"), EconomySim.good_factor(GameState, "lena"),
				EconomySim.unemployment(GameState) * 100.0, GameState.citizens.size(), EconomySim.classify(farm), float(farm["price"])])
	get_tree().quit()
