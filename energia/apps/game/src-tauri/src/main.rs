// Evita una consola extra en Windows; en macOS no tiene efecto.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    voltaje_lib::run()
}
