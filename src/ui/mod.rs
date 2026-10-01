mod keypad;
mod panels;
#[cfg(feature = "ui-test")]
mod smoke;
use crate::platform::{self, Boot};
use dioxus::prelude::*;
use gosh_calc::{
    commands::Command,
    engine::{AngleUnit, Base, Mode},
    state::{AppState, Dialog, WindowState},
};

#[derive(Clone, Copy)]
pub struct Dispatch {
    pub model: Signal<AppState>,
    pub action: Callback<Command>,
}
impl Dispatch {
    pub fn run(&self, command: Command) {
        self.action.call(command);
    }
}

#[component]
pub fn App() -> Element {
    use_hook(platform::configure_webview);
    let boot = use_context::<Boot>();
    let initial = boot.state;
    let model = use_signal(move || initial);
    #[cfg(feature = "ui-test")]
    let mut test_revision = use_signal(|| 0_u64);
    let controller = boot.controller.clone();
    let action = use_callback(move |command| {
        let mut model = model;
        #[cfg(feature = "ui-test")]
        {
            *test_revision.write() += 1;
        }
        if controller.execute(&mut model.write(), command) {
            dioxus_desktop::window().close();
        }
    });
    let dispatch = use_context_provider(|| Dispatch { model, action });
    let menus = dispatch;
    dioxus_desktop::use_muda_event_handler(move |event| {
        if let Some(command) = platform::menu_command(event.id.as_ref()) {
            menus.run(command);
        }
    });
    let geometry = dispatch;
    dioxus_desktop::use_wry_event_handler(move |event, _| {
        use dioxus_desktop::tao::event::{Event, WindowEvent};
        if let Event::WindowEvent { event, .. } = event {
            if matches!(event, WindowEvent::Resized(_) | WindowEvent::CloseRequested) {
                let window = dioxus_desktop::window();
                let size = window.inner_size().to_logical::<f64>(window.scale_factor());
                let previous = geometry.model.read().window;
                let maximized = window.is_maximized();
                geometry.run(Command::SetWindow(WindowState {
                    width: if maximized {
                        previous.width
                    } else {
                        size.width
                    },
                    height: if maximized {
                        previous.height
                    } else {
                        size.height
                    },
                    maximized,
                }));
            }
        }
    });
    let errors = dispatch;
    let error_controller = boot.controller;
    use_future(move || {
        let error_controller = error_controller.clone();
        async move {
            loop {
                tokio::time::sleep(std::time::Duration::from_millis(300)).await;
                if let Some(error) = error_controller.error() {
                    log::error!("Settings persistence failed");
                    let mut model = errors.model;
                    model.write().notice = Some(error);
                }
            }
        }
    });
    let focus_state = use_memo(move || {
        let state = model.read();
        (state.dialog, state.history_open)
    });
    use_effect(move || {
        let (dialog, _) = *focus_state.read();
        if dialog.is_some() {
            return;
        }
        document::eval(
            r#"
            if (!window.goshFocusInstalled) {
                window.goshFocusInstalled = true;
                document.addEventListener('keydown', event => {
                    if ((event.key === 'Enter' || event.key === ' ') && event.target.closest('button, select')) event.stopPropagation();
                    const dialog = document.querySelector('[role=dialog]');
                    if (dialog && event.key === 'Tab') {
                        const focusable = [...dialog.querySelectorAll('button:not([disabled]), select')];
                        const first = focusable[0], last = focusable[focusable.length - 1];
                        if (event.shiftKey && document.activeElement === first) { last.focus(); event.preventDefault(); }
                        if (!event.shiftKey && document.activeElement === last) { first.focus(); event.preventDefault(); }
                    }
                }, true);
            }
            document.querySelector('.app')?.focus();
        "#,
        );
    });
    let notice = use_memo(move || model.read().notice.clone());
    use_effect(move || {
        if notice.read().as_deref() == Some("Copied") {
            spawn(async move {
                tokio::time::sleep(std::time::Duration::from_secs(2)).await;
                let mut model = model;
                let copied = model.read().notice.as_deref() == Some("Copied");
                if copied {
                    model.write().notice = None;
                }
            });
        }
    });
    #[cfg(feature = "ui-test")]
    smoke::install();
    let keyboard_dispatch = dispatch;
    let state = model.read();
    let history_open = state.history_open;
    let theme = state.theme.css();
    #[cfg(feature = "ui-test")]
    let revision = Some(test_revision.read().to_string());
    #[cfg(not(feature = "ui-test"))]
    let revision: Option<String> = None;
    rsx! {
        style { {include_str!("../../resources/style.css")} }
        main { class: "app", "data-theme": theme, "data-test-revision": revision, tabindex: "0", "aria-label": "Gosh Calc",
            onkeydown: move |event: KeyboardEvent| {
                if event.is_composing() { return; }
                let key = event.key().to_string();
                let state = keyboard_dispatch.model.read();
                if state.dialog.is_some() {
                    drop(state);
                    if key == "Escape" { event.prevent_default(); keyboard_dispatch.run(Command::CloseDialog); }
                    return;
                }
                let modifiers = event.modifiers();
                let command = platform::keyboard(&key, modifiers.ctrl(), modifiers.meta(), modifiers.alt(), modifiers.shift(), state.calc.mode, state.calc.base);
                drop(state);
                if let Some(command) = command { event.prevent_default(); keyboard_dispatch.run(command); }
            },
            header { class: "toolbar",
                div { class: "brand", span { class: "brand-icon", "=" } span { "Gosh Calc" } }
                div { class: "toolbar-actions",
                    button { title: "History", "aria-label": "History", "aria-expanded": "{history_open}", onclick: move |_| dispatch.run(Command::ToggleHistory), "↺" }
                    button { title: "Settings", "aria-label": "Settings", onclick: move |_| dispatch.run(Command::ShowDialog(Dialog::Settings)), "⚙" }
                    button { title: "Keyboard shortcuts", "aria-label": "Keyboard shortcuts", onclick: move |_| dispatch.run(Command::ShowDialog(Dialog::Shortcuts)), "?" }
                }
            }
            nav { class: "modes", "aria-label": "Calculator mode",
                for (mode, label) in [(Mode::Standard,"Standard"),(Mode::Scientific,"Scientific"),(Mode::Programmer,"Programmer")] {
                    button { key: "{label}", "data-mode": label, "aria-pressed": "{state.calc.mode == mode}",
                        onclick: move |_| dispatch.run(Command::SetMode(mode)), "{label}" }
                }
            }
            div { class: if history_open { "workspace with-history" } else { "workspace" },
                section { class: "calculator", "aria-label": "Calculation", Display {} keypad::Keypad {} }
                if history_open { panels::History {} }
            }
            if let Some(notice) = &state.notice {
                div { class: "notice", role: "status", span { "{notice}" }
                    button { "aria-label": "Dismiss notification", title: "Dismiss", onclick: move |_| dispatch.run(Command::DismissNotice), "×" }
                }
            }
            if let Some(dialog) = state.dialog { panels::DialogPanel { dialog } }
        }
    }
}

#[component]
fn Display() -> Element {
    let dispatch = use_context::<Dispatch>();
    let state = dispatch.model.read();
    let expression = state.calc.expression_display();
    let result = state.calc.result_display();
    rsx! {
        section { class: "display", "aria-label": "Calculator display",
            div { class: "expression-row", span { class: "expression", title: "{expression}", "{expression}" }
                button { title: "Copy result", "aria-label": "Copy result", onclick: move |_| dispatch.run(Command::Copy), "⧉" }
            }
            output { id: "result", class: "result", "aria-live": "polite", title: "{result}", "{result}" }
            if let Some(error) = state.calc.error { p { class: "error-detail", "{error}" } }
            if state.calc.mode == Mode::Scientific {
                button { class: "angle", "aria-label": "Toggle angle unit", onclick: move |_| dispatch.run(Command::ToggleAngle),
                    if state.calc.angle == AngleUnit::Deg { "DEG" } else { "RAD" }
                }
            }
            if let Some((hex, dec, oct, bin)) = state.calc.base_readout() {
                div { class: "base-readout",
                    for (base, value) in [(Base::Hex,hex),(Base::Dec,dec),(Base::Oct,oct),(Base::Bin,bin)] {
                        button { key: "{base.label()}", "data-base": base.label(), "aria-pressed": "{state.calc.base == base}",
                            title: "Select {base.label()}", onclick: move |_| dispatch.run(Command::SetBase(base)),
                            span { class: "base-label", "{base.label()}" } span { class: "base-value", "{value}" }
                        }
                    }
                }
            }
        }
    }
}
