class_name TransportDivSim
extends RefCounted
## División de transporte (pedido: "si se arma algo de transporte, tiene que ser una empresa totalmente aparte o un
## ministerio de transporte dentro de la misma empresa, para que entre en las finanzas").
## Edificios de transporte: los de producto "transporte" (central de transporte, caballeriza, depósito de camiones,
## cochera de tren, astillero, hangar) y los del sector Transporte (empresa de buses, estación, puerto, aeropuerto).
## Por cada uno el jugador elige (b["transport_org"]):
##   - "interna" (por defecto): sus costos (sueldos, combustible, alimento, mantenimiento) se REPARTEN cada mes entre
##     los negocios que usaron sus envíos, según las unidades·km transportadas (sin mover dinero). Aparecen en el
##     costeo de cada fábrica (CostSim) como "transporte asignado".
##   - "empresa": razón social propia (b["company_name"], forma legal de legal_types) con su libro contable. Cobra un
##     flete a tus negocios por cada envío (tarifa de mercado o la que fijes, b["freight_rate"] por unidad·km): el
##     negocio lo registra como gasto "fletes" y la empresa como "ventas". Es un traspaso dentro de tu grupo: no
##     mueve dinero ni paga IVA y el consolidado lo elimina. Con capacidad ociosa también cobra fletes a empresas NPC
##     (dinero real que sale de su caja).
## Estado en GameState.economy["transport"]: {month {tkm, billed, npc}, last {…}, alloc {bid: {amount, by}}, total_billed}.


static func cfg() -> Dictionary:
	return GameData.extra("terrenos_costos").get("transport", {})


static func is_transport_def(def: Dictionary) -> bool:
	return str(def.get("product", "")) == "transporte" or str(def.get("sector", "")) == "Transporte"


static func is_transport(gs, b: Dictionary) -> bool:
	return gs.owned_by_player(b) and is_transport_def(gs.building_def(b))


static func org(b: Dictionary) -> String:
	return "empresa" if str(b.get("transport_org", "interna")) == "empresa" else "interna"


static func company_name(gs, b: Dictionary) -> String:
	var n := str(b.get("company_name", ""))
	return n if n != "" else "%s %s" % [str(cfg().get("company_suffix", "Transportes")), gs.building_label(b)]


static func st(gs) -> Dictionary:
	var t = gs.economy.get("transport")
	if not (t is Dictionary):
		t = {}
	for k in ["month", "last", "alloc"]:
		if not (t.get(k) is Dictionary):
			t[k] = {}
	for k in ["month", "last"]:
		for kk in ["tkm"]:
			if not (t[k].get(kk) is Dictionary):
				t[k][kk] = {}
	gs.economy["transport"] = t
	return t


static func division(gs) -> Array:
	return gs.buildings.filter(func(b): return is_transport(gs, b))


## Cambia la organización de un edificio de transporte. org: "interna" | "empresa".
static func set_org(gs, b: Dictionary, p_org: String, name := "", legal := "sas") -> String:
	if not is_transport(gs, b):
		return "No es un edificio de transporte tuyo"
	b["transport_org"] = "empresa" if p_org == "empresa" else "interna"
	if p_org == "empresa":
		b["company_name"] = name if name != "" else company_name(gs, b)
		if GameData.legal_types.has(legal):
			b["legal"] = legal
	return ""


## Tarifa de mercado por unidad·km y manejo por unidad (× price_mult).
static func market_rate(gs) -> float:
	return float(cfg().get("rate_per_ukm", 0.04)) * gs.price_mult()


static func handling(gs) -> float:
	return float(cfg().get("handling_per_unit", 0.01)) * gs.price_mult()


static func rate_of(gs, b: Dictionary) -> float:
	var r := float(b.get("freight_rate", 0.0))
	return r if r > 0.0 else market_rate(gs)


static func set_rate(b: Dictionary, rate: float) -> void:
	b["freight_rate"] = maxf(0.0, rate)


static func freight(gs, b: Dictionary, qty: float, km: float) -> float:
	return qty * (rate_of(gs, b) * km + handling(gs))


## Negocio que se beneficia de un envío: el destino si es un negocio productor tuyo; si no, el origen; si no, -1.
static func beneficiary(gs, s: Dictionary) -> int:
	for id in [int(s.get("to", -1)), int(s.get("from", -1))]:
		var b: Dictionary = gs.get_building(id)
		if b.is_empty() or not gs.owned_by_player(b) or not BusinessSim.is_business(b):
			continue
		var def: Dictionary = gs.building_def(b)
		if is_transport_def(def) or (WarehouseSim.is_warehouse_building(gs, b) and not CostSim.is_producer_def(def)):
			continue   # Almacenes puros y transporte no son beneficiarios (sí los negocios con almacén integrado).
		return id
	return -1


## Cada día: registra los envíos nuevos (unidades·km por estación y negocio) y factura los fletes de las empresas.
static func daily(gs) -> void:
	var t := st(gs)
	var tkm: Dictionary = t["month"]["tkm"]
	var rf := float(LogisticsSim.tcfg().get("route_factor", 1.25))
	for s in LogisticsSim.shipments(gs):
		if s.has("tdiv"):
			continue
		s["tdiv"] = true
		var km := maxf(float(cfg().get("min_km", 0.2)), Vector2(float(s.get("ax", 0)), float(s.get("az", 0))).distance_to(Vector2(float(s.get("bx", 0)), float(s.get("bz", 0)))) * rf / 1000.0)
		var qty := float(s.get("qty", 0.0))
		var crew: Array = s.get("crew", [])
		var n := 0
		for pair in crew:
			n += int(pair[1])
		if n <= 0 or qty <= 0.0:
			continue
		var benef := beneficiary(gs, s)
		var purchase := float(s.get("bought", 0.0))
		if purchase > 0.0 and benef >= 0:
			CostSim.add_purchase(gs, benef, purchase * LogisticsSim.buy_unit_price(gs, str(s.get("good", ""))))
		for pair in crew:
			var stb: Dictionary = gs.get_building(int(pair[0]))
			if stb.is_empty() or not is_transport(gs, stb):
				continue
			var share := float(pair[1]) / float(n)
			var sk := str(int(stb["id"]))
			var row: Dictionary = tkm.get(sk, {})
			row[str(benef)] = float(row.get(str(benef), 0.0)) + qty * km * share
			tkm[sk] = row
			if org(stb) == "empresa" and benef >= 0 and benef != int(stb["id"]):
				var fee := snappedf(freight(gs, stb, qty * share, km), 0.01)
				if fee > 0.0:
					var payer: Dictionary = gs.get_building(benef)
					BusinessSim.ledger_add(payer, "fletes", fee)
					BusinessSim.ledger_add(stb, "ventas", fee)
					t["month"]["billed"] = float(t["month"].get("billed", 0.0)) + fee
					t["total_billed"] = float(t.get("total_billed", 0.0)) + fee
					stb["fletes_internos_mes"] = float(stb.get("fletes_internos_mes", 0.0)) + fee


## Gasto del mes anterior de un edificio (todo lo que no es ingreso ni inversión).
static func expenses(b: Dictionary, period := "last_month") -> float:
	var p: Dictionary = b.get("ledger", {}).get(period, {})
	var out := 0.0
	for k in p:
		if not k in BusinessSim.INCOME_KEYS and not k in BusinessSim.NON_PNL_KEYS:
			out += float(p[k])
	return out


static func income(b: Dictionary, period := "last_month") -> float:
	var p: Dictionary = b.get("ledger", {}).get(period, {})
	var out := 0.0
	for k in p:
		if k in BusinessSim.INCOME_KEYS:
			out += float(p[k])
	return out


## Cierre mensual (después de BusinessSim.monthly, que ya pasó el libro a last_month).
static func monthly(gs) -> void:
	var t := st(gs)
	t["last"] = t["month"]
	t["month"] = {"tkm": {}, "billed": 0.0, "npc": 0.0}
	for b in division(gs):
		b["fletes_internos_last"] = float(b.get("fletes_internos_mes", 0.0))
		b["fletes_internos_mes"] = 0.0
	_allocate(gs, t)
	_npc_clients(gs, t)


## Reparte el costo de cada estación interna entre los negocios según las unidades·km del mes.
static func _allocate(gs, t: Dictionary) -> void:
	var alloc := {}
	var tkm: Dictionary = t["last"].get("tkm", {})
	var producers := CostSim.producers(gs)
	for b in division(gs):
		if org(b) != "interna":
			continue
		var cost := expenses(b)
		if cost <= 0.0:
			continue
		var row: Dictionary = tkm.get(str(int(b["id"])), {})
		var total := 0.0
		for k in row:
			total += float(row[k])
		if total <= 0.0:
			continue   # Sin envíos: el costo queda en la división (no se asigna).
		for k in row:
			var share := cost * float(row[k]) / total
			var targets := {}
			if int(k) >= 0 and not gs.get_building(int(k)).is_empty():
				targets[int(k)] = 1.0
			else:
				# Envíos entre almacenes: a los productores según el valor que producen.
				var w := 0.0
				for p in producers:
					w += CostSim.output_value(gs, p)
				for p in producers:
					if w > 0.0:
						targets[int(p["id"])] = CostSim.output_value(gs, p) / w
			for bid in targets:
				var a: Dictionary = alloc.get(str(bid), {"amount": 0.0, "by": {}})
				var amt := share * float(targets[bid])
				a["amount"] = float(a["amount"]) + amt
				a["by"][str(int(b["id"]))] = float(a["by"].get(str(int(b["id"])), 0.0)) + amt
				alloc[str(bid)] = a
	t["alloc"] = alloc


static func allocated_to(gs, b: Dictionary) -> float:
	return float(st(gs)["alloc"].get(str(int(b["id"])), {}).get("amount", 0.0))


## Empresas de transporte con capacidad ociosa cobran fletes a empresas NPC (sale de su caja).
static func _npc_clients(gs, t: Dictionary) -> void:
	var npcs := NpcBusinessSim.npc_buildings(gs).filter(func(nb): return str(nb.get("npc_state", "")) == NpcBusinessSim.STATE_OPEN and float(nb.get("reserve", 0.0)) > 0.0)
	if npcs.is_empty():
		return
	var total_npc := 0.0
	for b in division(gs):
		if org(b) != "empresa" or not gs.is_active(b):
			continue
		var crew := LogisticsSim.crew_size(gs, b)
		if crew <= 0:
			continue
		var used := float(b.get("fletes_internos_last", 0.0))
		var cap: float = float(cfg().get("npc_per_crew", 6.0)) * crew * gs.price_mult()
		var room := maxf(0.0, cap - used * 0.5)
		for nb in npcs:
			if room <= 0.0:
				break
			var fee := minf(room, float(nb["reserve"]) * float(cfg().get("npc_max_share", 0.02)))
			fee = snappedf(fee, 0.01)
			if fee < 0.01:
				continue
			nb["reserve"] = float(nb["reserve"]) - fee
			BusinessSim.ledger_add(nb, "fletes", fee)
			BusinessSim.earn(gs, b, fee, "ventas")
			b["fletes_npc_last"] = float(b.get("fletes_npc_last", 0.0)) + fee
			room -= fee
			total_npc += fee
	t["last"]["npc"] = total_npc


## Filas para Finanzas: [{id, name, org, income, internal, npc, costs, result, allocated}] del mes anterior.
static func finance_rows(gs) -> Array:
	var out := []
	for b in division(gs):
		var inc := income(b)
		var cost := expenses(b)
		out.append({"id": int(b["id"]), "name": company_name(gs, b) if org(b) == "empresa" else gs.building_label(b),
			"org": org(b), "org_label": "Empresa aparte" if org(b) == "empresa" else "División interna",
			"income": inc, "internal": float(b.get("fletes_internos_last", 0.0)), "costs": cost, "result": inc - cost,
			"allocated": cost if org(b) == "interna" else 0.0})
	return out


## Consolidado del grupo: suma de todos tus edificios eliminando los fletes internos (no se cuentan dos veces).
static func consolidated(gs) -> Dictionary:
	var inc := 0.0
	var spend := 0.0
	var internal := 0.0
	for b in gs.buildings:
		if not gs.owned_by_player(b):
			continue
		inc += income(b)
		spend += expenses(b)
	for b in division(gs):
		internal += float(b.get("fletes_internos_last", 0.0))
	return {"income_gross": inc, "expenses_gross": spend, "internal": internal, "income": inc - internal, "expenses": spend - internal, "result": inc - spend}
