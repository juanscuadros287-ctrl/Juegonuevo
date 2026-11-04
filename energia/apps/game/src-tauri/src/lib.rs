/// La app nativa solo aloja la web: toda la lógica del juego vive en TypeScript.
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("error al iniciar Voltaje");
}
