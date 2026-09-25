class_name HeirsSim
extends RefCounted
## Sección C — talentos, educación de herederos, orden de herederos y bonos del jefe de familia.
## Estado en GameState.player["familia"] = {talents: {id: {talento: 0-100}}, edu: {id: {plan, focus, months}},
## heir_order: [ids]}. Parámetros en data/dynasty.json → "talents", "education".
##   - Cada persona tiene talentos innatos (5-35 según su semilla); a la familia del jugador se le guardan
##     y suben con la educación que pagues (tutor, colegio, universidad o carrera en el extranjero).
##   - El jefe de familia da bonos moderados según sus talentos (ver head_bonus).
##   - El jugador decide el orden de herederos: al morir hereda el primero vivo de la lista.

const TALENTS := ["negocios", "politica", "ciencia", "artes", "oficio"]


static func dcfg() -> Dictionary:
	return GameData.extra("dynasty")


static func tcfg() -> Dictionary:
	return dcfg().get("talents", {})


static func ecfg() -> Dictionary:
	return dcfg().get("education", {})


## Estado de la familia (con valores por defecto para partidas antiguas).
static func state(gs) -> Dictionary:
	var f: Dictionary = gs.player.get("familia", {})
	for k in ["talents", "edu"]:
		if not f.has(k) or typeof(f[k]) != TYPE_DICTIONARY:
			f[k] = {}
	if not f.has("heir_order") or typeof(f["heir_order"]) != TYPE_ARRAY:
		f["heir_order"] = []
	elif f["heir_order"].any(func(x): return typeof(x) != TYPE_INT):
		f["heir_order"] = f["heir_order"].map(func(x): return int(x))   # Partidas guardadas en JSON.
	gs.player["familia"] = f
	return f


static func talent_label(k: String) -> String:
	return str(tcfg().get("labels", {}).get(k, k.capitalize()))


# --- Talentos ---------------------------------------------------------------------------------------

## Talento innato (determinista por persona).
static func innate(c: Citizen, k: String) -> float:
	var r: Array = tcfg().get("innate", [5, 35])
	var lo := int(r[0])
	var span := maxi(1, int(r[1]) - lo + 1)
	var h := absi(hash("%d:%s" % [c.visual_seed, k]))
	return float(lo + h % span)


## Talentos estimados de alguien que no es de tu familia (innato + estudios + oficio).
static func derived(c: Citizen) -> Dictionary:
	var sk: Dictionary = c.skills
	var edu := float(c.education) * 6.0
	var out := {}
	out["negocios"] = innate(c, "negocios") + edu + float(sk.get("comercio", 0.0)) * 0.25
	out["politica"] = innate(c, "politica") + edu + float(c.experience) * 0.3
	out["ciencia"] = innate(c, "ciencia") + edu + (float(sk.get("ciencia", 0.0)) + float(sk.get("medicina", 0.0))) * 0.2
	out["artes"] = innate(c, "artes") + edu * 0.5 + float(sk.get("artesania", 0.0)) * 0.2
	var craft := 0.0
	for s in ["agricultura", "construccion", "mineria", "artesania"]:
		craft = maxf(craft, float(sk.get(s, 0.0)))
	out["oficio"] = innate(c, "oficio") + craft * 0.25
	for k in out:
		out[k] = snappedf(clampf(float(out[k]), 0.0, 100.0), 0.1)
	return out


static func talents(gs, c: Citizen) -> Dictionary:
	if c == null:
		return {}
	var st: Dictionary = state(gs)["talents"]
	if st.has(str(c.id)):
		return st[str(c.id)]
	return derived(c)


static func talent(gs, c: Citizen, k: String) -> float:
	return float(talents(gs, c).get(k, 0.0))


## Guarda los talentos de un familiar (desde ese momento solo cambian con la educación).
static func ensure_talents(gs, c: Citizen) -> Dictionary:
	var st: Dictionary = state(gs)["talents"]
	var key := str(c.id)
	if not st.has(key):
		var t := derived(c)
		# Hijos: algo de los padres.
		var parents := []
		for pid in c.parent_ids:
			if gs.citizens.has(pid):
				parents.append(gs.citizens[pid])
		if not parents.is_empty():
			for k in TALENTS:
				var avg := 0.0
				for p in parents:
					avg += talent(gs, p, k)
				avg /= parents.size()
				t[k] = snappedf(clampf(float(t[k]) + (avg - 20.0) * 0.2, 0.0, 100.0), 0.1)
		st[key] = t
	return st[key]


static func add_talent(gs, c: Citizen, k: String, amount: float) -> void:
	var t := ensure_talents(gs, c)
	t[k] = snappedf(clampf(float(t.get(k, 0.0)) + amount, 0.0, 100.0), 0.01)


static func best_talent(gs, c: Citizen) -> String:
	var t := talents(gs, c)
	var best := "negocios"
	for k in TALENTS:
		if float(t.get(k, 0.0)) > float(t.get(best, 0.0)):
			best = k
	return best


static func talents_text(gs, c: Citizen) -> String:
	var t := talents(gs, c)
	var parts := []
	for k in TALENTS:
		parts.append("%s %d" % [talent_label(k), int(float(t.get(k, 0.0)))])
	return ", ".join(parts)


# --- Familia ----------------------------------------------------------------------------------------

## Familiares del jugador: cónyuge, hijos (y adoptados), hermanos y padres vivos.
static func family_members(gs) -> Array:
	var p: Citizen = gs.player_citizen()
	var out := []
	if p == null:
		return out
	var add := func(id: int):
		if gs.citizens.has(id) and id != p.id:
			var c: Citizen = gs.citizens[id]
			if not out.has(c):
				out.append(c)
	if p.spouse_id >= 0:
		add.call(p.spouse_id)
	for id in p.children_ids:
		add.call(id)
	for c in siblings(gs, p):
		add.call(c.id)
	for id in p.parent_ids:
		add.call(id)
	return out


static func siblings(gs, p: Citizen) -> Array:
	var out := []
	if p.parent_ids.is_empty():
		return out
	for pid in p.parent_ids:
		var par: Citizen = gs.citizens.get(pid)
		if par == null:
			continue
		for kid in par.children_ids:
			if kid != p.id and gs.citizens.has(kid) and not out.has(gs.citizens[kid]):
				out.append(gs.citizens[kid])
	# Padres ya muertos: hermanos por padres en común.
	if out.is_empty():
		for c in gs.citizens.values():
			if c.id != p.id and c.parent_ids.any(func(x): return p.parent_ids.has(x)):
				out.append(c)
	return out


static func relation_of(gs, c: Citizen) -> String:
	var p: Citizen = gs.player_citizen()
	if p == null:
		return ""
	if c.id == p.id:
		return "Tú"
	if c.id == p.spouse_id:
		return "Cónyuge"
	if p.children_ids.has(c.id):
		return "Hijo(a)"
	if p.parent_ids.has(c.id):
		return "Padre/Madre"
	if siblings(gs, p).has(c):
		return "Hermano(a)"
	return "Familiar"


# --- Educación ----------------------------------------------------------------------------------------

static func plan_def(plan: String) -> Dictionary:
	return ecfg().get("plans", {}).get(plan, {})


static func plan_ids() -> Array:
	return ecfg().get("plans", {}).keys()


static func plan_fee(gs, plan: String) -> float:
	return float(plan_def(plan).get("fee", 0.0)) * gs.price_mult()


static func edu_of(gs, c: Citizen) -> Dictionary:
	return state(gs)["edu"].get(str(c.id), {"plan": "ninguna", "focus": "negocios", "months": {}})


static func plan_block_reason(gs, c: Citizen, plan: String) -> String:
	var d := plan_def(plan)
	if d.is_empty():
		return "Plan desconocido"
	if plan == "ninguna":
		return ""
	var p: Citizen = gs.player_citizen()
	if p == null or not (p.children_ids.has(c.id) or c.id == p.spouse_id or siblings(gs, p).has(c)):
		return "Solo para tu familia"
	var age: int = c.age_years(gs.today())
	if age < int(d.get("min_age", 0)) or age > int(d.get("max_age", 200)):
		return "Edad %d-%d" % [int(d.get("min_age", 0)), int(d.get("max_age", 200))]
	if gs.era() < int(d.get("min_era", 1)):
		return "Disponible desde la %s" % GameData.era_label(int(d.get("min_era", 1)))
	if c.education < int(d.get("min_education", 0)):
		return "Requiere %s" % GameData.education_label(int(d.get("min_education", 0)))
	return ""


static func set_plan(gs, c: Citizen, plan: String, focus := "") -> String:
	var r := plan_block_reason(gs, c, plan)
	if r != "":
		return r
	if focus == "" or not TALENTS.has(focus):
		focus = str(edu_of(gs, c).get("focus", best_talent(gs, c)))
	ensure_talents(gs, c)
	var e := edu_of(gs, c).duplicate(true)
	e["plan"] = plan
	e["focus"] = focus
	state(gs)["edu"][str(c.id)] = e
	if plan == "ninguna":
		return "%s ya no recibe educación extra." % c.first_name
	return "%s: %s enfocado en %s (%s/mes)." % [c.first_name, plan_def(plan).get("label", plan), talent_label(focus), Fmt.money(plan_fee(gs, plan))]


## Cobra las cuotas y sube talentos (una vez al mes).
static func monthly(gs) -> void:
	var p: Citizen = gs.player_citizen()
	if p == null:
		return
	var st := state(gs)
	for c in family_members(gs):
		ensure_talents(gs, c)
	ensure_talents(gs, p)
	var free_gain := float(ecfg().get("school_free_gain", 0.3))
	for id in p.children_ids:
		var k: Citizen = gs.citizens.get(id)
		if k != null and k.school_id >= 0:
			for t in TALENTS:
				add_talent(gs, k, t, free_gain * (0.5 if t == "artes" or t == "oficio" else 1.0))
	var edu: Dictionary = st["edu"]
	for key in edu.keys():
		var c: Citizen = gs.citizens.get(int(key))
		if c == null:
			edu.erase(key)
			continue
		var e: Dictionary = edu[key]
		var plan := str(e.get("plan", "ninguna"))
		if plan == "ninguna":
			continue
		var reason := plan_block_reason(gs, c, plan)
		if reason != "":
			e["plan"] = "ninguna"
			gs.notify("%s terminó %s (%s)." % [c.full_name(), str(plan_def(plan).get("label", plan)).to_lower(), reason], "familia")
			continue
		var fee := plan_fee(gs, plan)
		if fee > 0.0:
			if gs.money < fee:
				gs.notify("No alcanzó el dinero para la educación de %s este mes." % c.first_name, "familia")
				continue
			gs.add_money(-fee)
			_pay_fee(gs, plan, fee)
		study_month(gs, c, plan, str(e.get("focus", "negocios")))


## Un mes de estudio: sube el talento elegido y un poco los demás.
static func study_month(gs, c: Citizen, plan: String, focus: String) -> void:
	var d := plan_def(plan)
	for t in TALENTS:
		var gain := float(d.get("all", 0.0))
		if t == focus:
			gain += float(d.get("focus", 0.0))
		add_talent(gs, c, t, gain)
	var e: Dictionary = state(gs)["edu"].get(str(c.id), {"plan": plan, "focus": focus, "months": {}})
	var months: Dictionary = e.get("months", {})
	months[plan] = int(months.get(plan, 0)) + 1
	e["months"] = months
	state(gs)["edu"][str(c.id)] = e


## Adónde va la cuota (economía cerrada): tutor → un adulto educado; colegio/universidad → tesoro;
## extranjero → sale del pueblo (como una importación).
static func _pay_fee(gs, plan: String, fee: float) -> void:
	match plan:
		"tutor":
			var best: Citizen = null
			var fam := family_members(gs)
			for c in gs.citizens.values():
				if gs.is_player(c.id) or fam.has(c) or c.age_years(gs.today()) < 20:
					continue
				if best == null or c.education > best.education or (c.education == best.education and c.id < best.id):
					best = c
			if best != null:
				best.money += fee
			else:
				GovSim.add_treasury(gs, fee)
		"colegio", "universidad":
			GovSim.add_treasury(gs, fee)
		_:
			pass


# --- Bonos del jefe de familia -------------------------------------------------------------------------

## Bono de 0 a bonus_max según el talento del jefe de familia por encima de bonus_from.
static func head_bonus(gs, k: String) -> float:
	var p: Citizen = gs.player_citizen()
	if p == null:
		return 0.0
	var from := float(tcfg().get("bonus_from", 40))
	var f := clampf((talent(gs, p, k) - from) / maxf(1.0, 100.0 - from), 0.0, 1.0)
	return f * float(tcfg().get("bonus_max", {}).get(k, 0.0))


## Descuento de mantenimiento de tus negocios (negocios + oficio).
static func upkeep_discount(gs) -> float:
	return head_bonus(gs, "negocios") + head_bonus(gs, "oficio")


static func research_mult(gs) -> float:
	return 1.0 + head_bonus(gs, "ciencia")


static func bonus_text(gs) -> String:
	var parts := []
	var n := upkeep_discount(gs)
	if n > 0.0:
		parts.append("−%s mantenimiento" % Fmt.pct(n * 100.0))
	var pol := head_bonus(gs, "politica")
	if pol > 0.0:
		parts.append("−%s impuesto a las ganancias" % Fmt.pct(pol * 100.0))
	var sci := head_bonus(gs, "ciencia")
	if sci > 0.0:
		parts.append("+%s investigación" % Fmt.pct(sci * 100.0))
	var art := head_bonus(gs, "artes")
	if art > 0.0:
		parts.append("+%.1f reputación/mes" % art)
	return ", ".join(parts) if not parts.is_empty() else "sin bonos (talentos bajo %d)" % int(tcfg().get("bonus_from", 40))


# --- Orden de herederos ---------------------------------------------------------------------------------

## Quiénes pueden estar en la lista: hijos (y adoptados), cónyuge y hermanos.
static func heir_pool(gs) -> Array:
	var p: Citizen = gs.player_citizen()
	var out := []
	if p == null:
		return out
	for id in p.children_ids:
		if gs.citizens.has(id):
			out.append(gs.citizens[id])
	if p.spouse_id >= 0 and gs.citizens.has(p.spouse_id):
		out.append(gs.citizens[p.spouse_id])
	for s in siblings(gs, p):
		if not out.has(s):
			out.append(s)
	return out


static func heir_order(gs) -> Array:
	return state(gs)["heir_order"]


static func add_heir(gs, id: int) -> String:
	var order := heir_order(gs)
	if order.has(id):
		return "Ya está en la lista"
	if not heir_pool(gs).any(func(c): return c.id == id):
		return "Solo hijos, cónyuge o hermanos"
	order.append(id)
	return "%s es tu heredero n.º %d." % [gs.person_name(id), order.size()]


static func remove_heir(gs, id: int) -> String:
	heir_order(gs).erase(id)
	return "%s salió del orden de herederos." % gs.person_name(id)


## Mueve un heredero (delta −1 = subir, +1 = bajar).
static func move_heir(gs, id: int, delta: int) -> void:
	var order := heir_order(gs)
	var i := order.find(id)
	if i < 0:
		return
	var j := clampi(i + delta, 0, order.size() - 1)
	if j == i:
		return
	order.remove_at(i)
	order.insert(j, id)


## Primer heredero vivo de la lista (o null: se usa la regla anterior).
static func pick_heir(gs, dead: Citizen) -> Citizen:
	for id in heir_order(gs):
		var iid := int(id)
		if iid != dead.id and gs.citizens.has(iid):
			return gs.citizens[iid]
	return null


static func has_listed_heir(gs) -> bool:
	for id in heir_order(gs):
		if gs.citizens.has(int(id)) and not gs.is_player(int(id)):
			return true
	return false


## Tras la sucesión: la lista se conserva solo con quienes siguen siendo familia del nuevo jefe.
static func on_succession(gs, _dead: Citizen, _heir: Citizen) -> void:
	var pool := heir_pool(gs).map(func(c): return c.id)
	var keep := []
	for id in heir_order(gs):
		if pool.has(int(id)) and not keep.has(int(id)):
			keep.append(int(id))
	state(gs)["heir_order"] = keep
