shader_type spatial;
render_mode cull_disabled;
// terrain_chunk.gdshader + gradación de color (docs/GRAFICOS.md). Mismo cuerpo (include): las dos
// versiones no se pueden desincronizar.
#define TERRAIN_GRADE
#include "res://shaders/terrain_grade.gdshaderinc"
#include "res://shaders/terrain_chunk_body.gdshaderinc"
