// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use portable_pty::{CommandBuilder, NativePtySystem, PtyPair, PtySize, PtySystem};
use std::io::{Read, Write};
use std::sync::{Arc, Mutex};
use tauri::State;

struct AppState {
    pty: Arc<Mutex<Option<PtyPair>>>,
}

#[tauri::command]
async fn pty_create(
    state: State<'_, AppState>,
    cols: u16,
    rows: u16,
) -> Result<(), String> {
    let pty_system = NativePtySystem::default();
    let pair = pty_system
        .openpty(PtySize {
            cols,
            rows,
            pixel_width: 0,
            pixel_height: 0,
        })
        .map_err(|e| e.to_string())?;

    let cmd = CommandBuilder::new("/bin/sh");
    pair.slave.spawn_command(cmd).map_err(|e| e.to_string())?;

    let lock = state.pty.lock().map_err(|e| e.to_string())?;
    *lock = Some(pair);
    Ok(())
}

#[tauri::command]
async fn pty_write(state: State<'_, AppState>, data: String) -> Result<(), String> {
    let lock = state.pty.lock().map_err(|e| e.to_string())?;
    if let Some(ref pair) = *lock {
        let mut writer = pair.master.take_writer().map_err(|e| e.to_string())?;
        writer.write_all(data.as_bytes()).map_err(|e| e.to_string())?;
        writer.flush().map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
async fn pty_read(state: State<'_, AppState>) -> Result<String, String> {
    let lock = state.pty.lock().map_err(|e| e.to_string())?;
    if let Some(ref pair) = *lock {
        let mut reader = pair.master.try_clone_reader().map_err(|e| e.to_string())?;
        drop(lock); // release mutex while blocking on read
        let mut buf = [0u8; 4096];
        let n = reader.read(&mut buf).map_err(|e| e.to_string())?;
        return Ok(String::from_utf8_lossy(&buf[..n]).to_string());
    }
    Ok(String::new())
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_store::Builder::new().build())
        .manage(AppState {
            pty: Arc::new(Mutex::new(None)),
        })
        .invoke_handler(tauri::generate_handler![pty_create, pty_write, pty_read])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
