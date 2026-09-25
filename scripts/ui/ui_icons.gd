class_name UIIcons
extends RefCounted
## Set de iconos propio (sin copyright): trazos simples en una rejilla de 24×24, escritos como SVG
## y rasterizados en tiempo de ejecución al tamaño pedido × sobremuestreo (nítidos en Retina).
## Se dibujan en blanco: el color se da con `modulate` o con los colores de icono del tema.
## Uso: UIIcons.tex("money", 18) → Texture2D. Lista completa: UIIcons.names(). Ver docs/UI.md.

const OVERSAMPLE := 3.0

## Contenido SVG (dentro de <svg viewBox="0 0 24 24">), con trazo blanco de 2 px por defecto.
const ICONS := {
	# Indicadores
	"money": '<circle cx="12" cy="12" r="9"/><path d="M15 9.2c-.6-1-1.7-1.5-3-1.5-1.8 0-3 .9-3 2.2 0 3 6 1.6 6 4.6 0 1.3-1.3 2.3-3 2.3-1.4 0-2.6-.6-3.1-1.6M12 6v1.7M12 16.8V18"/>',
	"population": '<circle cx="9" cy="8" r="3.2"/><path d="M3 19.5c0-3.3 2.7-5.7 6-5.7s6 2.4 6 5.7"/><circle cx="17" cy="9" r="2.5"/><path d="M16.8 13.6c2.5 0 4.4 2 4.4 4.8"/>',
	"happiness": '<circle cx="12" cy="12" r="9"/><path d="M8 14c1 1.5 2.3 2.3 4 2.3s3-.8 4-2.3M9 9.3v.8M15 9.3v.8"/>',
	"health": '<path d="M12 20s-7.5-4.6-7.5-10.2A4.3 4.3 0 0 1 12 7.3a4.3 4.3 0 0 1 7.5 2.5C19.5 15.4 12 20 12 20z"/><path d="M7.5 12.5h2.4l1.3-2.2 1.8 4 1.2-1.8h2.3"/>',
	"heart": '<path d="M12 20s-7.5-4.6-7.5-10.2A4.3 4.3 0 0 1 12 7.3a4.3 4.3 0 0 1 7.5 2.5C19.5 15.4 12 20 12 20z"/>',
	"crime": '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/><path d="M12 8v5M12 16.2v.3"/>',
	"inflation": '<path d="M18.5 5.5l-13 13"/><circle cx="7" cy="7" r="2.5"/><circle cx="17" cy="17" r="2.5"/>',
	"gdp": '<path d="M3 21V11l5 3v-3l5 3v-3l5 3V4h3v17z"/><path d="M2 21h20"/>',
	"treasury": '<ellipse cx="12" cy="6" rx="7" ry="2.5"/><path d="M5 6v4c0 1.4 3.1 2.5 7 2.5s7-1.1 7-2.5V6M5 10v4c0 1.4 3.1 2.5 7 2.5s7-1.1 7-2.5v-4M5 14v4c0 1.4 3.1 2.5 7 2.5s7-1.1 7-2.5v-4"/>',
	"employment": '<path d="M3 17.5h18v2.5H3z"/><path d="M5 17.5a7 7 0 0 1 14 0"/><path d="M10 11V6.5h4V11"/>',
	"education": '<path d="M2 9l10-5 10 5-10 5z"/><path d="M6 11v5c0 1.5 2.7 3 6 3s6-1.5 6-3v-5M22 9v6"/>',
	"trend_up": '<path d="M3 17l6-6 4 4 8-8"/><path d="M15 7h6v6"/>',
	"trend_down": '<path d="M3 7l6 6 4-4 8 8"/><path d="M15 17h6v-6"/>',
	# Secciones del juego
	"build": '<path d="M3.5 20.5l9-9"/><path d="M10 7.5l3.2-3.2c1.9-1.9 5-1.9 6.9 0l-3.1 1.3 2.2 2.2-4.8 4.8z"/>',
	"companies": '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2M3 13h18M11 13v2h2v-2"/>',
	"finance": '<path d="M3 9.5L12 4l9 5.5z"/><path d="M5.5 10v7.5M9.8 10v7.5M14.2 10v7.5M18.5 10v7.5M3 20h18"/>',
	"stats": '<path d="M3 20.5h18"/><rect x="5" y="11" width="3" height="6.5" rx=".6"/><rect x="10.5" y="5" width="3" height="12.5" rx=".6"/><rect x="16" y="8.5" width="3" height="9" rx=".6"/>',
	"economy": '<path d="M3 3.5V20.5h17.5"/><path d="M7 15l4-4.5 3 3 5.5-6.5"/><path d="M15.5 7h4v4"/>',
	"government": '<path d="M4 20.5h16M6 20.5v-7M10 20.5v-7M14 20.5v-7M18 20.5v-7M4 13.5h16M6.5 13.5a5.5 5.5 0 0 1 11 0M12 8V3M12 3h3.5v2H12"/>',
	"logistics": '<path d="M2 6h11v10.5H2zM13 9.5h4.5l3.5 3.5v3.5h-8"/><circle cx="6" cy="17.5" r="2"/><circle cx="16.5" cy="17.5" r="2"/>',
	"trade": '<path d="M3 15.5h18l-2.8 5h-12.4z"/><path d="M12 3v12.5M12 4.5l6 8.5h-6M12 7l-5 6h5"/>',
	"contracts": '<path d="M14 3H6a1 1 0 0 0-1 1v16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8z"/><path d="M14 3v5h5M8.5 12.5h7M8.5 16.5h4.5"/>',
	"transit": '<rect x="4" y="3" width="16" height="15" rx="3"/><path d="M4 11h16M7.5 21v-3M16.5 21v-3M9 6h6"/><circle cx="8" cy="14.5" r=".9"/><circle cx="16" cy="14.5" r=".9"/>',
	"utilities": '<path d="M13 2L4.5 13.5h6.5l-1 8.5 8.5-11.5h-6.5z"/>',
	"water": '<path d="M12 3s6 6.5 6 11a6 6 0 0 1-12 0c0-4.5 6-11 6-11z"/>',
	"realestate": '<path d="M3 11l9-7 9 7"/><path d="M5 9.5V20.5h14V9.5"/><path d="M10 20.5v-6h4v6"/>',
	"catalog": '<path d="M12 3l8 4.5v9L12 21l-8-4.5v-9z"/><path d="M4 7.5l8 4.5 8-4.5M12 12v9"/>',
	"research": '<path d="M9 3h6M10 3v6.2l-5.4 9.3A1.7 1.7 0 0 0 6 21h12a1.7 1.7 0 0 0 1.4-2.5L14 9.2V3"/><path d="M7.4 15.5h9.2"/>',
	"science": '<circle cx="12" cy="12" r="1.6" fill="#fff"/><ellipse cx="12" cy="12" rx="9.5" ry="3.8"/><ellipse cx="12" cy="12" rx="9.5" ry="3.8" transform="rotate(60 12 12)"/><ellipse cx="12" cy="12" rx="9.5" ry="3.8" transform="rotate(120 12 12)"/>',
	"character": '<circle cx="12" cy="8" r="4"/><path d="M4 21c0-4.4 3.6-7 8-7s8 2.6 8 7"/>',
	"family": '<circle cx="12" cy="5" r="2.3"/><circle cx="5.5" cy="18.5" r="2.3"/><circle cx="12" cy="18.5" r="2.3"/><circle cx="18.5" cy="18.5" r="2.3"/><path d="M12 7.3v8.9M12 11.5H5.5v4.7M12 11.5h6.5v4.7"/>',
	"dynasty": '<path d="M3 8l4.5 4L12 5l4.5 7L21 8l-2 10.5H5z"/><path d="M5 21h14"/>',
	"society": '<circle cx="12" cy="7" r="3"/><path d="M6.5 20c0-3.3 2.4-5.5 5.5-5.5s5.5 2.2 5.5 5.5"/><circle cx="5" cy="10" r="2"/><circle cx="19" cy="10" r="2"/><path d="M2 18c0-2 1.2-3.5 3-3.5M22 18c0-2-1.2-3.5-3-3.5"/>',
	"tourism": '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M8.5 7l1.5-3h4l1.5 3"/><circle cx="12" cy="13.5" r="3.5"/>',
	"town": '<path d="M3 21V10l5-4 5 4v11M13 21V6h8v15M2 21h20"/><path d="M7 21v-4h2v4M16 10h2M16 14h2"/>',
	"globe": '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.5 3.8 5.5 3.8 9s-1.3 6.5-3.8 9c-2.5-2.5-3.8-5.5-3.8-9S9.5 5.5 12 3z"/>',
	"map": '<path d="M3 6l6-2 6 2 6-2v14l-6 2-6-2-6 2z"/><path d="M9 4v14M15 6v14"/>',
	"road": '<path d="M8 3L4 21M16 3l4 18M12 4v3M12 10.5v3M12 17v3"/>',
	"mine": '<path d="M4 20.5l8.5-8.5"/><path d="M4.5 8c4.5-4.5 10.5-4.5 15 0-3.5-1.2-7-.8-10 1.5M16.5 4.5c1.2 3.5.8 7-1.5 10"/>',
	"key": '<circle cx="7.5" cy="15.5" r="4"/><path d="M10.5 12.5L20 3M16 7l3 3M13.5 9.5l2 2"/>',
	"trophy": '<path d="M7 4h10v5a5 5 0 0 1-10 0z"/><path d="M7 6H4a3 3 0 0 0 3 4M17 6h3a3 3 0 0 1-3 4M12 14v4M8 21h8M9 18h6"/>',
	"star": '<path d="M12 3l2.7 5.6 6.1.8-4.4 4.3 1 6.1L12 16.9l-5.4 2.9 1-6.1-4.4-4.3 6.1-.8z"/>',
	"baby": '<circle cx="12" cy="9" r="5"/><path d="M10 8.5v.4M14 8.5v.4M10.5 11.3c.9.6 2.1.6 3 0M7 20.5c.8-2.4 2.8-4 5-4s4.2 1.6 5 4"/>',
	"tomb": '<path d="M6 21V9a6 6 0 0 1 12 0v12z"/><path d="M12 9v7M9.5 11.5h5M4 21h16"/>',
	"ring": '<circle cx="12" cy="14.5" r="6"/><path d="M9.5 3.5h5L16 5.5l-4 3-4-3z"/>',
	"calendar": '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>',
	# Clima
	"sun": '<circle cx="12" cy="12" r="4.5"/><path d="M12 2v2.5M12 19.5V22M2 12h2.5M19.5 12H22M4.9 4.9l1.8 1.8M17.3 17.3l1.8 1.8M4.9 19.1l1.8-1.8M17.3 6.7l1.8-1.8"/>',
	"cloud": '<path d="M7 18.5a4.5 4.5 0 0 1-.6-9A6 6 0 0 1 17.8 9a4.8 4.8 0 0 1-.3 9.5z"/>',
	"rain": '<path d="M6.5 14.5a4 4 0 0 1-.4-8A5.5 5.5 0 0 1 16.8 6a4.3 4.3 0 0 1 .2 8.5z"/><path d="M8.5 17.5l-1 3M12.5 17.5l-1 3M16.5 17.5l-1 3"/>',
	"snow": '<path d="M6.5 14.5a4 4 0 0 1-.4-8A5.5 5.5 0 0 1 16.8 6a4.3 4.3 0 0 1 .2 8.5z"/><path d="M8 18.5v.3M12 20v.3M16 18.5v.3M10 21.5v.3M14 21.5v.3"/>',
	"storm": '<path d="M6.5 14.5a4 4 0 0 1-.4-8A5.5 5.5 0 0 1 16.8 6a4.3 4.3 0 0 1 .2 8.5z"/><path d="M12.5 13l-2.5 4h3.5l-2 4"/>',
	"fog": '<path d="M4 9h13M7 13h13M4 17h13M9 5h8"/>',
	"thermo": '<path d="M14 14.5V5a2 2 0 0 0-4 0v9.5a4 4 0 1 0 4 0z"/><path d="M12 9v7"/>',
	# Tiempo
	"pause": '<rect x="6.5" y="5" width="3.6" height="14" rx="1" fill="#fff" stroke="none"/><rect x="13.9" y="5" width="3.6" height="14" rx="1" fill="#fff" stroke="none"/>',
	"play": '<path d="M7.5 4.8v14.4L19 12z" fill="#fff" stroke-width="1.5"/>',
	"speed2": '<path d="M3 5.5v13l8.5-6.5zM12.5 5.5v13l8.5-6.5z" fill="#fff" stroke-width="1.2"/>',
	"speed3": '<path d="M1.5 6.5v11l6.5-5.5zM8.8 6.5v11l6.5-5.5zM16 6.5v11l6.5-5.5z" fill="#fff" stroke-width="1"/>',
	"realtime": '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.2 2"/>',
	"jump": '<path d="M3.5 5.5v13l8-6.5zM11.5 5.5v13l7-6.5z" fill="#fff" stroke-width="1.2"/><path d="M20.5 5v14" stroke-width="2.4"/>',
	# Interfaz
	"bell": '<path d="M6 16.5V11a6 6 0 0 1 12 0v5.5l2 2H4z"/><path d="M10 20.5a2 2 0 0 0 4 0"/>',
	"alert": '<path d="M12 3.5L2.5 20h19z"/><path d="M12 10v4.5M12 17.3v.4"/>',
	"info": '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.6v.4"/>',
	"check": '<path d="M5 12.5l4.5 4.5L19 7"/>',
	"close": '<path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>',
	"menu": '<path d="M4 6.5h16M4 12h16M4 17.5h16"/>',
	"settings": '<circle cx="12" cy="12" r="3"/><circle cx="12" cy="12" r="7"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1L7 17M17 7l2.1-2.1"/>',
	"refresh": '<path d="M20 11a8 8 0 1 0-2.3 5.7"/><path d="M20 4v7h-7"/>',
	"chevron_down": '<path d="M6 9l6 6 6-6"/>',
	"chevron_up": '<path d="M6 15l6-6 6 6"/>',
	"chevron_right": '<path d="M9 6l6 6-6 6"/>',
	"chevron_left": '<path d="M15 6l-6 6 6 6"/>',
	"updown": '<path d="M7 9.5l5-5 5 5M7 14.5l5 5 5-5"/>',
	"save": '<path d="M5 4h11l3 3v13H5z"/><path d="M8 4v5h7V4M8 20v-6h8v6"/>',
	"folder": '<path d="M3 6.5a1 1 0 0 1 1-1h5l2 2h9a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z"/>',
	"exit": '<path d="M14 4H5v16h9"/><path d="M10 12h11M17 8l4 4-4 4"/>',
	"plus": '<path d="M12 5v14M5 12h14"/>',
	"minus": '<path d="M5 12h14"/>',
	"eye": '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
	"filter": '<path d="M3 5h18l-7 8v6l-4 2v-8z"/>',
	"grid": '<rect x="3" y="3" width="7.5" height="7.5" rx="1.5"/><rect x="13.5" y="3" width="7.5" height="7.5" rx="1.5"/><rect x="3" y="13.5" width="7.5" height="7.5" rx="1.5"/><rect x="13.5" y="13.5" width="7.5" height="7.5" rx="1.5"/>',
	"list": '<path d="M9 6h11M9 12h11M9 18h11"/><circle cx="4.5" cy="6" r=".9"/><circle cx="4.5" cy="12" r=".9"/><circle cx="4.5" cy="18" r=".9"/>',
	"camera": '<circle cx="12" cy="12" r="3"/><path d="M12 2v4M12 18v4M2 12h4M18 12h4"/>',
	"difficulty_1": '<path d="M12 3c-4 4-6 7-6 10a6 6 0 0 0 12 0c0-3-2-6-6-10z"/>',
	"shield": '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/>',
	"skull": '<path d="M5 11a7 7 0 0 1 14 0c0 2.5-1 4-2.5 5v3.5h-9V16C6 15 5 13.5 5 11z"/><circle cx="9.3" cy="11.5" r="1.6"/><circle cx="14.7" cy="11.5" r="1.6"/><path d="M10.5 19.5v-2M13.5 19.5v-2"/>',
	"leaf": '<path d="M5 19c0-8 5-13.5 15-14-.5 10-6 15-14 15"/><path d="M5 20c3-5 6-8 10-10"/>',
	"anchor": '<circle cx="12" cy="5" r="2"/><path d="M12 7v14M8 11h8M4 13a8 8 0 0 0 16 0"/>',
	"mountain": '<path d="M2 20l7-12 4 6 3-4 6 10z"/><path d="M7.5 10.5l1.5 1.5 1.3-1.5"/>',
	"sprout": '<path d="M12 21v-9"/><path d="M12 12C12 8 9 5.5 4.5 5.5c0 4.5 3 6.5 7.5 6.5zM12 10c0-3.5 2.5-6 7.5-6 0 4-2.5 6-7.5 6z"/>',
}


static var _cache := {}


static func names() -> Array:
	return ICONS.keys()


static func has(name: String) -> bool:
	return ICONS.has(name)


## Textura del icono a `size` px lógicos (se rasteriza a size × OVERSAMPLE).
static func tex(name: String, size := 18) -> Texture2D:
	var key := "%s@%d" % [name, size]
	if _cache.has(key):
		return _cache[key]
	var body: String = ICONS.get(name, ICONS["info"])
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">%s</svg>' % body
	var img := Image.new()
	var err := img.load_svg_from_string(svg, float(size) * OVERSAMPLE / 24.0)
	var t: Texture2D
	if err != OK or img.is_empty():
		t = PlaceholderTexture2D.new()
		(t as PlaceholderTexture2D).size = Vector2(size, size)
	else:
		img.generate_mipmaps()
		var it := ImageTexture.create_from_image(img)
		it.set_size_override(Vector2i(size, size))
		t = it
	_cache[key] = t
	return t


## Casilla de verificación dibujada (para el tema).
static func checkbox(on: bool, radio := false) -> Texture2D:
	var key := "cb_%s_%s" % [on, radio]
	if _cache.has(key):
		return _cache[key]
	var shape := '<circle cx="12" cy="12" r="8.5"/>' if radio else '<rect x="3.5" y="3.5" width="17" height="17" rx="4"/>'
	var inner := ""
	if on:
		inner = '<circle cx="12" cy="12" r="4.5" fill="#EDC259" stroke="none"/>' if radio else '<path d="M7.5 12.5l3 3 6-7" stroke="#16181D" stroke-width="2.6"/>'
		shape = shape.replace("/>", ' fill="#EDC259" stroke="#EDC259"/>') if not radio else shape.replace("/>", ' stroke="#EDC259"/>')
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#9AA0AA" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">%s%s</svg>' % [shape, inner]
	var img := Image.new()
	img.load_svg_from_string(svg, 18.0 / 24.0 * OVERSAMPLE)
	var t := ImageTexture.create_from_image(img)
	t.set_size_override(Vector2i(18, 18))
	_cache[key] = t
	return t


## Círculo relleno (agarradera de deslizadores).
static func dot(size: int, color: Color) -> Texture2D:
	var key := "dot_%d_%s" % [size, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" fill="#%s" stroke="#16181D" stroke-width="2"/></svg>' % color.to_html(false)
	var img := Image.new()
	img.load_svg_from_string(svg, float(size) / 24.0 * OVERSAMPLE)
	var t := ImageTexture.create_from_image(img)
	t.set_size_override(Vector2i(size, size))
	_cache[key] = t
	return t
