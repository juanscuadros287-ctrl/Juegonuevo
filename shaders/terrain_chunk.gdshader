shader_type spatial;
render_mode cull_disabled;
// Fase 9A/9B + mapa v2: chunks y teselas lejanas del país. Todo el cuerpo está en
// terrain_chunk_body.gdshaderinc (compartido con terrain_chunk_plus.gdshader).
#include "res://shaders/terrain_chunk_body.gdshaderinc"
