// Copyright (c) 2026 goshitsarch-eng
// SPDX-License-Identifier: MIT

//! Persisted settings via cosmic-config (file backend).

use cosmic::cosmic_config::{Config, ConfigGet, ConfigSet};
use crate::engine::{AngleUnit, CalcState, HistoryEntry, Mode};

pub const CONFIG_VERSION: u64 = 1;

pub fn store() -> Option<Config> {
    match Config::new(crate::APP_ID, CONFIG_VERSION) {
        Ok(c) => Some(c),
        Err(e) => {
            log::warn!("cosmic-config unavailable: {e}");
            None
        }
    }
}

pub fn load(store: &Config, state: &mut CalcState) {
    if let Ok(m) = store.get::<String>("mode") {
        let mode = match m.as_str() {
            "scientific" => Mode::Scientific,
            "programmer" => Mode::Programmer,
            _ => Mode::Standard,
        };
        state.set_mode(mode);
    }
    if let Ok(a) = store.get::<String>("angle") {
        if a == "rad" {
            state.angle = AngleUnit::Rad;
        }
    }
    if let Ok(h) = store.get::<Vec<HistoryEntry>>("history") {
        state.history = h;
    }
}

pub fn save(store: &Option<Config>, state: &CalcState) {
    let Some(store) = store else { return };
    let tx = store.transaction();
    let mode = match state.mode {
        Mode::Standard => "standard",
        Mode::Scientific => "scientific",
        Mode::Programmer => "programmer",
    };
    let angle = match state.angle {
        AngleUnit::Deg => "deg",
        AngleUnit::Rad => "rad",
    };
    let _ = tx.set("mode", mode);
    let _ = tx.set("angle", angle);
    let _ = tx.set("history", &state.history);
    if let Err(e) = tx.commit() {
        log::warn!("failed to persist config: {e}");
    }
}
