#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]
mod platform;
mod ui;
use gosh_calc::{persistence::Store, state::AppState, APP_NAME, VERSION};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("warn")).init();
    if let Some(argument) = std::env::args().nth(1) {
        match argument.as_str() {
            "--version" | "-V" => {
                println!("{APP_NAME} {VERSION}");
                return Ok(());
            }
            "--help" | "-h" => {
                println!("{APP_NAME}\n\nUsage: gosh-calc [--help | --version]\n\nA desktop calculator with standard, scientific and programmer modes.");
                return Ok(());
            }
            _ => return Err(format!("Unknown option: {argument}. Try --help.").into()),
        }
    }
    let (state, store) = match Store::discover() {
        Ok(store) => match store.load() {
            Ok(loaded) => {
                let mut state = AppState::from_saved(loaded.state);
                state.notice = loaded.notice;
                (state, Some(store))
            }
            Err(error) => {
                log::error!("Settings could not be loaded; saving disabled");
                (
                    AppState {
                        notice: Some(error.to_string()),
                        ..AppState::default()
                    },
                    None,
                )
            }
        },
        Err(error) => (
            AppState {
                notice: Some(error.to_string()),
                ..AppState::default()
            },
            None,
        ),
    };
    let config = platform::desktop_config(&state, store.as_ref())?;
    let controller = std::rc::Rc::new(platform::Controller::new(store)?);
    let dom = dioxus::prelude::VirtualDom::new(ui::App)
        .with_root_context(platform::Boot { state, controller });
    dioxus_desktop::launch::launch_virtual_dom(dom, config);
}
