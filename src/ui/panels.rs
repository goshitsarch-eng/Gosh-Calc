use super::Dispatch;
use dioxus::prelude::*;
use gosh_calc::{
    commands::Command,
    state::{Dialog, Theme},
    VERSION,
};

#[component]
pub fn History() -> Element {
    let dispatch = use_context::<Dispatch>();
    let model = dispatch.model.read();
    rsx! {
        aside { class: "history", "aria-label": "Calculation history",
            div { class: "panel-heading", h2 { "History" }
                button { title: "Close history", "aria-label": "Close history", onclick: move |_| dispatch.run(Command::ToggleHistory), "×" }
            }
            div { class: "history-list",
                if model.calc.history.is_empty() { p { class: "empty-state", "Your calculations will appear here." } }
                for (index, entry) in model.calc.history.iter().enumerate() {
                    button { key: "{index}", class: "history-entry", title: "Recall {entry.result}",
                        onclick: move |_| dispatch.run(Command::Recall(index)),
                        span { class: "history-expression", "{entry.expr}" } strong { "= {entry.result}" }
                    }
                }
            }
            button { class: "clear-history", disabled: !model.enabled(Command::ClearHistory), onclick: move |_| dispatch.run(Command::ClearHistory), "Clear history" }
        }
    }
}

#[component]
pub fn DialogPanel(dialog: Dialog) -> Element {
    let dispatch = use_context::<Dispatch>();
    use_effect(move || {
        document::eval("document.querySelector('[role=dialog] button')?.focus()");
    });
    let name = match dialog {
        Dialog::Settings => "Settings",
        Dialog::About => "About Gosh Calc",
        Dialog::Shortcuts => "Keyboard shortcuts",
    };
    let selected_theme = dispatch.model.read().theme;
    rsx! {
        div { class: "modal-backdrop", onclick: move |_| dispatch.run(Command::CloseDialog),
            section { class: "dialog", role: "dialog", "aria-modal": "true", "aria-labelledby": "dialog-title",
                onclick: |event| event.stop_propagation(),
                div { class: "panel-heading", h2 { id: "dialog-title", "{name}" }
                    button { title: "Close", "aria-label": "Close dialog", onclick: move |_| dispatch.run(Command::CloseDialog), "×" }
                }
                match dialog {
                    Dialog::Settings => rsx! {
                        fieldset { legend { "Appearance" }
                            for theme in [Theme::System, Theme::Light, Theme::Dark] {
                                button { "data-theme-choice": theme.css(), "aria-pressed": "{selected_theme == theme}",
                                    onclick: move |_| dispatch.run(Command::SetTheme(theme)), "{theme.label()}" }
                            }
                        }
                        p { "Mode, angle unit, history, appearance and window size are saved automatically." }
                    },
                    Dialog::About => rsx! {
                        p { class: "about-mark", "=" } h3 { "Gosh Calc {VERSION}" }
                        p { "A standard, scientific and programmer calculator. Built with Rust and Dioxus Desktop." }
                        p { "Copyright © 2026 goshitsarch-eng · MIT license" }
                        p { class: "muted", "An early preview of the cross-platform edition." }
                    },
                    Dialog::Shortcuts => rsx! {
                        dl { class: "shortcuts",
                            dt { "0–9 / A–F" } dd { "Enter digits; A–F in programmer HEX" }
                            dt { "+ − * / ^ %" } dd { "Arithmetic; ^ is XOR in programmer mode" }
                            dt { "Enter / =" } dd { "Evaluate; press again to repeat" }
                            dt { "Esc / Delete / Backspace" } dd { "Clear all / clear entry / delete digit" }
                            dt { "( ) ! & | < > ~" } dd { "Parentheses, factorial and bitwise operators" }
                            dt { "p" } dd { "π in scientific mode" }
                            dt { "Ctrl/⌘ C" } dd { "Copy result (Ctrl+Insert also works)" }
                            dt { "{crate::platform::history_shortcut_label()}" } dd { "History" }
                            dt { "Ctrl/⌘ 1, 2, 3" } dd { "Standard, scientific, programmer" }
                            dt { "Ctrl/⌘ , / F1" } dd { "Settings / this shortcut guide" }
                        }
                    },
                }
                button { class: "dialog-done", onclick: move |_| dispatch.run(Command::CloseDialog), "Done" }
            }
        }
    }
}
