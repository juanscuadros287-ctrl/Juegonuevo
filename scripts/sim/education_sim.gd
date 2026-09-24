class_name EducationSim
extends RefCounted
## Escuelas, colegios y universidades: matriculan niños/jóvenes según cupos
## (profesores × alumnos por profesor) y pensión. Al completar años de estudio
## suben su nivel de educación y su habilidad de ciencia.


static func capacity(gs, b: Dictionary) -> int:
	var teachers := 0
	for c in gs.employees_of(int(b["id"])):
		if c.job_kind == "empleo":
			teachers += 1
	return int(teachers * float(gs.level_def(b).get("prod_per_worker", 15)))


static func students_of(gs, b: Dictionary) -> Array:
	var id := int(b["id"])
	return gs.citizens.values().filter(func(c): return c.school_id == id)


static func monthly(gs) -> void:
	var today: int = gs.today()
	var schools := []
	for b in gs.buildings:
		if gs.owned_by_player(b) and str(gs.building_def(b).get("product", "")) == "educacion" and b["status"] == "activo":
			schools.append(b)
	# Bajas: edad fuera de rango, escuela cerrada o sin pago.
	for c in gs.citizens.values():
		if c.school_id < 0:
			continue
		var b: Dictionary = gs.get_building(c.school_id)
		if b.is_empty() or b["status"] != "activo" or not _age_ok(gs, b, c.age_years(today)):
			_graduate_check(gs, c, b)
			c.school_id = -1
			c.career = ""
	for b in schools:
		var ld: Dictionary = gs.level_def(b)
		var enrolled := students_of(gs, b)
		var cap := capacity(gs, b)
		# Matrícula de nuevos alumnos.
		if enrolled.size() < cap:
			for c in gs.citizens.values():
				if enrolled.size() >= cap:
					break
				if c.school_id >= 0 or gs.is_player(c.id) or not _age_ok(gs, b, c.age_years(today)):
					continue
				var grants_now := int(ld.get("grants_education", 1))
				if grants_now >= 3:
					# Universidad: requiere secundaria y aún no tener profesión.
					if c.profession != "" or c.education < int(ld.get("min_student_education", 2)):
						continue
					var careers: Array = b.get("careers", GameData.profession_ids())
					if careers.is_empty():
						continue
					c.career = _pick_career(gs, careers)
				elif c.education >= grants_now:
					continue
				c.school_id = int(b["id"])
				enrolled.append(c)
		# Pensión y avance académico.
		var fee := float(b.get("fee", 0.0))
		for c in enrolled.duplicate():
			if fee > 0.0:
				var payers := []
				for pid in c.parent_ids:
					if gs.citizens.has(pid):
						payers.append(gs.citizens[pid])
				if payers.is_empty():
					payers = [c]
				if not PopulationSim.pay_with(gs, payers, fee):
					c.school_id = -1
					continue
				BusinessSim.earn(gs, b, fee, "ventas")
			var grants := int(ld.get("grants_education", 1))
			if grants >= 3:
				c.uni_years += 1.0 / 12.0
			else:
				c.school_years += 1.0 / 12.0
				c.school_level = maxi(c.school_level, grants)
			c.skills["ciencia"] = minf(100.0, float(c.skills.get("ciencia", 0.0)) + 0.4)
			c.skills["comercio"] = minf(100.0, float(c.skills.get("comercio", 0.0)) + 0.1)
			_graduate_check(gs, c, b)
		b["students"] = students_of(gs, b).size()


## Asigna la carrera con menos profesionales en el pueblo entre las ofrecidas.
static func _pick_career(gs, careers: Array) -> String:
	var count := {}
	for c in gs.citizens.values():
		if c.profession != "":
			count[c.profession] = int(count.get(c.profession, 0)) + 1
		if c.career != "":
			count[c.career] = int(count.get(c.career, 0)) + 1
	var best: String = careers[0]
	for k in careers:
		if int(count.get(k, 0)) < int(count.get(best, 0)):
			best = k
	return best


static func _age_ok(gs, b: Dictionary, age: int) -> bool:
	var ld: Dictionary = gs.level_def(b)
	return age >= int(ld.get("min_age", 6)) and age <= int(ld.get("max_age", 15))


## Sube el nivel educativo al completar los años requeridos.
static func _graduate_check(gs, c: Citizen, _b: Dictionary) -> void:
	var years: Dictionary = GameData.game.get("education_years", {"1": 4, "2": 8, "3": 3})
	var new_level := c.education
	if c.uni_years >= float(years.get("3", 3)) and c.education >= 2 and c.career != "":
		new_level = maxi(new_level, 3)
		c.profession = c.career
		c.career = ""
		c.school_id = -1
		var psk := str(GameData.professions.get("professions", {}).get(c.profession, {}).get("skill", "ciencia"))
		c.skills[psk] = minf(100.0, float(c.skills.get(psk, 0.0)) + 25.0)
		gs.notify("%s se graduó de la universidad: %s." % [c.full_name(), GameData.profession_label(c.profession)], "importante")
	elif c.school_years >= float(years.get("2", 8)) and c.school_level >= 2:
		new_level = maxi(new_level, 2)
	elif c.school_years >= float(years.get("1", 4)):
		new_level = maxi(new_level, 1)
	if new_level > c.education:
		c.education = new_level
		c.skills["ciencia"] = minf(100.0, float(c.skills.get("ciencia", 0.0)) + 8.0)
		gs.count("graduates")
		if new_level == 2:
			gs.notify("%s se graduó (%s)." % [c.full_name(), GameData.education_label(new_level)], "info")
