// Cuerpo común del shader de los chunks del país (Fase 9A/9B + mapa v2). Lo incluyen
// terrain_chunk.gdshader y terrain_chunk_plus.gdshader (este define TERRAIN_GRADE): así las dos copias
// no se desincronizan nunca.
// - De cerca se ve low-poly (normal plana de las derivadas de pantalla); de lejos se mezcla con la normal
//   suave del vértice, con el relieve exagerado según la distancia (laderas sombreadas desde el país).
// - Ruido de detalle filtrado por el tamaño del píxel (sin moiré): variación de color por bioma,
//   pendiente (roca con estratos) y altura (páramo, nieve en las cumbres), y microrelieve por "bump".
// - Bosque y selva: copas procedurales (Voronoi) cuyo tamaño crece con la distancia, sombreadas con la
//   luz real: de lejos el bosque tiene textura y relieve en lugar de manchas planas. UV.x = densidad
//   de árboles del bioma, UV.y = aridez (desierto/costa).
// - Costas con arena y ríos reales (geo_tex: distancia y ancho del cauce de Natural Earth) como
//   líneas azules que mantienen un grosor mínimo en pantalla.
// - Niebla: velo translúcido (fog_tex, un valor por chunk, interpolado).
// - Fronteras de municipio: zone_tex (id por chunk).
// - is_far: tesela lejana; se recorta donde detail_tex marca un chunk con malla detallada. En la banda
//   fade_near..fade_far las dos capas se mezclan con un tramado complementario (transición suave).
// COLOR.a marca la hierba (estación).

uniform vec3 season_tint = vec3(1.0);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform sampler2D zone_tex : filter_nearest, repeat_disable;
uniform sampler2D detail_tex : filter_nearest, repeat_disable;
uniform sampler2D geo_tex : filter_linear, repeat_disable;
uniform sampler2D river_tex : filter_linear, repeat_disable;   // distancia (m) al cauce, 25 m por píxel
uniform bool has_geo = false;
uniform vec4 geo_rect = vec4(0.0, 0.0, 1.0, 1.0);   // x0, z0, ancho, alto (m)
uniform vec2 map_origin = vec2(0.0);
uniform float map_texels = 68.0;
uniform float chunk_size = 400.0;
uniform bool is_far = false;
uniform float border_alpha = 0.0;
uniform float border_width = 20.0;
uniform vec3 veil_color = vec3(0.66, 0.68, 0.71);
uniform float water_level = 0.0;
uniform float snow_line = 150.0;
uniform float relief = 1.0;
uniform float fade_near = 100000.0;
uniform float fade_far = 100001.0;
// Pulido: el pueblo (chunk central, terreno viejo sin copas) está en el origen. Las copas del bosque
// entran con la misma mezcla de colores que CountryGen.blend_at (HALF_CHUNK..HALF_CHUNK + BLEND):
// antes el bosque empezaba de golpe en el borde del chunk del pueblo (costura recta).
uniform float town_half = 200.0;
uniform float town_blend = 480.0;

varying vec3 world_pos;
varying vec3 world_nrm;
varying vec2 veg;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	veg = UV;
}

float zone_id(ivec2 c) {
	int w = int(map_texels);
	c = clamp(c, ivec2(0), ivec2(w - 1));
	return texelFetch(zone_tex, c, 0).r;
}

float tc_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 tc_hash2(vec2 p) {
	return vec2(tc_hash(p), tc_hash(p + vec2(17.13, 91.7)));
}

float tc_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(tc_hash(i), tc_hash(i + vec2(1.0, 0.0)), f.x), mix(tc_hash(i + vec2(0.0, 1.0)), tc_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// fbm filtrado: cada octava se apaga cuando su longitud de onda baja de ~2 píxeles (fp = m por píxel).
float tc_fbm(vec2 p, float wave, float fp) {
	float s = 0.0;
	float a = 0.5;
	float norm = 0.0;
	float w = wave;
	for (int o = 0; o < 4; o++) {
		float k = 1.0 - smoothstep(1.5, 4.0, fp / w * 2.0);
		s += a * k * (tc_noise(p / w + float(o) * 7.31) - 0.5);
		norm += a;
		a *= 0.5;
		w *= 0.5;
	}
	return s / norm;   // ~[-0.5, 0.5]
}

// Crestas: fbm "ridged" filtrado por el tamaño del píxel. Devuelve una altura (m) con crestas marcadas.
float tc_ridges(vec2 p, float wave, float fp) {
	float s = 0.0;
	float a = 1.0;
	float w = wave;
	for (int o = 0; o < 4; o++) {
		float k = 1.0 - smoothstep(1.5, 4.0, fp / w * 2.0);
		float r = 1.0 - pow(abs(tc_noise(p / w + float(o) * 3.17) * 2.0 - 1.0), 1.6);   // cresta redondeada
		s += a * k * r * r * w * 0.16;
		a *= 0.55;
		w *= 0.5;
	}
	return s;
}

// Copas de árboles: una por celda con probabilidad `dens`. Devuelve la altura de la copa (0 = claro).
float tc_canopy(vec2 p, float dens, float aa) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 h = tc_hash2(i + g);
			float pres = tc_hash(i + g + vec2(3.7, 1.9));
			if (pres > dens) {
				continue;
			}
			float r = 0.5 + 0.3 * pres / max(dens, 0.01);
			float d = length(g + 0.15 + h * 0.7 - f) / r;
			// Cúpula con borde suavizado al tamaño del píxel (antes el borde era un escalón dentado).
			best = max(best, sqrt(max(1.0 - d * d, 0.0)) * (1.0 - smoothstep(1.0 - aa, 1.0, d)));
		}
	}
	return best;
}

// Tramado de la banda de transición entre LOD: ruido de gradiente intercalado (IGN, el que usan los
// motores para el "crossfade" de LOD). Reparte el umbral de forma uniforme sin grumos (el ruido blanco
// de antes dejaba "sal y pimienta") ni la trama regular de una matriz de Bayer; con MSAA/TAA se funde.
float tc_ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void fragment() {
	vec2 cuv = (world_pos.xz - map_origin) / chunk_size;
	float dist = length(VERTEX);
	// Tramado complementario entre la malla detallada y la tesela lejana (banda fade_near..fade_far).
	float dither = tc_ign(floor(FRAGCOORD.xy));
	float fade = smoothstep(fade_near, fade_far, dist);
	if (is_far) {
		if (texture(detail_tex, cuv / map_texels).r > 0.5 && dither >= fade) {
			discard;
		}
	} else if (dither < fade) {
		discard;
	}
	vec2 p = world_pos.xz;
	float fp = max(length(fwidth(world_pos.xz)) * 0.7, 0.05);   // metros por píxel
	float far_k = smoothstep(500.0, 9000.0, dist);
	float h = world_pos.y;
	vec3 wn = normalize(world_nrm);
	float slope = 1.0 - wn.y;
	// Faldones (UV.x + 10, Terrain.SKIRT_UV): son paredes verticales que tapan las rendijas entre chunks
	// de distinta resolución. Con la normal de las derivadas salían oscuros y se veían como líneas
	// punteadas a lo largo de los bordes de chunk; ahora se iluminan con la normal del suelo y sin copas.
	float skirt = step(1.05, veg.x);
	float dens = clamp(veg.x, 0.0, 1.0) * (1.0 - skirt);
	float arid = clamp(veg.y, 0.0, 1.0);
	float mtn = clamp(-veg.y, 0.0, 1.0);          // montaña o nevado
	float nev = clamp(-veg.y - 1.0, 0.0, 1.0);    // nevado (la nieve la decide la altura, abajo)
	// Relieve más marcado a distancia: la normal se inclina más (laderas sombreadas desde lejos).
	float ex = 1.0 + relief * (0.5 + 2.6 * far_k) * (1.0 + 0.8 * mtn);
	vec3 wn_ex = normalize(vec3(wn.x * ex, wn.y, wn.z * ex));
	float n_macro = tc_fbm(p, 2400.0, fp);
	float n_mid = tc_fbm(p + 311.0, 380.0, fp);
	float n_fine = tc_fbm(p + 57.0, 45.0, fp);
	// Claro alrededor del pueblo con borde orgánico (ruido) para que no se lea como un cuadrado.
	dens *= smoothstep(town_half, town_half + town_blend * 0.8, max(abs(p.x), abs(p.y)) + n_mid * 260.0) * smoothstep(town_half, town_half + 80.0, max(abs(p.x), abs(p.y)));

	vec3 c = COLOR.rgb;
	float grass = COLOR.a;
	c = mix(c, c * season_tint, grass);
	// Pulido: junto al pueblo el color se calcula como en el chunk del pueblo (terrain_plus) y el
	// detalle del país entra con la misma mezcla que los colores (CountryGen.blend_at): sin el cuadrado
	// claro con borde recto alrededor del pueblo.
	vec3 c_town = mix(c, vec3(0.92, 0.94, 0.97) * max(max(COLOR.r, COLOR.g), 0.45) * 1.6, grass * snow_amount);
#ifdef TERRAIN_GRADE
	c_town = terrain_grade(c_town, grass, world_pos, dist);
#endif
	float cheb = max(abs(world_pos.x), abs(world_pos.z));
	float town_k = smoothstep(town_half, town_half + town_blend, cheb + n_mid * 200.0) * smoothstep(town_half, town_half + 80.0, cheb);
	// Variación por bioma: pasto y bosque con zonas más secas o más húmedas; tierra y roca con manchas.
	float lum0 = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 warm = c * vec3(1.12, 1.04, 0.78);
	vec3 cool = c * vec3(0.86, 1.0, 0.94);
	c = mix(c, mix(cool, warm, clamp(n_macro * 1.6 + 0.5, 0.0, 1.0)), 0.55 * max(grass, dens));
	c *= 1.0 + n_mid * 0.22 + n_fine * 0.16;
	// Montaña: matorral pardo verdoso y roca desnuda en manchas (no un gris liso); el nevado parte de roca.
	vec3 scrub = vec3(0.4, 0.43, 0.3) * (0.9 + n_fine * 0.5);
	vec3 bare = vec3(0.5, 0.46, 0.41) * (0.92 + n_fine * 0.4);
	vec3 mcol = mix(scrub, bare, smoothstep(-0.1, 0.25, n_mid + slope * 0.8 + nev * 0.5));
	c = mix(c, mcol, mtn * 0.85);
	// Crestas de montaña: relieve fino con su pendiente calculada en el mundo (diferencias finitas, sin
	// bloques de píxeles) que inclina la normal: la luz real sombrea una ladera y aclara la otra.
	if (mtn > 0.001) {
		float e = max(fp * 1.5, 6.0);
		float r0 = tc_ridges(p + 911.0, 1000.0, fp);
		float rx = tc_ridges(p + vec2(e, 0.0) + 911.0, 1000.0, fp);
		float rz = tc_ridges(p + vec2(0.0, e) + 911.0, 1000.0, fp);
		vec2 rg = vec2(rx - r0, rz - r0) / e * mtn * (0.3 + 0.45 * far_k);
		wn_ex = normalize(wn_ex + vec3(-rg.x, 0.0, -rg.y));
		c *= 1.0 - 0.1 * mtn + 0.18 * clamp(r0 / 160.0, 0.0, 1.0) * mtn;
	}
	// Páramo (alto y sin nieve): pasto amarillento y ocre.
	float paramo = smoothstep(snow_line - 55.0, snow_line - 25.0, h + n_mid * 20.0) * (1.0 - arid);
	c = mix(c, vec3(0.56, 0.52, 0.34) * (0.9 + n_fine), paramo * 0.55 * max(grass, 0.4));
	// Roca en las pendientes, con estratos.
	float rock = smoothstep(0.16, 0.34, slope + n_mid * 0.12) * (1.0 - smoothstep(snow_line + 10.0, snow_line + 30.0, h) * 0.5);
	vec3 rock_c = vec3(0.47, 0.44, 0.4) * (0.88 + 0.12 * sin(h * 0.9 + n_mid * 6.0)) * (1.0 + n_fine * 0.3);
	c = mix(c, rock_c, rock * 0.85);
	// Arena en la costa y las orillas (se ensancha un poco de lejos para que la costa se lea).
	float above = h - water_level;
	float sand = (1.0 - smoothstep(0.7, 1.4 + 2.2 * far_k, above + n_fine * 0.8)) * step(-3.0, above);
	c = mix(c, vec3(0.84, 0.78, 0.6) * (0.95 + n_fine * 0.3), sand * (1.0 - rock));
	// Copas de árboles (bosque, selva): celdas de 9 m cerca que crecen con la distancia (≥ ~6 px).
	float bump = n_fine * 2.0 + n_mid * 6.0;
	// Pulido: borde del bosque orgánico (umbral con ruido) en lugar del polígono de la malla.
	float forest = smoothstep(0.1, 0.4, dens + n_mid * 0.5 + n_fine * 0.25) * (1.0 - sand) * (1.0 - rock * 0.7);
	if (forest > 0.001) {
		float cs = max(9.0, fp * 6.5);
		float lv = log2(cs / 9.0);
		float l0 = floor(lv);
		float s0 = 9.0 * exp2(l0);
		float t = fract(lv);
		float cd = clamp(dens * 1.05 + n_mid * 0.35, 0.0, 1.0);
		float aa0 = clamp(fp / s0 * 2.5, 0.08, 0.6);
		float ch = mix(tc_canopy(p / s0, cd, aa0), tc_canopy(p / (s0 * 2.0) + 17.3, cd, aa0 * 0.5), t);
		float sc = mix(s0, s0 * 2.0, t);
		vec3 crown = c * (0.62 + 0.5 * ch) * mix(vec3(1.0), vec3(0.92, 1.06, 0.9), tc_hash(floor(p / s0)));
		c = mix(c, crown, forest);
		bump += ch * sc * 0.45 * forest;
	}
	// Nieve: en las cumbres (menos en las paredes muy empinadas) y la de la estación en la hierba.
	float snow = smoothstep(snow_line, snow_line + 5.0, h + n_mid * 18.0 + n_fine * 9.0 - slope * 25.0);
	// Vetas de roca dentro de la nieve (crestas y canales) para que no parezca una nube.
	float streak = smoothstep(0.08, 0.2, abs(n_mid * 1.5 + n_fine)) * smoothstep(0.2, 0.45, slope + n_fine * 0.3);
	snow *= 1.0 - streak * 0.7;
	c = mix(c, vec3(0.8, 0.83, 0.88), snow);
	c = mix(c, vec3(0.92, 0.94, 0.97) * max(max(COLOR.r, COLOR.g), 0.45) * 1.6, grass * snow_amount);
#ifdef TERRAIN_GRADE
	c = terrain_grade(c, grass, world_pos, dist);
#endif
	// Sombreado cartográfico suave (luz del noroeste) que se suma al sol real desde lejos.
	float hs = dot(wn_ex, normalize(vec3(-0.55, 0.7, -0.45)));
	c *= mix(1.0, clamp(0.5 + 0.6 * hs, 0.55, 1.12), (0.55 + 0.25 * mtn) * far_k);
	c = mix(c_town, c, town_k);

	// Normal: plana de cerca (low-poly), suave y exagerada lejos, más microrelieve por bump.
	vec3 fn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(fn, VERTEX) > 0.0) {
		fn = -fn;   // el signo de dFdy depende del backend: la normal siempre mira a la cámara
	}
	float facet = 1.0 - smoothstep(120.0, 650.0, dist);
	vec3 vn = normalize((VIEW_MATRIX * vec4(wn_ex, 0.0)).xyz);
	vec3 n = normalize(mix(vn, fn, facet));
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec3 r1 = cross(dpy, n);
	vec3 r2 = cross(n, dpx);
	float det = dot(dpx, r1);
	float bk = relief * (0.35 + 0.65 * smoothstep(80.0, 600.0, dist));
	vec3 grad = sign(det) * (dFdx(bump) * r1 + dFdy(bump) * r2) * bk;
	vec3 nb = abs(det) * n - grad;
	if (dot(nb, nb) > 1e-12) {
		n = normalize(nb);
	}
	if (skirt > 0.5) {
		n = vn;
	}
	NORMAL = n;

	// Velo translúcido: desatura, aclara un poco y baja el contraste, pero deja ver el relieve y el bioma.
	float fog = texture(fog_tex, cuv / map_texels).r;
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 veiled = mix(c, vec3(lum), 0.7 * fog);
	veiled = mix(veiled, veil_color * (0.45 + 0.7 * lum), 0.3 * fog);
	c = veiled;
	// Ríos reales: líneas azules con grosor mínimo en pantalla (de cerca manda el cauce tallado).
	if (has_geo) {
		vec2 guv = (p - geo_rect.xy) / geo_rect.zw;
		if (guv.x > 0.0 && guv.y > 0.0 && guv.x < 1.0 && guv.y < 1.0) {
			vec4 g = texture(geo_tex, guv);
			float rw = g.g;
			if (rw > 1.0) {
				float rdist = texture(river_tex, guv).r;
				float half_w = rw * 0.15 + 6.0 + fp * 1.0;   // +6 m: error de la textura de 25 m
				float line = 1.0 - smoothstep(half_w - max(fp, 8.0), half_w, rdist);
				line *= smoothstep(3.0, 9.0, fp) * (1.0 - snow);
				line *= mix(0.55, 0.95, smoothstep(14.0, 50.0, rw));
				line *= smoothstep(1100.0, 2200.0, length(p));   // junto al pueblo no hay cauce (CountryGen)
				c = mix(c, vec3(0.2, 0.42, 0.56) * (1.0 - 0.25 * fog), line * 0.9);
			}
		}
	}
	// Fronteras de municipio (tenues; más cálidas alrededor del tuyo).
	// Pulido (docs/GRAFICOS.md §10): la frontera es la curva de nivel 0,5 de un indicador "mismo
	// municipio que mi celda" interpolado entre los centros de las 4 celdas vecinas (marching squares
	// suavizado). Antes seguía los bordes de los chunks y se veía en escalera; ahora las esquinas se
	// cortan en diagonal/curva y la línea tiene ancho uniforme en metros con antialias por píxel.
	if (border_alpha > 0.001) {
		ivec2 ci = ivec2(floor(cuv));
		float id = zone_id(ci);
		float mine = texelFetch(zone_tex, clamp(ci, ivec2(0), ivec2(int(map_texels) - 1)), 0).g;
		vec2 q = cuv - 0.5;
		ivec2 b = ivec2(floor(q));
		vec2 t = q - floor(q);
		float i00 = abs(zone_id(b) - id) < 0.001 ? 1.0 : 0.0;
		float i10 = abs(zone_id(b + ivec2(1, 0)) - id) < 0.001 ? 1.0 : 0.0;
		float i01 = abs(zone_id(b + ivec2(0, 1)) - id) < 0.001 ? 1.0 : 0.0;
		float i11 = abs(zone_id(b + ivec2(1, 1)) - id) < 0.001 ? 1.0 : 0.0;
		float e = 0.0;
		if (i00 + i10 + i01 + i11 < 3.99) {
			float v = mix(mix(i00, i10, t.x), mix(i01, i11, t.x), t.y);
			vec2 g = vec2(mix(i10 - i00, i11 - i01, t.y), mix(i01 - i00, i11 - i10, t.x));
			// Distancia (en metros) a la curva v = 0,5.
			float dm = abs(v - 0.5) / max(length(g), 0.25) * chunk_size;
			float hw = max(border_width * 0.75, fp * 1.2);
			float aa = max(fp * 1.2, 1.0);
			e = 1.0 - smoothstep(hw - aa, hw + aa, dm);
			e *= 0.55 + 0.45 * (1.0 - smoothstep(0.0, hw, dm));   // centro más marcado
		}
		vec3 bc = mix(vec3(1.0), vec3(1.0, 0.82, 0.35), mine);
		c = mix(c, bc, e * border_alpha * (1.0 + 0.5 * mine));
	}
	ALBEDO = clamp(c, vec3(0.0), vec3(1.0));
	ROUGHNESS = mix(0.95, 0.6, snow);
	SPECULAR = 0.2 * (1.0 - fog);
}
