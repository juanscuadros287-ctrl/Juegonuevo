# Guardado de partidas

Objetivo: **que nunca se pierda una partida**, ni por un corte de luz ni por una actualización del
juego. Código: `scripts/autoload/save_manager.gd` (autoload `SaveManager`) y
`scripts/autoload/save_migrations.gd` (`SaveMigrations`). Pruebas: `tests/test_guardado.tscn`.

## Dónde se guardan

En `user://`, con nombre de carpeta fijo (`project.godot`: `config/name="Dinastía"`,
`config/use_custom_user_dir=true`, `config/custom_user_dir_name="Dinastía"`):

| Sistema | Carpeta |
|---|---|
| macOS | `~/Library/Application Support/Dinastía/` |
| Linux | `~/.local/share/Dinastía/` |
| Windows | `%APPDATA%\Dinastía\` |

Esa carpeta es independiente del `.app`: reemplazar el juego por una versión nueva **no la toca**.
**No cambies `config/name` ni `custom_user_dir_name`**: el juego dejaría de encontrar las partidas.

```
slots/slot_N.sav            partida de la ranura N (1..5)
slots/slot_N.sav.bak1       copia anterior (la más reciente)
slots/slot_N.sav.bak2       copia anterior a la anterior
slots/slot_N.sav.tmp        solo existe durante una escritura (o tras un corte)
slots/slot_N.sav.damaged    principal ilegible apartada al volver a guardar (nunca se borra sola)
slots/slot_N.vV.backup      copia intacta de la partida antes de migrarla desde la versión V
slots/slots.cfg             nombres de ranura, última partida, minutos de autoguardado, importadas
saves/*.sav, saves/*.json   sistema anterior (nombres libres); se importan a ranuras, no se borran
```

Las versiones anteriores del juego guardaban en `<datos>/Godot/app_userdata/Dinastía/saves/`; esa
carpeta también se revisa al buscar partidas antiguas.

## Cuándo se guarda

- **Autoguardado** en la ranura activa cada N minutos reales de juego (Opciones → Autoguardado:
  1, 3 (por defecto), 5, 10 o solo por mes), **al empezar cada mes** del juego (mínimo 20 s entre
  guardados, para no guardar sin parar a velocidad x3) y al terminar un salto de años.
- **Al salir**: «Salir del juego», «Guardar y salir al menú», cerrar la ventana o Cmd+Q
  (`NOTIFICATION_WM_CLOSE_REQUEST`; `auto_accept_quit` está desactivado para guardar antes).
- **Partida nueva**: se guarda al crearla y otra vez a los 3 s (ya con miniatura del mundo).
- Menú de pausa (Esc): «Guardar ahora», «Guardar y salir al menú», «Guardar en otra ranura…»,
  «Salir del juego (guarda antes)» e indicador del último guardado. Cada guardado muestra un aviso
  discreto «Guardado ✓» abajo a la derecha.

## Escritura atómica y copias

1. Se escribe `slot_N.sav.tmp` completo y se verifica (cabecera legible, tamaño correcto).
2. Si la principal es legible: `.bak1 → .bak2`, `principal → .bak1`. Si está dañada se aparta a
   `.damaged` (así no desplaza las copias buenas).
3. `.tmp → principal` (renombrar es atómico).

Al cargar se prueba en orden: principal, `.tmp` (solo si está completo: caso de corte justo entre
renombrados), `.bak1`, `.bak2`. Cada archivo lleva el tamaño y el SHA-256 del cuerpo, así que un
archivo truncado o con un byte cambiado se detecta y se pasa a la copia. Si nada carga, se muestra
el error con botones para intentar cada copia, y **no se borra ni se modifica nada**.

## Formato (versión 8)

```
store_var(cabecera) + u32 tamaño + cuerpo (var_to_bytes)
cabecera = {magic: "DINASTIA", format_version: 8, game_version: "0.10.1", saved_at: "2026-09-26T14:03:10",
            meta: {town, player, country_id, country, date, year, money, population, play_seconds,
                   difficulty, title, thumbnail (PNG 320×180)},
            body_size, body_sha256}
cuerpo   = {state: GameState.to_dict(), time: TimeManager.to_dict()}
```

El menú lee solo la cabecera (rápido, con miniatura). En memoria una partida es
`{format_version, game_version, saved_at, meta, state, time}`. Se siguen leyendo los formatos viejos:
un solo `store_var({version, saved_at, summary, time, state})` (v7 y anteriores) y `.json`.

## Compatibilidad entre versiones

Dos mecanismos:

1. **Tolerancia** (`GameState.load_dict`): toda clave que falte toma un valor por defecto (y los
   `init_state(...)` de cada sistema completan lo suyo); las claves que sobran (de una versión más
   nueva) se ignoran; un tipo inesperado (p. ej. texto donde iba un diccionario) se trata como vacío.
   Los ajustes básicos (`SETTINGS_FALLBACK`) se completan siempre. Así, **añadir un sistema nuevo
   no necesita migración**: basta con leerlo con `d.get("clave", {})` y dejar que su `init_state`
   rellene lo que falte, como hacen todos los sistemas actuales.
2. **Migraciones** (`save_migrations.gd`): para cambios de *forma* o de *significado* (renombrar una
   clave, cambiar una lista por un diccionario, cambiar unidades…).

### Cómo agregar una migración (cada vez que cambie el formato)

1. En `scripts/autoload/save_migrations.gd` sube `CURRENT` (p. ej. de 8 a 9) y pon el mismo número
   en `GameState.SAVE_VERSION`.
2. Escribe la función, con ese nombre exacto (se busca por nombre):
   ```gdscript
   static func migrate_v8_to_v9(d: Dictionary) -> Dictionary:
       # d = {format_version, game_version, saved_at, meta, state, time} en la versión 8
       var st: Dictionary = d.get("state", {})
       if st.has("vieja_clave"):
           st["nueva_clave"] = st["vieja_clave"]   # no borres datos del jugador
       return d
   ```
   `SaveMigrations.migrate()` aplica en orden todas las que falten (v3 → v4 → … → actual) y actualiza
   `format_version` tras cada paso. Si falta una función de la cadena, la carga falla con un mensaje
   claro y la partida queda intacta.
3. Añade un caso en `tests/test_guardado.gd` con un diccionario mínimo de la versión anterior y
   comprueba que carga y se puede jugar.
4. Corre todas las pruebas.

Antes de migrar una partida de ranura, `SaveManager` copia el archivo original a
`slot_N.vV.backup` (una vez por versión). Una partida «del futuro» (versión mayor que la del juego)
se intenta cargar igual gracias a la tolerancia.

## Partidas del sistema anterior

La primera vez que se abre la pantalla principal, las partidas de `saves/` (nombres libres, incluido
`autoguardado`; se omiten las de pruebas `test_*`/`prueba_*`) se importan a las ranuras libres: las
5 más recientes. El resto aparece en «Partidas antiguas (N)» para importarlas a mano a una ranura
libre. Los archivos originales no se modifican.

## API (SaveManager)

| Función | Qué hace |
|---|---|
| `list_slots()` / `slot_info(i)` | estado de las ranuras (`empty`/`ok`/`damaged`), cabecera, copias |
| `begin_slot(i)` | antes de `GameState.new_game`: la partida nueva vivirá en la ranura *i* |
| `save_slot(i, motivo)` | guardado atómico con copias (emite `saved(slot, ok, motivo)`) |
| `request_save(motivo)` | captura la miniatura (sin la interfaz) y guarda en la ranura activa |
| `load_slot(i)` | carga con respaldo automático; `{ok, error, source, used_backup, from_version}` |
| `load_file(ruta, i)` | carga una copia concreta |
| `delete_slot(i)` / `rename_slot(i, nombre)` | borrar (con sus copias) / renombrar |
| `autosave_tick(delta)` | reloj del autoguardado (lo llama `_process` durante la partida) |
| `quit_game()` | guarda (si hay ranura) y cierra |
| `list_legacy()` / `import_legacy(nombre, i)` / `auto_import_legacy()` | partidas antiguas |
| `save_game(n)` / `load_game(n)` / `list_saves()` / `delete_save(n)` | nombres libres en `saves/` (pruebas) |
| `use_dirs(slots, legacy)` | cambia las carpetas (las pruebas usan una propia) |

## Pruebas

`godot --headless tests/test_guardado.tscn` cubre: 5 ranuras (crear, listar, renombrar, borrar),
autoguardado por tiempo y por mes, escritura atómica y copias rotativas, recuperación con la
principal corrupta/truncada/con un byte cambiado y tras un corte al renombrar, migración de una
partida v3 mínima y de una sin versión, `.json` antiguo, claves «del futuro» y tipos inesperados,
importación de partidas antiguas, ida y vuelta (guardar → cargar → guardar da el mismo estado y la
simulación sigue determinista) y la interfaz (ranuras, confirmaciones, error sin borrar, menú de
pausa y barra superior a 1600 y 1280 px).
