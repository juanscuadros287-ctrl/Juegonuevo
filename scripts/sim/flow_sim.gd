class_name FlowSim
extends RefCounted
## Contabilidad de flujos de dinero: "no se gana ni se pierde de la nada".
## Todo pago tiene origen, destino y motivo. Este módulo da los destinos que no son una persona:
##   - Cuenta externa  gs.economy["external"] = {balance, out{motivo}, in{motivo}, month{...}}:
##     el resto del mundo. `balance` = lo que salió neto de la economía (importaciones, repuestos,
##     turismo al exterior…) menos lo que entró (exportaciones, remesas, créditos de fuera).
##   - Bancos  gs.economy["banks"] = {cash}: caja de los bancos (externo y NPC). Prestar la baja;
##     cuotas e intereses la suben. Puede quedar negativa (fondeo del banco en el exterior).
##   - Proveedores locales (pay_local): vecinos que venden lo que cultivan, recogen o reparan y
##     empresas NPC del pueblo. Sin nadie que venda, lo recibe el mercado municipal (tesoro).
## pockets(gs) suma todos los bolsillos; pockets.total + external.balance es constante
## (tests/test_conservacion.gd lo verifica mes a mes).

const EXT := "external"
const BANKS := "banks"


static func cfg() -> Dictionary:
	return GameData.economy.get("flows", {})


# --- Cuenta externa -----------------------------------------------------------------------------

static func _ext(gs) -> Dictionary:
	if not gs.economy.has(EXT) or not (gs.economy[EXT] is Dictionary):
		gs.economy[EXT] = {"balance": 0.0, "out": {}, "in": {}, "month": {}}
	return gs.economy[EXT]


## Dinero que sale de la economía hacia el exterior (el que paga ya lo descontó).
static func external_out(gs, amount: float, reason: String) -> void:
	if amount == 0.0:
		return
	var e := _ext(gs)
	e["balance"] = float(e.get("balance", 0.0)) + amount
	var o: Dictionary = e["out"]
	o[reason] = float(o.get(reason, 0.0)) + amount
	var m: Dictionary = e["month"]
	m["out"] = float(m.get("out", 0.0)) + amount


## Dinero que entra desde el exterior (el que cobra ya lo sumó).
static func external_in(gs, amount: float, reason: String) -> void:
	if amount == 0.0:
		return
	var e := _ext(gs)
	e["balance"] = float(e.get("balance", 0.0)) - amount
	var i: Dictionary = e["in"]
	i[reason] = float(i.get(reason, 0.0)) + amount
	var m: Dictionary = e["month"]
	m["in"] = float(m.get("in", 0.0)) + amount


static func external_balance(gs) -> float:
	return float(_ext(gs).get("balance", 0.0))


## Cierre de mes: guarda el neto del mes (para gráficas) y reinicia el acumulado.
static func close_month(gs) -> void:
	var e := _ext(gs)
	e["last_month"] = e["month"]
	e["month"] = {}


# --- Bancos --------------------------------------------------------------------------------------

static func banks_cash(gs) -> float:
	return float(gs.economy.get(BANKS, {}).get("cash", 0.0))


## Movimiento de la caja de los bancos (positivo: el banco cobra; negativo: el banco presta/paga).
static func bank_move(gs, amount: float) -> void:
	if not gs.economy.has(BANKS) or not (gs.economy[BANKS] is Dictionary):
		gs.economy[BANKS] = {"cash": 0.0}
	gs.economy[BANKS]["cash"] = float(gs.economy[BANKS].get("cash", 0.0)) + amount


# --- Gastos con destino ---------------------------------------------------------------------------

## Gasto de un negocio en mantenimiento, insumos u obra: `import_share` del monto se importa
## (sale a la cuenta externa con su motivo) y el resto lo cobran proveedores del pueblo.
static func spend(gs, amount: float, reason: String, import_share := -1.0) -> void:
	if amount <= 0.0:
		return
	if import_share < 0.0:
		import_share = float(cfg().get("import_share", {}).get(reason, cfg().get("default_import_share", 0.3)))
	import_share = clampf(import_share, 0.0, 1.0)
	var imp := amount * import_share
	if imp > 0.0:
		external_out(gs, imp, reason)
	pay_local(gs, amount - imp)


## Paga a proveedores del pueblo: primero empresas NPC activas (su caja), luego vecinos sin
## empleo (venden lo que cultivan o reparan); sin nadie, lo recibe el mercado municipal (tesoro).
static func pay_local(gs, amount: float) -> void:
	if amount <= 0.0:
		return
	NpcBusinessSim._pay_local(gs, amount)


# --- Bolsillos -----------------------------------------------------------------------------------

## Todo el dinero del país cargado, por bolsillo. "total" no incluye la cuenta externa.
static func pockets(gs) -> Dictionary:
	var cit := 0.0
	for c in gs.citizens.values():
		cit += c.money
	var npc := 0.0
	var other_res := 0.0
	for b in gs.buildings:
		var r := float(b.get("reserve", 0.0))
		if NpcBusinessSim.is_npc(b):
			npc += r
		else:
			other_res += r
	var towns := 0.0
	for t in TradeSim.towns(gs):
		towns += float(t.get("cash", 0.0))
	var muni := 0.0
	for k in gs.map.get("regions", {}):
		var reg = gs.map["regions"][k]
		if reg is Dictionary:
			muni += float(reg.get("treasury", 0.0))
	var stock := StockSim.world_cash(gs) if not gs.world_econ.is_empty() else 0.0
	var ins := InsuranceSim.external_cash(gs) if not gs.world_econ.is_empty() else 0.0
	var p := {
		"player": float(gs.money), "citizens": cit, "npc_firms": npc, "reserves": other_res,
		"treasury": float(gs.government.get("treasury", 0.0)), "municipal": muni, "towns": towns,
		"banks": banks_cash(gs), "stock": stock, "insurers": ins,
	}
	var total := 0.0
	for k in p:
		total += float(p[k])
	p["total"] = total
	p["external"] = external_balance(gs)
	return p


## Total conservado: bolsillos + lo que salió neto al exterior. Debe ser constante.
static func conserved_total(gs) -> float:
	var p := pockets(gs)
	return float(p["total"]) + float(p["external"])
