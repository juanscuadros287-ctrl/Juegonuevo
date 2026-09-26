// Gradación de color del terreno (docs/GRAFICOS.md). La usan terrain_plus y terrain_chunk_plus.
// Baja la saturación del pasto (el verde puro se veía "neón"), le da variación suave de tono por
// zonas (manchas secas y húmedas) y oscurece un poco a lo lejos para dar profundidad.

float tg_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float tg_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(tg_hash(i), tg_hash(i + vec2(1.0, 0.0)), f.x), mix(tg_hash(i + vec2(0.0, 1.0)), tg_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 terrain_grade(vec3 c, float grass, vec3 wpos, float dist) {
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	// Pasto: menos saturado y un poco más oscuro, con manchas secas (ocre) y húmedas.
	vec3 g = mix(vec3(lum), c, 0.6) * vec3(0.9, 0.84, 0.8);
	float patch = tg_noise(wpos.xz * 0.035) * 0.65 + tg_noise(wpos.xz * 0.13) * 0.35;
	g = mix(g, g * vec3(1.12, 1.0, 0.78), smoothstep(0.55, 0.85, patch) * 0.55);
	g = mix(g, g * vec3(0.85, 0.95, 0.9), smoothstep(0.45, 0.15, patch) * 0.5);
	c = mix(c, g, grass);
	// Resto (tierra, roca, arena): variación leve.
	c *= 0.95 + 0.1 * tg_noise(wpos.xz * 0.5);
	c = mix(c, c * 0.9, 1.0 - grass);   // arena y tierra un poco menos claras (no se queman)
	return c * mix(1.0, 0.92, smoothstep(150.0, 900.0, dist));
}
