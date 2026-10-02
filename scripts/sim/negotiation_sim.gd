class_name NegotiationSim
extends RefCounted
## Sección H — Recomprar algo a su dueño (terreno o apartamento) exige negociar, como en la vida real:
## unos piden alto, otros bajo (necesitan dinero) y otros no quieren vender. La personalidad sale de un
## hash determinista (semilla + bien + dueño): el mismo dueño responde igual al mismo bien.
## Modificadores: apego (años que lleva siendo dueño, hasta +30 %) y necesidad de dinero (ahorros bajos: −8 %).
## Parámetros en data/terrenos_costos.json → negotiation.


static func cfg() -> Dictionary:
	return GameData.extra("terrenos_costos").get("negotiation", {})


static func _h(gs, key: String, owner_id: int, salt: int) -> float:
	var h: int = int(gs.settings.get("seed", 1)) * 2654435761 ^ key.hash() * 40503 ^ (owner_id + 7) * 2246822519 ^ salt * 3266489917
	h = ((h ^ (h >> 15)) * 0x2c1b3c6d) & 0xFFFFFFFF
	h = ((h ^ (h >> 12)) * 0x297a2d39) & 0xFFFFFFFF
	h = h ^ (h >> 15)
	return float(h & 0xFFFFFF) / 16777216.0


## Personalidad del dueño frente a ese bien: {kind, label, ask (precio que pide), ratio (ask/valor)}.
## since_day: desde cuándo es dueño (-1 = desconocido).
static func profile(gs, key: String, value: float, owner_id: int, since_day := -1) -> Dictionary:
	var kinds: Dictionary = cfg().get("kinds", {})
	var total := 0.0
	for k in kinds:
		total += float(kinds[k].get("weight", 0.0))
	var pick := _h(gs, key, owner_id, 1) * maxf(0.0001, total)
	var kind := "normal"
	var acc := 0.0
	for k in ["se_niega", "alto", "normal", "bajo"]:
		if not kinds.has(k):
			continue
		acc += float(kinds[k].get("weight", 0.0))
		if pick <= acc:
			kind = k
			break
	var kd: Dictionary = kinds.get(kind, {"ask": [1.05, 1.2], "label": "Precio razonable"})
	var rg: Array = kd.get("ask", [1.05, 1.2])
	var ratio := lerpf(float(rg[0]), float(rg[1]), _h(gs, key, owner_id, 2))
	if since_day != -1:
		var years := maxf(0.0, float(gs.today() - since_day) / 365.0)
		ratio *= 1.0 + minf(float(cfg().get("attachment_max", 0.3)), years * float(cfg().get("attachment_per_year", 0.03)))
	var c: Citizen = gs.citizens.get(owner_id)
	if c != null and c.money < value * 0.1 and kind != "se_niega":
		ratio *= 0.92   # Necesita el dinero.
	return {"kind": kind, "label": str(kd.get("label", kind)), "ratio": ratio, "ask": snappedf(value * ratio, 1.0)}


## Respuesta a una oferta: {ok, counter (precio que pide si contraoferta, 0 si no), text}.
static func respond(gs, key: String, value: float, owner_id: int, amount: float, since_day := -1) -> Dictionary:
	var p := profile(gs, key, value, owner_id, since_day)
	var ask := float(p["ask"])
	if amount >= ask:
		return {"ok": true, "counter": 0.0, "text": "Acepta %s." % Fmt.money(amount), "profile": p}
	if str(p["kind"]) == "se_niega":
		return {"ok": false, "counter": 0.0, "text": "No quiere vender (solo lo pensaría por mucho más de lo que vale).", "profile": p}
	if amount >= ask * float(cfg().get("counter_band", 0.88)):
		return {"ok": false, "counter": ask, "text": "Contraoferta: lo deja en %s." % Fmt.money(ask), "profile": p}
	return {"ok": false, "counter": 0.0, "text": "Rechaza: %s le parece poco (%s)." % [Fmt.money(amount), str(p["label"]).to_lower()], "profile": p}
