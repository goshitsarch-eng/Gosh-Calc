//! Bounded, versioned settings with atomic replacement and read-only legacy import.
use crate::{
    engine::{AngleUnit, CalcState, Mode},
    state::SavedState,
    APP_ID,
};
use std::{
    fmt,
    fs::{self, OpenOptions},
    io::{Read, Write},
    path::{Path, PathBuf},
    sync::{mpsc, Mutex},
    thread,
    time::{SystemTime, UNIX_EPOCH},
};

const MAX_FILE_BYTES: u64 = 1024 * 1024;

#[derive(Debug)]
pub struct StoreError(pub String);
impl fmt::Display for StoreError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for StoreError {}

#[derive(Clone, Debug)]
pub struct Store {
    pub directory: PathBuf,
    pub legacy: Option<PathBuf>,
}
pub struct Loaded {
    pub state: SavedState,
    pub notice: Option<String>,
}

impl Store {
    pub fn discover() -> Result<Self, StoreError> {
        let base = directories::BaseDirs::new()
            .ok_or_else(|| StoreError("Cannot find your configuration directory.".into()))?;
        let directory = std::env::var_os("GOSH_CALC_CONFIG_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| base.config_dir().join(APP_ID));
        // Only Linux ever had cosmic-config user data. Flatpak's XDG base is
        // already scoped to this app; no host-filesystem permission is needed.
        let legacy = if cfg!(target_os = "linux") {
            Some(base.config_dir().join("cosmic").join(APP_ID).join("v1"))
        } else {
            None
        };
        Ok(Self { directory, legacy })
    }
    pub fn path(&self) -> PathBuf {
        self.directory.join("settings.json")
    }
    pub fn load(&self) -> Result<Loaded, StoreError> {
        let path = self.path();
        if path.exists() {
            let bytes = read_bounded(&path)?;
            match serde_json::from_slice::<SavedState>(&bytes) {
                Ok(mut state) => {
                    if state.schema_version != 1 {
                        return Err(StoreError("Settings were written by a newer version. They have been preserved; saving is disabled.".into()));
                    }
                    sanitize(&mut state);
                    return Ok(Loaded {
                        state,
                        notice: None,
                    });
                }
                Err(_) => {
                    let backup = self
                        .directory
                        .join(format!("settings.corrupt.{}.json", unique_id()));
                    fs::copy(&path, &backup).map_err(|e| {
                        StoreError(format!(
                            "Cannot back up unreadable settings: {e}. Saving is disabled."
                        ))
                    })?;
                    return Ok(Loaded {
                        state: SavedState::default(),
                        notice: Some(
                            "Unreadable settings were backed up. Starting with defaults.".into(),
                        ),
                    });
                }
            }
        }
        let mut state = SavedState::default();
        let Some(legacy) = self.legacy.as_ref().filter(|p| p.is_dir()) else {
            return Ok(Loaded {
                state,
                notice: None,
            });
        };
        if let Some(mode) = read_legacy::<String>(legacy, "mode")? {
            state.mode = match mode.as_str() {
                "scientific" => Mode::Scientific,
                "programmer" => Mode::Programmer,
                _ => Mode::Standard,
            };
        }
        if let Some(angle) = read_legacy::<String>(legacy, "angle")? {
            if angle == "rad" {
                state.angle = AngleUnit::Rad;
            }
        }
        if let Some(history) = read_legacy(legacy, "history")? {
            state.history = history;
        }
        sanitize(&mut state);
        let backup = self.directory.join("legacy-cosmic-v1-backup");
        fs::create_dir_all(&backup).map_err(io_error)?;
        for name in ["mode", "angle", "history"] {
            let source = legacy.join(name);
            let target = backup.join(name);
            if source.is_file() && !target.exists() {
                fs::copy(source, target).map_err(io_error)?;
            }
        }
        self.save(&state)?;
        Ok(Loaded { state, notice: Some("Imported your previous mode, angle unit and history. Original settings are unchanged.".into()) })
    }
    pub fn save(&self, state: &SavedState) -> Result<(), StoreError> {
        fs::create_dir_all(&self.directory).map_err(io_error)?;
        let mut state = state.clone();
        sanitize(&mut state);
        let bytes = serde_json::to_vec_pretty(&state)
            .map_err(|e| StoreError(format!("Cannot encode settings: {e}")))?;
        let temporary = self
            .directory
            .join(format!(".settings.{}.tmp", unique_id()));
        let result = (|| {
            let mut file = OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&temporary)
                .map_err(io_error)?;
            file.write_all(&bytes).map_err(io_error)?;
            file.sync_all().map_err(io_error)?;
            drop(file);
            fs::rename(&temporary, self.path()).map_err(io_error)
        })();
        if result.is_err() {
            let _ = fs::remove_file(&temporary);
        }
        result
    }
}

fn io_error(error: std::io::Error) -> StoreError {
    StoreError(format!("Cannot read or save calculator settings: {error}"))
}
fn unique_id() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    format!("{}-{nanos}", std::process::id())
}
fn read_bounded(path: &Path) -> Result<Vec<u8>, StoreError> {
    let file = fs::File::open(path).map_err(io_error)?;
    let mut bytes = Vec::new();
    file.take(MAX_FILE_BYTES + 1)
        .read_to_end(&mut bytes)
        .map_err(io_error)?;
    if bytes.len() as u64 > MAX_FILE_BYTES {
        return Err(StoreError(
            "Settings exceed the 1 MiB limit. They have been preserved; saving is disabled.".into(),
        ));
    }
    Ok(bytes)
}
fn read_legacy<T: serde::de::DeserializeOwned>(
    directory: &Path,
    name: &str,
) -> Result<Option<T>, StoreError> {
    let path = directory.join(name);
    if !path.exists() {
        return Ok(None);
    }
    ron::de::from_bytes(&read_bounded(&path)?)
        .map(Some)
        .map_err(|_| {
            StoreError(format!(
                "Cannot import legacy {name}. Original data is preserved; saving is disabled."
            ))
        })
}
fn sanitize(state: &mut SavedState) {
    let mut calc = CalcState::new();
    calc.history = std::mem::take(&mut state.history);
    calc.sanitize_persisted();
    calc.history
        .retain(|h| !matches!(h.value, Some(crate::engine::Value::F(v)) if !v.is_finite()));
    state.history = calc.history;
    state.window = state.window.bounded();
}

/// One writer serializes updates; filesystem work stays off the UI thread.
/// Joining on drop flushes the last queued durable state before process exit.
pub struct Writer {
    sender: Option<mpsc::Sender<SavedState>>,
    errors: Mutex<mpsc::Receiver<String>>,
    worker: Option<thread::JoinHandle<()>>,
}
impl Writer {
    pub fn new(store: Store) -> Result<Self, StoreError> {
        let (sender, receiver) = mpsc::channel();
        let (error_sender, errors) = mpsc::channel();
        let worker = thread::Builder::new()
            .name("settings-writer".into())
            .spawn(move || {
                while let Ok(mut state) = receiver.recv() {
                    // Coalesce bursts (e.g. window resizing) without losing the
                    // latest state, including the final update during shutdown.
                    while let Ok(newer) = receiver.try_recv() {
                        state = newer;
                    }
                    if let Err(error) = store.save(&state) {
                        let _ = error_sender.send(error.to_string());
                    }
                }
            })
            .map_err(io_error)?;
        Ok(Self {
            sender: Some(sender),
            errors: Mutex::new(errors),
            worker: Some(worker),
        })
    }
    pub fn save(&self, state: SavedState) -> Result<(), StoreError> {
        self.sender
            .as_ref()
            .ok_or_else(|| StoreError("Settings writer is closed.".into()))?
            .send(state)
            .map_err(|_| StoreError("Settings writer stopped unexpectedly.".into()))
    }
    pub fn error(&self) -> Option<String> {
        self.errors.lock().ok()?.try_recv().ok()
    }
}
impl Drop for Writer {
    fn drop(&mut self) {
        self.sender.take();
        if let Some(worker) = self.worker.take() {
            if worker.join().is_err() {
                log::error!("Settings writer failed during shutdown");
            }
        }
    }
}
