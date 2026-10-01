//! OS integration is centralized here; the calculator never shells out.
mod clipboard;
use dioxus_desktop::{
    muda::{
        accelerator::{Accelerator, Code, Modifiers},
        Menu, MenuItem, PredefinedMenuItem, Submenu,
    },
    tao::window::Icon,
    Config, LogicalSize, WindowBuilder,
};
use gosh_calc::{
    commands::Command,
    persistence::{Store, Writer},
    state::{AppState, Dialog},
    APP_NAME,
};
use std::rc::Rc;

#[derive(Clone)]
pub struct Boot {
    pub state: AppState,
    pub controller: Rc<Controller>,
}

pub struct Controller {
    writer: Option<Writer>,
    clipboard: clipboard::Clipboard,
}
impl Controller {
    pub fn new(store: Option<Store>) -> Result<Self, Box<dyn std::error::Error>> {
        Ok(Self {
            writer: store.map(Writer::new).transpose()?,
            clipboard: clipboard::Clipboard::default(),
        })
    }
    pub fn execute(&self, state: &mut AppState, command: Command) -> bool {
        let previous_mode = state.calc.mode;
        let effect = state.dispatch(command);
        if state.calc.mode == gosh_calc::engine::Mode::Scientific
            && previous_mode != state.calc.mode
        {
            let window = dioxus_desktop::window();
            let size = window.inner_size().to_logical::<f64>(window.scale_factor());
            if !window.is_maximized() && size.width < 760.0 {
                window.set_inner_size(LogicalSize::new(760.0, size.height));
            }
        }
        if effect.persist {
            if let Some(writer) = &self.writer {
                if let Err(error) = writer.save(state.saved()) {
                    state.notice = Some(error.to_string());
                }
            }
        }
        if let Some(text) = effect.copy {
            let result = self.clipboard.copy(text);
            state.notice = Some(match result {
                Ok(()) => "Copied".into(),
                Err(error) => format!("Could not copy: {error}"),
            });
        }
        effect.quit
    }
    pub fn error(&self) -> Option<String> {
        self.writer.as_ref()?.error()
    }
}

pub fn primary_modifier(control: bool, meta: bool) -> bool {
    if cfg!(target_os = "macos") {
        meta
    } else {
        control
    }
}

pub fn keyboard(
    key: &str,
    control: bool,
    meta: bool,
    alt: bool,
    shift: bool,
    mode: gosh_calc::engine::Mode,
    base: gosh_calc::engine::Base,
) -> Option<Command> {
    // Command+H belongs to native Hide on macOS; history uses Command+Shift+H.
    if cfg!(target_os = "macos") && meta && !shift && key.eq_ignore_ascii_case("h") {
        return None;
    }
    let primary = primary_modifier(control, meta) || (control && key == "Insert");
    gosh_calc::commands::keyboard(key, primary, alt, mode, base)
}

pub fn history_shortcut_label() -> &'static str {
    if cfg!(target_os = "macos") {
        "h / ⌘ Shift H"
    } else {
        "h / Ctrl H"
    }
}

pub fn configure_webview() {
    #[cfg(target_os = "linux")]
    {
        use dioxus_desktop::wry::WebViewExtUnix;
        use glib::prelude::*;
        let view = dioxus_desktop::window().webview.webview();
        let settings = view.property::<glib::Object>("settings");
        // A calculator needs no media, WebGL or back/forward page cache. Use
        // properties provided by the running system WebKit, preserving its
        // normal sandbox and JavaScript engine.
        for name in [
            "enable-webgl",
            "enable-webaudio",
            "enable-media",
            "enable-page-cache",
            "enable-media-stream",
            "enable-mediasource",
        ] {
            if settings.find_property(name).is_some() {
                settings.set_property(name, false);
            }
        }
    }
}

pub fn menu_command(id: &str) -> Option<Command> {
    use gosh_calc::engine::Mode;
    Some(match id {
        "copy" => Command::Copy,
        "clear" => Command::ClearAll,
        "history" => Command::ToggleHistory,
        "standard" => Command::SetMode(Mode::Standard),
        "scientific" => Command::SetMode(Mode::Scientific),
        "programmer" => Command::SetMode(Mode::Programmer),
        "settings" => Command::ShowDialog(Dialog::Settings),
        "about" => Command::ShowDialog(Dialog::About),
        "shortcuts" => Command::ShowDialog(Dialog::Shortcuts),
        "quit" => Command::Quit,
        _ => return None,
    })
}

fn accelerator(code: Code) -> Option<Accelerator> {
    Some(Accelerator::new(
        Some(if cfg!(target_os = "macos") {
            Modifiers::META
        } else {
            Modifiers::CONTROL
        }),
        code,
    ))
}

fn menus() -> Result<Menu, Box<dyn std::error::Error>> {
    let menu = Menu::new();
    let app = Submenu::new(
        if cfg!(target_os = "macos") {
            APP_NAME
        } else {
            "File"
        },
        true,
    );
    app.append_items(&[
        &MenuItem::with_id("about", "About Gosh Calc", true, None),
        &MenuItem::with_id("settings", "Settings…", true, accelerator(Code::Comma)),
        &PredefinedMenuItem::separator(),
    ])?;
    #[cfg(target_os = "macos")]
    app.append_items(&[
        &PredefinedMenuItem::services(None),
        &PredefinedMenuItem::hide(None),
        &PredefinedMenuItem::hide_others(None),
        &PredefinedMenuItem::show_all(None),
        &PredefinedMenuItem::separator(),
    ])?;
    app.append(&MenuItem::with_id(
        "quit",
        "Quit Gosh Calc",
        true,
        accelerator(Code::KeyQ),
    ))?;
    let edit = Submenu::new("Edit", true);
    edit.append_items(&[
        &MenuItem::with_id("copy", "Copy Result", true, accelerator(Code::KeyC)),
        &MenuItem::with_id("clear", "Clear Calculation", true, None),
    ])?;
    let view = Submenu::new("View", true);
    view.append_items(&[
        &MenuItem::with_id("standard", "Standard", true, accelerator(Code::Digit1)),
        &MenuItem::with_id("scientific", "Scientific", true, accelerator(Code::Digit2)),
        &MenuItem::with_id("programmer", "Programmer", true, accelerator(Code::Digit3)),
        &PredefinedMenuItem::separator(),
        &MenuItem::with_id(
            "history",
            "History",
            true,
            Some(Accelerator::new(
                Some(if cfg!(target_os = "macos") {
                    Modifiers::META | Modifiers::SHIFT
                } else {
                    Modifiers::CONTROL
                }),
                Code::KeyH,
            )),
        ),
    ])?;
    let help = Submenu::new("Help", true);
    help.append(&MenuItem::with_id(
        "shortcuts",
        "Keyboard Shortcuts",
        true,
        None,
    ))?;
    menu.append_items(&[&app, &edit, &view, &help])?;
    #[cfg(target_os = "macos")]
    {
        let window = Submenu::new("Window", true);
        window.append_items(&[
            &PredefinedMenuItem::minimize(None),
            &PredefinedMenuItem::maximize(None),
        ])?;
        menu.append(&window)?;
    }
    Ok(menu)
}

pub fn desktop_config(
    state: &AppState,
    store: Option<&Store>,
) -> Result<Config, Box<dyn std::error::Error>> {
    let geometry = state.window.bounded();
    let width = if state.calc.mode == gosh_calc::engine::Mode::Scientific {
        geometry.width.max(760.0)
    } else {
        geometry.width
    };
    let builder = WindowBuilder::new()
        .with_title(APP_NAME)
        .with_inner_size(LogicalSize::new(width, geometry.height))
        .with_min_inner_size(LogicalSize::new(360.0, 480.0))
        .with_maximized(geometry.maximized)
        .with_always_on_top(false);
    let icon = Icon::from_rgba(include_bytes!("../../resources/icon.rgba").to_vec(), 64, 64)?;
    let mut config = Config::new()
        .with_window(builder)
        .with_icon(icon)
        .with_menu(menus()?)
        .with_navigation_handler(|_| false)
        .with_disable_context_menu(true)
        .with_disable_drag_drop_handler(true);
    if let Some(store) = store {
        config = config.with_data_directory(store.directory.join("webview"));
    }
    Ok(config)
}
