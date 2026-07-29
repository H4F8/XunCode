// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use portable_pty::{Child, CommandBuilder, MasterPty, NativePtySystem, PtyPair, PtySize, PtySystem};
use std::io::{Read, Write};
use std::sync::{Arc, Mutex};
use tauri::{Emitter, State};

struct PtySession {
    _child: Box<dyn Child + Send + Sync>,
    writer: Box<dyn Write + Send>,
}

struct AppState {
    pty: Arc<Mutex<Option<PtyPair>>>,
    session: Arc<Mutex<Option<PtySession>>>,
}

#[tauri::command]
async fn pty_create(
    app: tauri::AppHandle,
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
    let child = pair.slave.spawn_command(cmd).map_err(|e| e.to_string())?;
    let writer = pair.master.take_writer().map_err(|e| e.to_string())?;

    {
        let mut lock = state.pty.lock().map_err(|e| e.to_string())?;
        *lock = Some(pair);
    }
    {
        let mut lock = state.session.lock().map_err(|e| e.to_string())?;
        *lock = Some(PtySession {
            _child: child,
            writer,
        });
    }

    // Spawn a blocking read loop that emits terminal output to the frontend.
    let reader_pair = {
        let lock = state.pty.lock().map_err(|e| e.to_string())?;
        lock.as_ref()
            .and_then(|p| p.master.try_clone_reader().ok())
            .ok_or_else(|| "failed to clone pty reader".to_string())?
    };

    std::thread::spawn(move || {
        let mut reader = reader_pair;
        let mut buf = [0u8; 4096];
        loop {
            match reader.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    let chunk = String::from_utf8_lossy(&buf[..n]).to_string();
                    if app.emit("pty:data", chunk).is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
    });

    Ok(())
}

#[tauri::command]
async fn pty_write(state: State<'_, AppState>, data: String) -> Result<(), String> {
    let mut lock = state.session.lock().map_err(|e| e.to_string())?;
    if let Some(ref mut session) = *lock {
        session
            .writer
            .write_all(data.as_bytes())
            .map_err(|e| e.to_string())?;
        session.writer.flush().map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
async fn pty_resize(state: State<'_, AppState>, cols: u16, rows: u16) -> Result<(), String> {
    let lock = state.pty.lock().map_err(|e| e.to_string())?;
    if let Some(ref pair) = *lock {
        pair.master
            .resize(PtySize {
                cols,
                rows,
                pixel_width: 0,
                pixel_height: 0,
            })
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_store::Builder::new().build())
        .manage(AppState {
            pty: Arc::new(Mutex::new(None)),
            session: Arc::new(Mutex::new(None)),
        })
        .invoke_handler(tauri::generate_handler![pty_create, pty_write, pty_resize])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
