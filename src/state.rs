use crate::engine::{AngleUnit, CalcState, HistoryEntry, Mode};
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Theme {
    #[default]
    System,
    Light,
    Dark,
}

impl Theme {
    pub fn label(self) -> &'static str {
        match self {
            Self::System => "Follow System",
            Self::Light => "Light",
            Self::Dark => "Dark",
        }
    }
    pub fn css(self) -> &'static str {
        match self {
            Self::System => "system",
            Self::Light => "light",
            Self::Dark => "dark",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct WindowState {
    pub width: f64,
    pub height: f64,
    pub maximized: bool,
}
impl Default for WindowState {
    fn default() -> Self {
        Self {
            width: 460.0,
            height: 700.0,
            maximized: false,
        }
    }
}
impl WindowState {
    pub fn bounded(self) -> Self {
        let defaults = Self::default();
        Self {
            width: if self.width.is_finite() {
                self.width.clamp(360.0, 2400.0)
            } else {
                defaults.width
            },
            height: if self.height.is_finite() {
                self.height.clamp(480.0, 1600.0)
            } else {
                defaults.height
            },
            maximized: self.maximized,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct SavedState {
    pub schema_version: u32,
    pub mode: Mode,
    pub angle: AngleUnit,
    pub history: Vec<HistoryEntry>,
    pub theme: Theme,
    pub window: WindowState,
}
impl Default for SavedState {
    fn default() -> Self {
        Self {
            schema_version: 1,
            mode: Mode::Standard,
            angle: AngleUnit::Deg,
            history: Vec::new(),
            theme: Theme::System,
            window: WindowState::default(),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Dialog {
    Settings,
    About,
    Shortcuts,
}

#[derive(Clone, Debug)]
pub struct AppState {
    pub calc: CalcState,
    pub theme: Theme,
    pub window: WindowState,
    pub history_open: bool,
    pub dialog: Option<Dialog>,
    pub notice: Option<String>,
}
impl AppState {
    pub fn from_saved(saved: SavedState) -> Self {
        let mut calc = CalcState::new();
        calc.set_mode(saved.mode);
        calc.angle = saved.angle;
        calc.history = saved.history;
        calc.sanitize_persisted();
        Self {
            calc,
            theme: saved.theme,
            window: saved.window.bounded(),
            history_open: false,
            dialog: None,
            notice: None,
        }
    }
    pub fn saved(&self) -> SavedState {
        SavedState {
            schema_version: 1,
            mode: self.calc.mode,
            angle: self.calc.angle,
            history: self.calc.history.clone(),
            theme: self.theme,
            window: self.window.bounded(),
        }
    }
}
impl Default for AppState {
    fn default() -> Self {
        Self::from_saved(SavedState::default())
    }
}
