class_name MarriageSim
extends RefCounted
## Sección C — matrimonio y fortuna.
##   - Ficha de patrimonio de cualquier persona (dinero, casas, empresas NPC, estatus, talentos, familia).
##   - Propuesta del jugador: la otra persona acepta o rechaza según la relación, la diferencia de
##     fortuna y estatus y su familia (nunca se obliga).
##   - Al casarse el jugador, el patrimonio del cónyuge (dinero, casas y empresas NPC) pasa a la familia:
##     solo se mueve de dueño, no se crea dinero.
##   - Matrimonios estratégicos de hijos/hermanos adultos con familias ricas del pueblo (dote o fusión de
##     empresa opcionales) o con alguien de un pueblo conectado.
## Parámetros en data/dynasty.json → "marriage".


static func cfg() -> Dictionary:
	return GameData.extra("dynasty").get("marriage", {})


# --- Patrimonio y estatus --------------------------------------------------------------------------------

static func homes_of(gs, c: Citizen) -> Array:
	var out := []
	for b in gs.buildings:
		if str(b.get("owner", "")) == "ciudadano" and int(b.get("owner_id", -1)) == c.id and not NpcBusinessSim.is_npc(b) and Housing.is_home(b):
			out.append(b)
	return out


static func businesses_of(gs, c: Citizen) -> Array:
	var out := []
	for b in NpcBusinessSim.npc_buildings(gs):
		if int(b.get("owner_id", -1)) == c.id:
			out.append(b)
	return out


## Patrimonio de una persona: {money, homes, homes_value, businesses, business_value, total}.
static func wealth(gs, c: Citizen) -> Dictionary:
	var money := maxf(0.0, c.money)
	var homes := homes_of(gs, c)
	var hv := 0.0
	for h in homes:
		hv += EconomySim.property_value(gs, h)
	var biz := businesses_of(gs, c)
	var bv := 0.0
	for b in biz:
		bv += NpcBusinessSim.valuation(gs, b) + maxf(0.0, float(b.get("reserve", 0.0)))
	return {"money": money, "homes": homes, "homes_value": hv, "businesses": biz, "business_value": bv,
		"total": money + hv + bv}


static func family_wealth(gs, c: Citizen) -> float:
	var t := 0.0
	for m in NpcBusinessSim.family_of(gs, c):
		t += float(wealth(gs, m)["total"])
	return t


static func _wealth_score(gs, amount: float) -> float:
	return clampf(log(1.0 + maxf(0.0, amount) / maxf(0.01, gs.price_mult())) / log(10.0) * 10.0, 0.0, 40.0)


## Estatus 0-100 de una persona (estudios, empresas, fortuna de su familia, talentos).
static func status(gs, c: Citizen) -> float:
	if gs.is_player(c.id):
		return player_status(gs)
	var t := HeirsSim.talents(gs, c)
	var avg := 0.0
	for k in HeirsSim.TALENTS:
		avg += float(t.get(k, 0.0))
	avg /= HeirsSim.TALENTS.size()
	var s := float(c.education) * 10.0 + businesses_of(gs, c).size() * 12.0 + _wealth_score(gs, family_wealth(gs, c)) + avg * 0.3
	if c.profession != "":
		s += 8.0
	return clampf(s, 0.0, 100.0)


static func player_status(gs) -> float:
	return clampf(PoliticsSim.reputation(gs) * 0.5 + _wealth_score(gs, EconomySim.net_worth(gs)) + gs.player_citizen().education * 4.0, 0.0, 100.0)


## Ficha para la interfaz antes de proponer.
static func sheet(gs, c: Citizen) -> Dictionary:
	var w := wealth(gs, c)
	var fam := []
	for m in NpcBusinessSim.family_of(gs, c):
		if m != c:
			fam.append({"id": m.id, "name": m.full_name(), "age": m.age_years(gs.today()), "money": m.money,
				"owner": not businesses_of(gs, m).is_empty()})
	return {"wealth": w, "family_wealth": family_wealth(gs, c), "status": status(gs, c),
		"talents": HeirsSim.talents(gs, c), "family": fam, "affinity": PlayerSim.affinity(gs, c.id)}


static func sheet_text(gs, c: Citizen) -> String:
	var sh := sheet(gs, c)
	var w: Dictionary = sh["wealth"]
	var s := "[b]Ficha de patrimonio[/b]\n"
	s += "Dinero %s · Casas %d (%s) · Empresas %d (%s)\n" % [Fmt.money(float(w["money"])), w["homes"].size(), Fmt.money(float(w["homes_value"])),
		w["businesses"].size(), Fmt.money(float(w["business_value"]))]
	if not w["businesses"].is_empty():
		s += "Empresas: %s\n" % ", ".join(w["businesses"].map(func(b): return gs.building_label(b)))
	s += "Patrimonio total %s · Fortuna de su familia %s\n" % [Fmt.money(float(w["total"])), Fmt.money(float(sh["family_wealth"]))]
	s += "Estatus %d/100 (el tuyo %d/100)\n" % [int(sh["status"]), int(player_status(gs))]
	s += "Talentos: %s\n" % HeirsSim.talents_text(gs, c)
	if not sh["family"].is_empty():
		s += "Familia: %s\n" % ", ".join(sh["family"].map(func(f): return "%s (%d)%s" % [f["name"], f["age"], " · empresario(a)" if f["owner"] else ""]))
	return s


# --- Propuesta del jugador --------------------------------------------------------------------------------

## Probabilidad de que acepte: relación + diferencia de fortuna + estatus + opinión de su familia.
static func proposal_chance(gs, c: Citizen) -> float:
	var k := cfg()
	var a := PlayerSim.affinity(gs, c.id)
	var ch := float(k.get("base", 0.1)) + a / 100.0 * float(k.get("affinity_weight", 0.8))
	var mine: float = maxf(0.0, EconomySim.net_worth(gs)) + 100.0 * gs.price_mult()
	var theirs: float = family_wealth(gs, c) + 100.0 * gs.price_mult()
	ch += clampf(log(mine / theirs) / log(10.0), -1.0, 1.0) * float(k.get("wealth_weight", 0.2))
	ch += (player_status(gs) - status(gs, c)) / 100.0 * float(k.get("status_weight", 0.15)) * 2.0
	# Su familia: cuánto te conocen sus padres (−peso si no te conocen nada).
	var parents := []
	for pid in c.parent_ids:
		if gs.citizens.has(pid):
			parents.append(PlayerSim.affinity(gs, pid))
	if not parents.is_empty():
		var avg := 0.0
		for v in parents:
			avg += float(v)
		avg /= parents.size()
		ch += (avg - 25.0) / 75.0 * float(k.get("family_weight", 0.1))
	return clampf(ch, float(k.get("min_chance", 0.03)), float(k.get("max_chance", 0.95)))


## Propuesta del jugador. roll < 0 → aleatorio.
static func propose(gs, c: Citizen, roll := -1.0) -> String:
	var r := PlayerSim.can_court(gs, c)
	if r != "":
		return r
	var a := PlayerSim.affinity(gs, c.id)
	var need := float(cfg().get("min_affinity", 20))
	if a < need:
		return "%s apenas te conoce (relación %d/%d)." % [c.first_name, int(a), int(need)]
	var chance := proposal_chance(gs, c)
	if roll < 0.0:
		roll = gs.rng.randf()
	if roll >= chance:
		PlayerSim._add_affinity(gs, c.id, -float(cfg().get("reject_affinity_loss", 8)))
		gs.notify("%s rechazó tu propuesta de matrimonio." % c.full_name(), "familia")
		return "%s dijo que no (probabilidad %d%%). Mejora la relación o tu posición." % [c.first_name, int(chance * 100.0)]
	var p: Citizen = gs.player_citizen()
	PopulationSim.marry(p, c)
	c.home_id = p.home_id
	if c.job_kind == "obra":
		c.job_id = -1
		c.job_kind = ""
	gs.count("marriages")
	var merged := merge_spouse_assets(gs, c)
	gs.notify("¡Te casaste con %s! %s" % [c.full_name(), merged], "familia")
	EventBus.citizens_moved.emit()
	return "¡%s aceptó! Ahora viven juntos. %s" % [c.first_name, merged]


## El patrimonio del cónyuge pasa a la familia: dinero, casas y empresas NPC (sin crear dinero).
static func merge_spouse_assets(gs, c: Citizen) -> String:
	var parts := []
	var biz := businesses_of(gs, c)
	for b in biz:
		# La caja de la empresa queda para el dueño (el cónyuge) y luego se une al dinero familiar.
		NpcBusinessSim._transfer_to_player(gs, b, "matrimonio")
	if not biz.is_empty():
		parts.append("%d empresa(s)" % biz.size())
	var homes := homes_of(gs, c)
	for h in homes:
		h["owner"] = "jugador"
		h["owner_id"] = -1
		h["for_sale"] = false
		EventBus.building_changed.emit(int(h["id"]))
	if not homes.is_empty():
		parts.append("%d casa(s)" % homes.size())
	var money := maxf(0.0, c.money)
	if money > 0.0:
		c.money -= money
		gs.money += money
		parts.append(Fmt.money(money))
	var hist: Array = gs.player.get("marriages_log", [])
	hist.append({"id": c.id, "name": c.full_name(), "day": gs.today(), "money": money, "homes": homes.size(), "businesses": biz.size()})
	gs.player["marriages_log"] = hist
	if parts.is_empty():
		return "No aportó patrimonio."
	return "Se unen las fortunas: %s." % ", ".join(parts)


# --- Matrimonios estratégicos (hijos y hermanos) ------------------------------------------------------------

## Familiares adultos y solteros que pueden casarse por acuerdo.
static func marriageable_relatives(gs) -> Array:
	var out := []
	var p: Citizen = gs.player_citizen()
	for c in HeirsSim.family_members(gs):
		if c.spouse_id < 0 and c.age_years(gs.today()) >= 18 and (p.children_ids.has(c.id) or HeirsSim.siblings(gs, p).has(c)):
			out.append(c)
	return out


static func can_arrange(gs, m: Citizen, t: Citizen) -> String:
	if not marriageable_relatives(gs).has(m):
		return "Solo hijos o hermanos adultos y solteros"
	if gs.is_player(t.id) or HeirsSim.family_members(gs).has(t):
		return "Es de tu familia"
	if t.gender == m.gender:
		return "Deben ser de distinto sexo"
	if t.spouse_id >= 0:
		return "Ya está casado(a)"
	var age: int = t.age_years(gs.today())
	if age < 18:
		return "Es menor de edad"
	if absi(age - m.age_years(gs.today())) > int(cfg().get("max_age_gap", 14)):
		return "Mucha diferencia de edad"
	if PopulationSim.is_related(m, t):
		return "Son parientes"
	return ""


## Candidatos del pueblo para un familiar: las familias más ricas primero (empresarios NPC).
static func strategic_candidates(gs, m: Citizen, limit := 6) -> Array:
	var out := []
	for c in gs.citizens.values():
		if can_arrange(gs, m, c) == "":
			out.append(c)
	var fw := {}
	for c in out:
		fw[c.id] = family_wealth(gs, c)
	out.sort_custom(func(a, b): return float(fw[a.id]) > float(fw[b.id]) if fw[a.id] != fw[b.id] else a.id < b.id)
	return out.slice(0, limit)


## Empresas NPC de la familia de t (para la fusión).
static func family_businesses(gs, t: Citizen) -> Array:
	var out := []
	for m in NpcBusinessSim.family_of(gs, t):
		out.append_array(businesses_of(gs, m))
	return out


static func dowry_amount(gs, t: Citizen) -> float:
	var total := 0.0
	for m in NpcBusinessSim.family_of(gs, t):
		total += maxf(0.0, m.money)
	return total * float(cfg().get("dowry_share", 0.12))


## Probabilidad de que la otra familia acepte: comparación de estatus y fortuna, talentos de tu
## familiar y relación contigo; pedir dote o fusión la bajan.
static func arrange_chance(gs, m: Citizen, t: Citizen, dowry: bool, merge: bool) -> float:
	var k := cfg()
	var ch := float(k.get("strategic_base", 0.35))
	var mine: float = maxf(0.0, EconomySim.net_worth(gs)) + 100.0 * gs.price_mult()
	var theirs: float = family_wealth(gs, t) + 100.0 * gs.price_mult()
	ch += clampf(log(mine / theirs) / log(10.0), -1.0, 1.0) * float(k.get("wealth_weight", 0.2))
	ch += (player_status(gs) - status(gs, t)) / 100.0 * float(k.get("status_weight", 0.15)) * 2.0
	var avg := 0.0
	for key in HeirsSim.TALENTS:
		avg += HeirsSim.talent(gs, m, key)
	ch += (avg / HeirsSim.TALENTS.size() - 30.0) / 100.0
	ch += PlayerSim.affinity(gs, t.id) / 100.0 * 0.2
	if dowry:
		ch -= float(k.get("strategic_dowry_penalty", 0.15))
	if merge:
		ch -= float(k.get("strategic_merge_penalty", 0.25))
	return clampf(ch, float(k.get("min_chance", 0.03)), float(k.get("max_chance", 0.95)))


## Propone el matrimonio de un familiar con alguien del pueblo. La otra familia decide.
static func arrange(gs, m: Citizen, t: Citizen, dowry := false, merge := false, roll := -1.0) -> String:
	var r := can_arrange(gs, m, t)
	if r != "":
		return r
	if merge and family_businesses(gs, t).is_empty():
		return "Su familia no tiene empresas para unir"
	var chance := arrange_chance(gs, m, t, dowry, merge)
	if roll < 0.0:
		roll = gs.rng.randf()
	if roll >= chance:
		PlayerSim._add_affinity(gs, t.id, -3.0)
		gs.notify("La familia de %s rechazó el matrimonio con %s." % [t.full_name(), m.full_name()], "familia")
		return "La familia de %s rechazó la propuesta (probabilidad %d%%)." % [t.first_name, int(chance * 100.0)]
	var extra := []
	if dowry:
		var amount := dowry_amount(gs, t)
		var fam := NpcBusinessSim.family_of(gs, t)
		var pool := 0.0
		for f in fam:
			pool += maxf(0.0, f.money)
		if amount > 0.0 and pool > 0.0:
			for f in fam:
				f.money -= maxf(0.0, f.money) / pool * amount
			gs.add_money(amount)
			extra.append("dote de %s" % Fmt.money(amount))
	if merge:
		var biz := family_businesses(gs, t)
		for b in biz:
			NpcBusinessSim._transfer_to_player(gs, b, "fusión familiar")
		extra.append("fusión de %s" % ", ".join(biz.map(func(b): return gs.building_label(b))))
	PopulationSim.marry(m, t)
	PopulationSim._house_couple(gs, m, t)
	gs.count("marriages")
	var text := "¡Boda! %s se casó con %s%s." % [m.full_name(), t.full_name(), " (" + ", ".join(extra) + ")" if not extra.is_empty() else ""]
	gs.notify(text, "familia")
	EventBus.citizens_moved.emit()
	return text


static func foreign_towns(gs) -> Array:
	return TradeSim.connected_towns(gs)


static func foreign_chance(gs, m: Citizen) -> float:
	var avg := 0.0
	for key in HeirsSim.TALENTS:
		avg += HeirsSim.talent(gs, m, key)
	var ch := float(cfg().get("foreign_base", 0.55)) + (PoliticsSim.reputation(gs) - 50.0) / 200.0 + (avg / HeirsSim.TALENTS.size() - 30.0) / 150.0
	return clampf(ch, 0.1, 0.9)


static func foreign_cost(gs) -> float:
	return float(cfg().get("foreign_wedding_cost", 150)) * gs.price_mult()


## Matrimonio con alguien de un pueblo conectado: se paga la boda (a ciudadanos) y, si aceptan,
## la pareja llega al pueblo (como un inmigrante).
static func arrange_foreign(gs, m: Citizen, roll := -1.0) -> String:
	if not marriageable_relatives(gs).has(m):
		return "Solo hijos o hermanos adultos y solteros"
	var towns := foreign_towns(gs)
	if towns.is_empty():
		return "Necesitas una conexión con otro pueblo"
	var cost := foreign_cost(gs)
	if gs.money < cost:
		return "La boda cuesta %s" % Fmt.money(cost)
	gs.add_money(-cost)
	PoliticsSim.spread_to_citizens(gs, cost, 6)
	var conn: Dictionary = towns[0]
	var town_name := str(conn.get("town_name", conn.get("town_id", "otro pueblo")))
	var chance := foreign_chance(gs, m)
	if roll < 0.0:
		roll = gs.rng.randf()
	if roll >= chance:
		gs.notify("Una familia de %s rechazó el matrimonio con %s." % [town_name, m.full_name()], "familia")
		return "La familia de %s rechazó la propuesta (probabilidad %d%%)." % [town_name, int(chance * 100.0)]
	var age := clampi(m.age_years(gs.today()) + gs.rng.randi_range(-4, 3), 18, 60)
	var t := PopulationSim.create_citizen(gs, "F" if m.gender == "M" else "M", age, PopulationSim.random_surname(gs))
	t.education = maxi(t.education, 1)
	PopulationSim.marry(m, t)
	t.home_id = m.home_id
	gs.count("marriages")
	gs.count("immigrants")
	EventBus.citizen_born.emit(t.id)
	var text := "¡Boda! %s se casó con %s, de %s, que llega a vivir al pueblo." % [m.full_name(), t.full_name(), town_name]
	gs.notify(text, "familia")
	EventBus.citizens_moved.emit()
	return text
