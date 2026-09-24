extends Node
## Diagnóstico de balance demográfico: godot --headless res://tests/balance.tscn

func _ready() -> void:
	for seed_value in [7, 8, 9]:
		GameState.new_game({"difficulty": "normal", "seed": seed_value})
		var causes := {}
		EventBus.citizen_removed.connect(func(_id, r): causes[r] = int(causes.get(r, 0)) + 1)
		var line := "semilla %d:" % seed_value
		for y in range(40):
			var before := GameState.citizens.size()
			GameState.money = 1000000.0  # Aísla la demografía de la economía del jugador.
			TimeManager.advance_days(364)
			for k in GameState.month_counters:
				if k.begins_with("death_"):
					causes[k] = int(causes.get(k, 0)) + int(GameState.month_counters[k])
			GameState.month_counters = {}
			TimeManager.advance_days(1)
			if not GameState.running:
				var last: Array = GameState.notifications_log.filter(func(e): return e["category"] == "jugador" and "murió" in e["text"])
				line += "\n  FIN %d: %s" % [TimeManager.year(), (last[-1]["text"] if not last.is_empty() else "?")]
				break
			if y % 5 == 4:
				var money := 0.0
				var adults := 0
				var married := 0
				for c in GameState.citizens.values():
					if c.age_years(GameState.today()) >= 16:
						adults += 1
						money += c.money
						if c.spouse_id >= 0:
							married += 1
				line += "\n  año %d: pobl %d adultos %d casados %d dinero_prom %.0f feliz %.0f salud %.0f crimen %d eventos %d gob %s tesoro %.0f" % [
					TimeManager.year(), GameState.citizens.size(), adults, married,
					money / maxf(1, adults), GameState.avg_happiness(), GameState.avg_health(),
					int(GameState.problems.get("crime", 0)), GameState.problems.get("events", []).size(), GameState.government.get("gov_id", ""), float(GameState.government.get("treasury", 0))]
		var c := {}
		for h in GameState.history:
			for k in ["births", "deaths"]:
				c[k] = int(c.get(k, 0)) + int(h[k])
		line += "\n  totales: %s causas: %s" % [str(c), str(causes)]
		print(line)
	get_tree().quit()
