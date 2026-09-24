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
