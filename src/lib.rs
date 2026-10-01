//! Portable calculator domain, commands, settings and persistence.
pub mod commands;
pub mod engine;
pub mod persistence;
pub mod state;

pub const APP_ID: &str = "dev.goshapps.calc";
pub const APP_NAME: &str = "Gosh Calc";
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
