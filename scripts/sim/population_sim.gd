class_name PopulationSim
extends RefCounted
## Simulación diaria de ciudadanos: economía doméstica, salud, enfermedad,
## muerte, matrimonios, nacimientos y emigración. Parámetros en data/citizens.json.


# --- Generación inicial ---------------------------------------------------------

static func generate_initial(gs, target: int) -> void:
	var cfg := GameData.citizens
	var adult_age := int(cfg.get("adult_age", 16))
	while gs.citizens.size() < target:
		var remaining: int = target - gs.citizens.size()
		var hut := create_hut(gs)
		var household := []
		if remaining >= 2 and gs.rng.randf() < 0.75:
			var h_age: int = gs.rng.randi_range(20, 48)
			var husband := create_citizen(gs, "M", h_age, random_surname(gs))
			var w_age := clampi(h_age + gs.rng.randi_range(-7, 3), 18, 44)
			var wife := create_citizen(gs, "F", w_age, random_surname(gs))
			marry(husband, wife)
			household.append_array([husband, wife])
			var max_kids := mini(gs.rng.randi_range(0, 4), remaining - 2)
			var max_child_age := mini(adult_age - 1, w_age - 18)
			for k in range(max_kids):
				var child := create_citizen(gs, "M" if gs.rng.randf() < 0.5 else "F",
						gs.rng.randi_range(0, maxi(0, max_child_age)), husband.last_name)
				link_parents(child, husband, wife)
				household.append(child)
			if remaining - household.size() >= 1 and gs.rng.randf() < 0.2:
				var elder := create_citizen(gs, "M" if gs.rng.randf() < 0.4 else "F",
						gs.rng.randi_range(56, 72), husband.last_name)
				household.append(elder)
		else:
			var g := "M" if gs.rng.randf() < 0.55 else "F"
			household.append(create_citizen(gs, g, gs.rng.randi_range(18, 60), random_surname(gs)))
		for c in household:
			c.home_id = int(hut["id"])


static func create_hut(gs) -> Dictionary:
	var pos := Vector2.ZERO
	for attempt in range(80):
		var ang: float = gs.rng.randf() * TAU
		var r: float = gs.rng.randf_range(9.0, gs.TOWN_RADIUS - 2.0 + attempt * 0.1)
		pos = Vector2(cos(ang), sin(ang)) * r
		var ok := true
		for b in gs.buildings:
			if pos.distance_to(Vector2(float(b["x"]), float(b["z"]))) < 6.5:
				ok = false
				break
		if ok:
			break
	var hut := ConstructionSim.make_building(gs, "vivienda", 1, pos.x, pos.y, atan2(-pos.x, -pos.y), "pueblo")
	hut["tier"] = "normal"
	gs.add_building(hut)
	return hut


static func random_surname(gs) -> String:
	var list: Array = GameData.names.get("surnames", ["García"])
	return list[gs.rng.randi() % list.size()]


static func random_first_name(gs, gender: String) -> String:
	var list: Array = GameData.names.get("male" if gender == "M" else "female", ["Juan"])
	return list[gs.rng.randi() % list.size()]


static func create_citizen(gs, gender: String, age: int, last_name: String) -> Citizen:
	var cfg := GameData.citizens
	var adult_age := int(cfg.get("adult_age", 16))
	var c := Citizen.new()
	c.id = gs.next_citizen_id
	gs.next_citizen_id += 1
	c.gender = gender
	c.first_name = random_first_name(gs, gender)
	c.last_name = last_name
	c.birth_day = gs.today() - age * 365 - gs.rng.randi_range(0, 364)
	c.visual_seed = gs.rng.randi()
	c.health = gs.rng.randf_range(75.0, 100.0) - maxf(0.0, age - 50) * 0.6
	c.happiness = gs.rng.randf_range(52.0, 70.0)
	# Habilidades: base baja + una habilidad principal según pesos de configuración.
	var skill_cfg: Dictionary = GameData.skills.get("skills", {})
	for s in skill_cfg:
		c.skills[s] = roundf(gs.rng.randf_range(0.0, 12.0))
	if age >= adult_age:
		var main := _weighted_skill(gs, skill_cfg)
		c.skills[main] = roundf(minf(100.0, 20.0 + (age - adult_age) * 1.2 + gs.rng.randf_range(0.0, 25.0)))
		c.experience = roundf(maxf(0.0, age - adult_age) * gs.rng.randf_range(0.4, 1.0) * 10.0) / 10.0
		var chances: Array = GameData.skills.get("education_chance_adults", [1.0])
		var r: float = gs.rng.randf()
		for i in range(chances.size()):
			r -= float(chances[i])
			if r <= 0.0:
				c.education = i
				break
		var money_range: Array = gs.diff().get("citizen_money", [20, 80])
		c.money = roundf(gs.rng.randf_range(float(money_range[0]), float(money_range[1])))
	gs.citizens[c.id] = c
	return c


static func _weighted_skill(gs, skill_cfg: Dictionary) -> String:
	var total := 0.0
	for s in skill_cfg:
		total += float(skill_cfg[s].get("weight", 1.0))
	var r: float = gs.rng.randf() * total
	for s in skill_cfg:
		r -= float(skill_cfg[s].get("weight", 1.0))
		if r <= 0.0:
			return s
	return skill_cfg.keys()[0]


static func marry(a: Citizen, b: Citizen) -> void:
	a.spouse_id = b.id
	b.spouse_id = a.id


static func link_parents(child: Citizen, father: Citizen, mother: Citizen) -> void:
	child.parent_ids = []
	for p in [father, mother]:
		if p != null:
			child.parent_ids.append(p.id)
			if not p.children_ids.has(child.id):
				p.children_ids.append(child.id)


# --- Mortalidad -------------------------------------------------------------------

static func annual_mortality(age: int) -> float:
	var m: Dictionary = GameData.citizens.get("mortality", {})
	var p := float(m.get("a", 0.0003)) * exp(float(m.get("b", 0.09)) * age)
	if age <= int(m.get("infant_age", 4)):
		p += float(m.get("infant_annual", 0.05))
	return p


static func daily_death_probability(age: int, health: float, sick: bool) -> float:
	var p := annual_mortality(age) / 365.0
	p *= 1.0 + (100.0 - health) / 40.0
	if sick:
		p *= float(GameData.citizens.get("disease", {}).get("death_mult_when_sick", 4.0))
	return p


# --- Ciclo diario --------------------------------------------------------------------

static func daily(gs) -> void:
	var cfg := GameData.citizens
	var today: int = gs.today()
	var adult_age := int(cfg.get("adult_age", 16))
	var season := WeatherSim.season_data(gs)
	var wdata := WeatherSim.weather_data(gs)
	var diff: Dictionary = gs.diff()
	var occupancy := home_occupancy(gs)

	var ids: Array = gs.citizens.keys()
	for id in ids:
		if not gs.citizens.has(id):
			continue
		var c: Citizen = gs.citizens[id]
		var age := c.age_years(today)
		_economy(gs, c, age, adult_age, season, wdata, diff)
		_health(gs, c, age, season, wdata, diff)
		if c.health <= 0.0 or gs.rng.randf() < daily_death_probability(age, c.health, c.sick):
			die(gs, c, "enfermedad" if c.sick else ("vejez" if age >= 60 else "causas naturales"))
			continue
		_happiness(gs, c, occupancy, wdata)

	_marriages(gs, today)
	_births(gs, today)
	if today % 7 == 0:
		_emigration(gs, today)


static func home_occupancy(gs) -> Dictionary:
	var occ := {}
	for c in gs.citizens.values():
		if c.home_id >= 0:
			occ[c.home_id] = int(occ.get(c.home_id, 0)) + 1
	return occ


## Billetera familiar: quiénes pueden pagar las necesidades de este ciudadano.
## Adultos: él mismo y su cónyuge. Menores: sus padres o adultos de su hogar.
static func _payers(gs, c: Citizen, is_adult: bool, adult_age: int) -> Array:
	var out := []
	if is_adult:
		out.append(c)
		if c.spouse_id >= 0 and gs.citizens.has(c.spouse_id):
			out.append(gs.citizens[c.spouse_id])
		return out
	for pid in c.parent_ids:
		if gs.citizens.has(pid):
			out.append(gs.citizens[pid])
	if out.is_empty() and c.home_id >= 0:
		var today: int = gs.today()
		for other in gs.citizens.values():
			if other.home_id == c.home_id and other.age_years(today) >= adult_age:
				out.append(other)
	return out


## Paga con la billetera familiar. El dinero del jugador es GameState.money.
static func pay_with(gs, payers: Array, amount: float) -> bool:
	if amount <= 0.0:
		return true
	var total := 0.0
	for p in payers:
		total += maxf(0.0, _wallet(gs, p))
	if total < amount:
		return false
	var left := amount
	for p in payers:
		if left <= 0.0:
			break
		var take := minf(maxf(0.0, _wallet(gs, p)), left)
		if gs.is_player(p.id):
			gs.add_money(-take)
		else:
			p.money -= take
		left -= take
	return true


static func _wallet(gs, p: Citizen) -> float:
	return gs.money if gs.is_player(p.id) else p.money


static func _economy(gs, c: Citizen, age: int, adult_age: int, season: Dictionary, wdata: Dictionary, diff: Dictionary) -> void:
	var cfg := GameData.citizens
	var price_mult := float(diff.get("price_mult", 1.0))
	var is_adult := age >= adult_age
	var is_player: bool = gs.is_player(c.id)
	var cost_factor := 1.0 if is_adult else float(cfg.get("child_cost_factor", 0.4))
	if is_player:
		cost_factor = float(PlayerSim.cfg().get("living_cost_factor", 2.0))
	var payers := _payers(gs, c, is_adult, adult_age)
	var employed := c.job_id >= 0
	if is_adult and not employed and not is_player:
		# Sin empleo: subsistencia (cultivan y venden excedentes por su cuenta).
		var skill := float(c.skills.get("agricultura", 0.0))
		var income := float(cfg.get("subsistence_income", 1.5)) * (0.8 + skill / 250.0)
		income *= float(season.get("farming", 1.0)) * float(wdata.get("farming", 1.0))
		income *= clampf(c.health / 80.0, 0.2, 1.0)
		if age >= int(cfg.get("retirement_age", 65)):
			income *= float(cfg.get("retired_income_factor", 0.5))
		c.money += income
		c.experience += 1.0 / 365.0
		c.skills["agricultura"] = minf(100.0, float(c.skills.get("agricultura", 0.0)) + 0.01)

	var needs: Dictionary = cfg.get("needs", {})
	var total_w := 0.0
	var met_w := 0.0
	var bonus := 0.0
	var energy_mult := float(wdata.get("energy_demand", 1.0))
	var home: Dictionary = gs.get_building(c.home_id)
	for need_id in cfg.get("needs_priority", []):
		if not needs.has(need_id):
			continue
		var need: Dictionary = needs[need_id]
		var w := float(need.get("weight", 0.1))
		total_w += w
		var ref := float(need.get("cost", 0.1)) * price_mult
		var qty := cost_factor
		if need_id == "energia":
			qty *= energy_mult
		var satisfied := false
		if payers.is_empty() and need_id in ["comida", "agua"]:
			satisfied = true  # Caridad del pueblo para huérfanos sin tutor.
		elif need_id == "vivienda":
			satisfied = _pay_housing(gs, c, home, payers, ref * qty)
		elif need.has("good"):
			var r := MarketSim.purchase(gs, payers, str(need["good"]), qty, ref, employed)
			satisfied = bool(r["ok"])
			bonus += float(r["bonus"])
		else:
			satisfied = pay_with(gs, payers, ref * qty)
		if satisfied:
			met_w += w
		else:
			c.health -= float(need.get("health_penalty", 0.0))
	c.needs_met = met_w / total_w if total_w > 0.0 else 1.0
	c.set_meta("bonus", bonus)


## Vivienda: gratis si es propia, alquiler si es tuya (del jugador), mantenimiento si es del pueblo.
static func _pay_housing(gs, c: Citizen, home: Dictionary, payers: Array, maintenance: float) -> bool:
	if home.is_empty():
		return false
	var owner := str(home.get("owner", "pueblo"))
	if owner == "ciudadano" or gs.is_player(c.id):
		return true
	if owner == "jugador":
		# La familia del jugador no paga alquiler.
		var p: Citizen = gs.player_citizen()
		if p != null and (c.id == p.spouse_id or p.children_ids.has(c.id) or c.home_id == p.home_id):
			return true
		var rent := MarketSim.daily_rent(gs, home)
		var factor := 1.0 if c.age_years(gs.today()) >= int(GameData.citizens.get("adult_age", 16)) else float(GameData.citizens.get("child_cost_factor", 0.4))
		rent *= factor
		if rent <= 0.0:
			return true
		if pay_with(gs, payers, rent):
			BusinessSim.earn(gs, home, rent, "alquileres")
			c.unpaid_days = 0
			return true
		c.unpaid_days += 1
		return false
	return pay_with(gs, payers, maintenance)


static func _health(gs, c: Citizen, age: int, season: Dictionary, wdata: Dictionary, diff: Dictionary) -> void:
	var dcfg: Dictionary = GameData.citizens.get("disease", {})
	if c.sick:
		var dmg: Array = dcfg.get("daily_damage", [1.5, 5.0])
		c.health -= gs.rng.randf_range(float(dmg[0]), float(dmg[1]))
		if gs.rng.randf() < float(dcfg.get("daily_recover_chance", 0.1)):
			c.sick = false
	else:
		var chance := float(dcfg.get("daily_chance", 0.0012)) * float(diff.get("disease_mult", 1.0))
		chance *= float(season.get("disease", 1.0)) * float(wdata.get("disease", 1.0))
		if age <= 5 or age >= 60:
			chance *= float(dcfg.get("vulnerable_mult", 2.0))
		if c.needs_met < 0.6:
			chance *= 1.5
		if gs.rng.randf() < chance:
			c.sick = true
			gs.count("illnesses")
			gs.notify("%s (%d años) se enfermó." % [c.full_name(), age], "salud")
		elif c.needs_met >= 0.65:
			var max_health := 100.0 - maxf(0.0, age - 50) * 0.8
			c.health = minf(max_health, c.health + float(GameData.citizens.get("health_regen_per_day", 0.6)))
	c.health = clampf(c.health, 0.0, 100.0)


static func _happiness(gs, c: Citizen, occupancy: Dictionary, wdata: Dictionary) -> void:
	var h: Dictionary = GameData.citizens.get("happiness", {})
	var target := float(h.get("base", 40)) + c.needs_met * float(h.get("needs_weight", 30))
	target += (c.health - 70.0) * float(h.get("health_weight", 0.25))
	if c.home_id < 0:
		target += float(h.get("homeless", -15))
	else:
		var b: Dictionary = gs.get_building(c.home_id)
		if not b.is_empty() and int(occupancy.get(c.home_id, 0)) > gs.building_capacity(b):
			target += float(h.get("overcrowded", -8))
		target += (MarketSim.home_quality(gs, b) - 1.0) * float(h.get("home_quality_weight", 5))
	if c.spouse_id >= 0:
		target += float(h.get("married", 4))
	if c.money >= float(h.get("rich_threshold", 60)):
		target += float(h.get("rich_bonus", 5))
	elif c.money < float(h.get("poor_threshold", 5)):
		target += float(h.get("poor_penalty", -6))
	if c.job_kind == "empleo":
		target += float(h.get("employed", 3))
	target += float(c.get_meta("bonus", 0.0))
	target += float(wdata.get("happiness", 0))
	target = clampf(target, 0.0, 100.0)
	c.happiness = clampf(c.happiness + (target - c.happiness) * float(h.get("adjust_rate", 0.05)), 0.0, 100.0)


# --- Eventos de vida ---------------------------------------------------------------------

static func die(gs, c: Citizen, cause: String) -> void:
	var age := c.age_years(gs.today())
	_remove(gs, c, "murió")
	gs.count("deaths")
	gs.count("death_" + cause.replace(" ", "_"))
	if gs.is_player(c.id):
		gs.notify("Tu personaje %s murió a los %d años (%s)." % [c.full_name(), age, cause], "jugador")
		PlayerSim.on_player_death(gs, c)
	else:
		gs.notify("Murió %s a los %d años (%s)." % [c.full_name(), age, cause], "muerte")


static func _remove(gs, c: Citizen, reason: String) -> void:
	gs.graveyard[c.id] = "%s (%s en %d)" % [c.full_name(), reason, TimeManager.year()]
	if c.spouse_id >= 0 and gs.citizens.has(c.spouse_id):
		gs.citizens[c.spouse_id].spouse_id = -1
	gs.citizens.erase(c.id)
	EventBus.citizen_removed.emit(c.id, reason)


static func is_related(a: Citizen, b: Citizen) -> bool:
	if a.parent_ids.has(b.id) or b.parent_ids.has(a.id):
		return true
	for p in a.parent_ids:
		if b.parent_ids.has(p):
			return true
	return false


static func _marriages(gs, today: int) -> void:
	var cfg := GameData.citizens
	var min_age := int(cfg.get("marriage_min_age", 18))
	var max_age := int(cfg.get("marriage_max_age", 50))
	var chance := float(cfg.get("annual_marriage_chance", 0.35)) / 365.0
	var gap := int(cfg.get("max_age_gap", 12))
	var single_women := []
	var single_men := []
	for c in gs.citizens.values():
		if c.spouse_id >= 0 or gs.is_player(c.id):
			continue
		var age: int = c.age_years(today)
		if age < min_age or age > max_age:
			continue
		if c.gender == "F":
			single_women.append(c)
		else:
			single_men.append(c)
	for man in single_men:
		if single_women.is_empty():
			return
		if gs.rng.randf() >= chance:
			continue
		var m_age: int = man.age_years(today)
		var candidates := single_women.filter(func(w): return absi(w.age_years(today) - m_age) <= gap and not is_related(man, w))
		if candidates.is_empty():
			continue
		var wife: Citizen = candidates[gs.rng.randi() % candidates.size()]
		single_women.erase(wife)
		marry(man, wife)
		_house_couple(gs, man, wife)
		gs.count("marriages")
		gs.notify("Boda: %s y %s se casaron." % [man.full_name(), wife.full_name()], "boda")


static func _house_couple(gs, a: Citizen, b: Citizen) -> void:
	var occ := home_occupancy(gs)
	# Preferencia: vivienda vacía, luego la casa de él, luego la de ella.
	for bld in gs.buildings:
		if bld.get("type") == "vivienda" and bld.get("owner") == "pueblo" and int(occ.get(int(bld["id"]), 0)) == 0:
			a.home_id = int(bld["id"])
			b.home_id = int(bld["id"])
			EventBus.citizens_moved.emit()
			return
	for pair in [[a, b], [b, a]]:
		var host: Citizen = pair[0]
		var guest: Citizen = pair[1]
		var bld: Dictionary = gs.get_building(host.home_id)
		if not bld.is_empty() and int(occ.get(host.home_id, 0)) < gs.building_capacity(bld):
			guest.home_id = host.home_id
			EventBus.citizens_moved.emit()
			return


static func _births(gs, today: int) -> void:
	var cfg := GameData.citizens
	var min_age := int(cfg.get("fertile_min_age", 18))
	var max_age := int(cfg.get("fertile_max_age", 44))
	var base := float(cfg.get("annual_birth_chance", 0.34)) / 365.0
	var max_children := int(cfg.get("max_children", 9))
	var gap_days := int(cfg.get("min_days_between_births", 300))
	var mothers := []
	for c in gs.citizens.values():
		if c.gender != "F" or c.spouse_id < 0 or not gs.citizens.has(c.spouse_id):
			continue
		var age: int = c.age_years(today)
		if age < min_age or age > max_age or c.children_ids.size() >= max_children:
			continue
		if today - c.last_birth_day < gap_days:
			continue
		mothers.append(c)
	for mother in mothers:
		var father: Citizen = gs.citizens[mother.spouse_id]
		var age: int = mother.age_years(today)
		var p: float = base * (0.4 + mother.happiness / 100.0) * (mother.health / 100.0)
		if age >= 35:
			p *= 0.5
		if mother.home_id != father.home_id:
			p *= 0.3
		if gs.is_player(mother.id) or gs.is_player(father.id):
			if not bool(gs.player.get("family_planning", true)):
				continue
			if int(gs.player.get("try_child_until", -1)) >= today:
				p *= float(PlayerSim.cfg().get("try_child_mult", 4.0))
		if gs.rng.randf() >= p:
			continue
		var baby := create_citizen(gs, "M" if gs.rng.randf() < 0.51 else "F", 0, father.last_name)
		baby.birth_day = today
		baby.health = gs.rng.randf_range(80.0, 100.0)
		baby.happiness = 70.0
		baby.home_id = mother.home_id
		link_parents(baby, father, mother)
		mother.last_birth_day = today
		gs.count("births")
		var ours: bool = gs.is_player(mother.id) or gs.is_player(father.id)
		gs.notify("%s %s, hijo(a) de %s y %s." % ["¡Nació tu hijo(a)" if ours else "Nació", baby.full_name(), father.first_name, mother.first_name], "familia" if ours else "nacimiento")
		EventBus.citizen_born.emit(baby.id)


static func _in_player_family(gs, c: Citizen) -> bool:
	var p: Citizen = gs.player_citizen()
	if p == null:
		return false
	return c.id == p.id or c.id == p.spouse_id or p.children_ids.has(c.id) or c.home_id == p.home_id


static func _emigration(gs, today: int) -> void:
	var cfg := GameData.citizens
	var threshold := float(cfg.get("emigration_threshold", 22))
	var chance := float(cfg.get("emigration_weekly_chance", 0.06))
	var adult_age := int(cfg.get("adult_age", 16))
	var leavers := []
	for c in gs.citizens.values():
		if c.age_years(today) >= adult_age and c.happiness < threshold and gs.rng.randf() < chance and not _in_player_family(gs, c):
			leavers.append(c)
	for c in leavers:
		if not gs.citizens.has(c.id):
			continue
		# Se va con su cónyuge e hijos menores.
		var family: Array = [c]
		if c.spouse_id >= 0 and gs.citizens.has(c.spouse_id):
			family.append(gs.citizens[c.spouse_id])
		for member in family.duplicate():
			for kid_id in member.children_ids:
				if gs.citizens.has(kid_id):
					var kid: Citizen = gs.citizens[kid_id]
					if kid.age_years(today) < adult_age and not family.has(kid):
						family.append(kid)
		for m in family:
			_remove(gs, m, "emigró")
		gs.count("emigrated", family.size())
		var who: String = c.full_name() if family.size() == 1 else "La familia %s (%d personas)" % [c.last_name, family.size()]
		gs.notify("%s emigró del pueblo por baja felicidad." % who, "emigracion")
