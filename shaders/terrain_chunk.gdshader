shader_type spatial;
render_mode cull_disabled;
// Fase 9A/9B: chunks del país (malla indexada con normales por vértice y colores interpolados).
// - De cerca se ve low-poly (normal plana de las derivadas de pantalla); de lejos se mezcla con la normal
//   suave del vértice: la capa lejana no se ve en bloques.
// - Niebla: velo translúcido que atenúa biomas y relieve (nunca un blanco opaco). fog_tex tiene un valor por
//   chunk (0 explorado, velo ligero, velo, fuera del país) y se interpola: los bordes son suaves.
// - Fronteras de municipio: zone_tex (id por chunk); se dibuja una línea tenue donde cambia el id.
// - is_far: tesela lejana; se recorta donde detail_tex marca un chunk con malla detallada visible.
// COLOR.a marca la hierba (estación).

uniform vec3 season_tint = vec3(1.0);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform sampler2D zone_tex : filter_nearest, repeat_disable;
uniform sampler2D detail_tex : filter_nearest, repeat_disable;
uniform vec2 map_origin = vec2(0.0);
uniform float map_texels = 68.0;
uniform float chunk_size = 400.0;
uniform bool is_far = false;
uniform float border_alpha = 0.0;
uniform float border_width = 20.0;
uniform vec3 veil_color = vec3(0.8, 0.83, 0.87);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float zone_id(ivec2 c) {
	int w = int(map_texels);
	c = clamp(c, ivec2(0), ivec2(w - 1));
	return texelFetch(zone_tex, c, 0).r;
}

void fragment() {
	vec2 cuv = (world_pos.xz - map_origin) / chunk_size;
	if (is_far) {
		if (texture(detail_tex, cuv / map_texels).r > 0.5) {
			discard;
		}
	}
	vec3 fn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(fn, VERTEX) > 0.0) {
		fn = -fn;   // el signo de dFdy depende del backend: la normal siempre mira a la cámara
	}
	float dist = length(VERTEX);
	float facet = 1.0 - smoothstep(180.0, 1400.0, dist);
	NORMAL = normalize(mix(NORMAL, fn, facet));
	vec3 c = COLOR.rgb;
	float grass = COLOR.a;
	c = mix(c, c * season_tint, grass);
	c = mix(c, vec3(0.92, 0.94, 0.97) * max(max(COLOR.r, COLOR.g), 0.45) * 1.6, grass * snow_amount);
	// Velo translúcido: desatura, aclara un poco y baja el contraste, pero deja ver el relieve y el bioma.
	float fog = texture(fog_tex, cuv / map_texels).r;
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 veiled = mix(c, vec3(lum), 0.65 * fog);
	veiled = mix(veiled, veil_color * (0.55 + 0.6 * lum), 0.42 * fog);
	c = veiled;
	// Fronteras de municipio (tenues; más cálidas alrededor del tuyo).
	if (border_alpha > 0.001) {
		ivec2 ci = ivec2(floor(cuv));
		vec2 f = cuv - floor(cuv);
		float id = zone_id(ci);
		float w = border_width / chunk_size;
		float e = 0.0;
		float mine = texelFetch(zone_tex, clamp(ci, ivec2(0), ivec2(int(map_texels) - 1)), 0).g;
		if (f.x < w && abs(zone_id(ci + ivec2(-1, 0)) - id) > 0.001) { e = max(e, 1.0 - f.x / w); }
		if (f.x > 1.0 - w && abs(zone_id(ci + ivec2(1, 0)) - id) > 0.001) { e = max(e, 1.0 - (1.0 - f.x) / w); }
		if (f.y < w && abs(zone_id(ci + ivec2(0, -1)) - id) > 0.001) { e = max(e, 1.0 - f.y / w); }
		if (f.y > 1.0 - w && abs(zone_id(ci + ivec2(0, 1)) - id) > 0.001) { e = max(e, 1.0 - (1.0 - f.y) / w); }
		e = smoothstep(0.0, 0.5, e);
		vec3 bc = mix(vec3(1.0), vec3(1.0, 0.82, 0.35), mine);
		c = mix(c, bc, e * border_alpha * (1.0 + 0.5 * mine));
	}
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2 * (1.0 - fog);
}
