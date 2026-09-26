class_name SkyRig
extends Node3D
## Iluminación y postproceso del mundo (docs/GRAFICOS.md): un solo Environment con cielo
## procedural, sol/luna con ciclo día-noche suave (amanecer y atardecer cálidos), tonemapping ACES,
## luz ambiental del cielo, sombras direccionales en cascadas y, solo en Forward+, SSAO, glow y
## niebla con dispersión del sol. En Compatibility (OpenGL) esos efectos se omiten.
## night_factor (0 = día, 1 = noche) enciende ventanas y faroles emisivos (MeshLib.set_night).

var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var night_factor := 0.0
var _profile: Dictionary = {}
var _last_night := -1.0

# Colores del cielo por altura del sol: [elevación, cenit, horizonte, luz del sol].
const SKY_KEYS := [
	[-0.35, Color(0.015, 0.025, 0.06), Color(0.05, 0.07, 0.13), Color(0.55, 0.65, 0.95)],
	[-0.08, Color(0.08, 0.1, 0.24), Color(0.36, 0.26, 0.34), Color(0.7, 0.6, 0.8)],
	[0.02, Color(0.22, 0.3, 0.52), Color(0.98, 0.56, 0.3), Color(1.0, 0.55, 0.3)],
	[0.16, Color(0.28, 0.46, 0.76), Color(0.96, 0.78, 0.58), Color(1.0, 0.8, 0.6)],
	[0.4, Color(0.24, 0.47, 0.82), Color(0.68, 0.8, 0.9), Color(1.0, 0.95, 0.88)],
	[1.0, Color(0.2, 0.44, 0.8), Color(0.64, 0.78, 0.9), Color(1.0, 0.98, 0.94)],
]


func _ready() -> void:
	add_to_group(GraphicsSettings.GROUP)


func build() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.18, 0.2, 0.2)
	sky_mat.ground_curve = 0.06
	sky_mat.sky_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_density = 0.0003
	env.fog_sky_affect = 0.25
	env.fog_aerial_perspective = 0.25
	env.fog_sun_scatter = 0.12
	# Glow suave (solo Forward+): los emisivos de noche florecen un poco.
	env.glow_intensity = 0.55
	env.glow_strength = 0.9
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 0.6)
	env.set_glow_level(3, 0.4)
	env.set_glow_level(4, 0.2)
	# SSAO (solo Forward+ en calidad alta).
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.8
	env.ssao_power = 1.4
	env.ssao_detail = 0.4
	env.ssao_horizon = 0.08
	env.ssao_light_affect = 0.15
	env.ssao_ao_channel_affect = 0.0
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.4
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.directional_shadow_pancake_size = 30.0
	# Sesgos pequeños: sin acné en caras planas ni "peter-panning" en la base de los edificios.
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.1
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.6
	add_child(sun)
	apply_graphics(GraphicsSettings.profile())


## Aplica el perfil de calidad (GraphicsSettings.apply lo llama en todos los del grupo).
func apply_graphics(p: Dictionary) -> void:
	_profile = p
	if env == null:
		return
	var fp := bool(p.get("forward_plus", false))
	sun.shadow_enabled = bool(p.get("shadows", true))
	sun.directional_shadow_max_distance = float(p.get("shadow_distance", 220.0))
	var lv := int(p.get("level", 2))
	sun.shadow_blur = [0.6, 1.0, 1.4][lv]
	# Alta: 4 cascadas mezcladas; Media: 2 cascadas (la mitad de pasadas de sombra).
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if lv >= GraphicsSettings.HIGH else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.06 if lv >= GraphicsSettings.HIGH else 0.25
	sun.directional_shadow_blend_splits = lv >= GraphicsSettings.HIGH
	RenderingServer.directional_shadow_atlas_set_size(int(p.get("shadow_atlas", 4096)), true)
	RenderingServer.directional_soft_shadow_filter_set_quality([
		RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][int(p.get("soft_shadows", 1))])
	env.ssao_enabled = bool(p.get("ssao", false))
	env.glow_enabled = bool(p.get("glow", false))
	# En Forward+ la niebla dispersa la luz del sol; en Compatibility queda solo la exponencial.
	env.fog_sun_scatter = 0.12 if fp else 0.0
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = int(p.get("msaa", Viewport.MSAA_2X))
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if bool(p.get("fxaa", false)) else Viewport.SCREEN_SPACE_AA_DISABLED
	if is_inside_tree():
		MeshLib.apply_ranges(get_tree(), p)


static func _sky_at(elev: float) -> Array:
	for i in range(SKY_KEYS.size() - 1):
		var a: Array = SKY_KEYS[i]
		var b: Array = SKY_KEYS[i + 1]
		if elev <= float(b[0]):
			var t := clampf(inverse_lerp(float(a[0]), float(b[0]), elev), 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			return [(a[1] as Color).lerp(b[1], t), (a[2] as Color).lerp(b[2], t), (a[3] as Color).lerp(b[3], t)]
	var last: Array = SKY_KEYS[SKY_KEYS.size() - 1]
	return [last[1], last[2], last[3]]


## Actualiza sol, cielo y luz según la hora (0-24) y el oscurecimiento del clima (0-1).
func update(hour: float, dim: float) -> void:
	if sun == null:
		return
	# El sol sale a las 6 y se pone a las 18; su altura máxima es ~62°.
	var t := (hour - 6.0) / 12.0
	var elev := sin(t * PI)                      # < 0 de noche
	var sun_elev_deg := elev * 62.0
	var az := -70.0 + t * 140.0
	var keys := _sky_at(elev)
	var gray := Color(0.5, 0.53, 0.58)
	var top: Color = (keys[0] as Color).lerp(gray * clampf(elev + 0.35, 0.1, 1.0), dim * 0.8)
	var horizon: Color = (keys[1] as Color).lerp(gray * clampf(elev + 0.45, 0.15, 1.0), dim * 0.8)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon.darkened(0.25)
	sky_mat.sun_curve = lerpf(0.05, 0.15, clampf(elev * 3.0, 0.0, 1.0))
	var day := smoothstep(-0.06, 0.3, elev)
	var moon := smoothstep(-0.02, -0.25, elev)
	night_factor = 1.0 - smoothstep(-0.1, 0.12, elev)
	if elev > -0.04:
		# Sol: luz cálida a baja altura, blanca a mediodía.
		sun.rotation = Vector3(-deg_to_rad(maxf(sun_elev_deg, 3.0)), deg_to_rad(az), 0)
		sun.light_color = keys[2]
		sun.light_energy = lerpf(0.0, 1.1, day) * (1.0 - dim * 0.55)
		sky_mat.sky_energy_multiplier = 1.0
	else:
		# Luna: luz azulada y tenue, alta en el cielo.
		sun.rotation = Vector3(-deg_to_rad(48.0), deg_to_rad(az + 180.0 + 30.0), 0)
		sun.light_color = Color(0.62, 0.72, 1.0)
		sun.light_energy = 0.2 * moon * (1.0 - dim * 0.7)
	sun.shadow_opacity = lerpf(0.55, 1.0, day) if elev > -0.04 else 0.5
	env.ambient_light_energy = lerpf(0.16, 0.62, day) * (1.0 - dim * 0.2)
	env.ambient_light_color = Color(0.4, 0.5, 0.75)
	env.ambient_light_sky_contribution = lerpf(0.35, 1.0, day)
	env.tonemap_exposure = lerpf(1.12, 1.0, day)
	env.fog_light_color = horizon.lerp(top, 0.35)
	env.fog_light_energy = lerpf(0.6, 1.0, day)
	var nf := clampf(night_factor + dim * 0.35, 0.0, 1.0)
	if absf(nf - _last_night) > 0.01:
		_last_night = nf
		MeshLib.set_night(nf)
