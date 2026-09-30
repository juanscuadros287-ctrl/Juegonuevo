# Instalar Dinastía en el Mac (abrir con doble clic)

## Instalar

1. Descomprime `Dinastia_macOS.zip` (doble clic en el .zip). Aparece **Dinastía.app**.
2. Arrastra **Dinastía.app** a la carpeta **Aplicaciones**.
3. **Solo la primera vez**: la app no está firmada por Apple (no hay cuenta de desarrollador), así
   que Gatekeeper la bloquea con doble clic. Haz **clic derecho (o Control+clic) → Abrir** y luego
   **Abrir** en el aviso.
   - En macOS 15 (Sequoia) o posterior, si no aparece el botón: intenta abrirla una vez, ve a
     **Ajustes del Sistema → Privacidad y seguridad**, baja hasta «Se bloqueó Dinastía» y pulsa
     **Abrir igualmente**.
   - Alternativa por Terminal: `xattr -dr com.apple.quarantine /Applications/Dinastía.app`
4. Desde entonces se abre con **doble clic** (y puedes dejarla en el Dock).

## Actualizar sin perder partidas

Las partidas **no están dentro de la app**: están en
`~/Library/Application Support/Dinastía/` (carpeta `slots/`). Para actualizar, reemplaza
Dinastía.app en Aplicaciones por la nueva; las partidas siguen ahí y, si el formato cambió, el juego
las convierte solo (guardando antes una copia `slot_N.vV.backup`). Ver `docs/GUARDADO.md`.

Para hacer una copia de seguridad manual: en Finder, **Ir → Ir a la carpeta…** y pega
`~/Library/Application Support/Dinastía/`; copia la carpeta `slots`.

## Generar el .app (para quien compila)

Requisitos: Godot 4.3-stable y sus *export templates*.

1. Plantillas (una vez, ~1 GB):
   ```bash
   mkdir -p ~/.local/share/godot/export_templates/4.3.stable          # Linux
   # en Mac: ~/Library/Application Support/Godot/export_templates/4.3.stable
   curl -L -o /tmp/tpl.tpz https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_export_templates.tpz
   unzip -j /tmp/tpl.tpz 'templates/*' -d ~/.local/share/godot/export_templates/4.3.stable/
   ```
   (o desde el editor: Editor → Administrar plantillas de exportación → Descargar e instalar).
2. Importar el proyecto una vez: `godot --headless --import`
3. Exportar:
   ```bash
   mkdir -p build
   godot --headless --export-release "macOS" build/Dinastia_macOS.zip
   godot --headless --export-release "Linux" build/Dinastia_Linux/Dinastia.x86_64
   ```

Presets en `export_presets.cfg`:

- **macOS**: universal (Apple Silicon + Intel), nombre «Dinastía», bundle id
  `com.sebastian.dinastia`, icono `icon.icns`, firma ad-hoc incorporada sin identidad (necesaria para
  que un binario arm64 arranque; no es una firma de desarrollador, por eso el paso 3 de arriba),
  sin notarización. Requiere `rendering/textures/vram_compression/import_etc2_astc=true` (ya puesto).
- **Linux**: x86_64 con el .pck incrustado (para probar).

El icono se genera con `python3 tools/make_icon.py` (Pillow): `icon.png` (1024), `icon.icns`,
`icon.ico`. Diseño propio: escudo dorado con una esmeralda talla esmeralda y una corona.

Los binarios **no se suben al repositorio** (`build/` está excluido).
