class_name Fmt
extends RefCounted
## Utilidades de formato de texto.


static func thousands(v: float) -> String:
	var neg := v < 0.0
	var s := str(int(roundf(absf(v))))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "." + out
	return ("-" if neg else "") + out


static func money(v: float) -> String:
	return GameData.currency() + thousands(v)


static func pct(v: float) -> String:
	return "%d%%" % int(roundf(v))


## Porcentaje con un decimal si es pequeño ("2,5%"), entero si no.
static func pct_1(v: float) -> String:
	if absf(v) < 10.0:
		return String.num(v, 1).replace(".", ",") + "%"
	return "%d%%" % int(roundf(v))


static func money2(v: float) -> String:
	return GameData.currency() + String.num(v, 2).replace(".", ",")


## Número compacto para ejes y tarjetas: 950 · 1,2 mil · 3,4 M.
static func compact(v: float) -> String:
	var a := absf(v)
	var sgn := "-" if v < 0.0 else ""
	if a >= 1000000.0:
		return sgn + String.num(a / 1000000.0, 1 if a < 10000000.0 else 0).replace(".", ",") + " M"
	if a >= 10000.0:
		return sgn + String.num(a / 1000.0, 0) + " mil"
	if a >= 1000.0:
		return sgn + String.num(a / 1000.0, 1).replace(".", ",") + " mil"
	if a >= 100.0 or is_equal_approx(a, roundf(a)):
		return sgn + str(int(roundf(a)))
	return sgn + String.num(a, 1).replace(".", ",")


static func money_compact(v: float) -> String:
	if v < 0.0:
		return "-" + GameData.currency() + compact(-v)
	return GameData.currency() + compact(v)


## Fecha corta a partir de un día absoluto: "mar 1703".
static func short_date(day: int) -> String:
	var d := TimeManager.date_from_day(day, TimeManager.start_year())
	var parts := d.split(" de ")
	if parts.size() >= 3:
		return "%s %s" % [parts[1].substr(0, 3), parts[2].split(" ")[0]]
	return d
