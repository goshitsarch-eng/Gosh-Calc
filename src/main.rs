// Copyright (c) 2026 goshitsarch-eng
// SPDX-License-Identifier: MIT

//! Gosh Calc — a calculator for the COSMIC desktop.

mod config;
mod engine;
mod i18n;

use cosmic::app::{context_drawer, Core, Settings, Task};
use cosmic::cosmic_config::Config;
use cosmic::iced::alignment::{Horizontal, Vertical};
use cosmic::iced::{event, keyboard, Event, Length, Size, Subscription};
use cosmic::prelude::*;
use cosmic::widget::toaster::{Toast, ToastId, Toasts};
use cosmic::widget::{self, button, column, container, row, scrollable, text};
use cosmic::{executor, theme, Element};

use engine::{AngleUnit, Base, BinOp, CalcState, Const, Mode, UnaryOp};

pub const APP_ID: &str = "dev.goshapps.calc";

/// Preferred window size per mode (GNOME-Calculator-style: the
/// window fits the pad). Column counts differ per mode (4/8/6), so a
/// single width either clips scientific labels or bloats standard.
/// Heights compensate for the display block, which is tallest in
/// programmer mode (base readout + selector), keeping key rows near
/// identical across modes (B15).
pub fn mode_window_size(mode: Mode) -> Size {
    match mode {
        Mode::Standard => Size::new(400., 580.),
        Mode::Scientific => Size::new(640., 600.),
        Mode::Programmer => Size::new(560., 660.),
    }
}

/// Persisted mode for boot-time window sizing. `init` loads the full
/// state again; this peek only sizes the initial window.
fn persisted_mode() -> Mode {
    let mut state = CalcState::new();
    if let Some(store) = config::store() {
        config::load(&store, &mut state);
    }
    state.mode
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("warn")).init();
    i18n::init();
    let settings = Settings::default().size(mode_window_size(persisted_mode()));
    // The configured icon theme may not be installed (stale
    // CosmicTk config, minimal system, sandbox). libcosmic renders
    // a missing icon as an empty SVG, which makes every icon-only
    // control — window minimize/maximize/close, history, copy —
    // invisible but still clickable. Fall back to an installed
    // theme so those controls always render (B14).
    let settings = match resolve_icon_theme(&cosmic::config::icon_theme()) {
        Some(fallback) => settings.default_icon_theme(fallback),
        None => settings,
    };
    cosmic::app::run::<App>(settings, ())?;
    Ok(())
}

/// Icon themes to try when the configured one is not installed, in
/// preference order. Cosmic first: it is the only theme carrying the
/// COSMIC-specific names.
const FALLBACK_ICON_THEMES: [&str; 3] = ["Cosmic", "Adwaita", "hicolor"];

/// Return a fallback icon theme when `configured` cannot be used,
/// or `None` to keep the configured theme.
fn resolve_icon_theme(configured: &str) -> Option<String> {
    resolve_icon_theme_in(configured, &icon_theme_dirs())
}

fn resolve_icon_theme_in(configured: &str, dirs: &[std::path::PathBuf]) -> Option<String> {
    if is_usable_theme_name(configured) && theme_installed(configured, dirs) {
        return None;
    }
    let found = FALLBACK_ICON_THEMES
        .iter()
        .find(|t| theme_installed(t, dirs))
        .map(|t| t.to_string());
    match &found {
        Some(fallback) => log::warn!(
            "icon theme \"{configured}\" is not installed; falling back to \"{fallback}\""
        ),
        None => log::warn!(
            "icon theme \"{configured}\" is not installed and no fallback theme was found"
        ),
    }
    found
}

/// Reject theme names that could escape the icon directories (the
/// config file is user-editable) or otherwise confuse lookup.
fn is_usable_theme_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 64
        && !name.contains(['/', '\\'])
        && !name.contains("..")
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.' | ' '))
}

fn theme_installed(theme: &str, dirs: &[std::path::PathBuf]) -> bool {
    dirs.iter()
        .any(|d| d.join(theme).join("index.theme").is_file())
}

/// XDG icon search directories: `$XDG_DATA_HOME/icons`,
/// `$XDG_DATA_DIRS/icons` (or the spec defaults), plus the legacy
/// `~/.icons`.
fn icon_theme_dirs() -> Vec<std::path::PathBuf> {
    use std::path::PathBuf;
    let mut dirs = Vec::new();
    if let Ok(home) = std::env::var("HOME") {
        match std::env::var("XDG_DATA_HOME") {
            Ok(custom) if !custom.is_empty() => dirs.push(PathBuf::from(custom).join("icons")),
            _ => dirs.push(PathBuf::from(&home).join(".local/share/icons")),
        }
        dirs.push(PathBuf::from(home).join(".icons"));
    }
    match std::env::var("XDG_DATA_DIRS") {
        Ok(list) => {
            for dir in list.split(':').filter(|s| !s.is_empty()) {
                dirs.push(PathBuf::from(dir).join("icons"));
            }
        }
        Err(_) => {
            dirs.push(PathBuf::from("/usr/local/share/icons"));
            dirs.push(PathBuf::from("/usr/share/icons"));
        }
    }
    dirs
}

#[derive(Clone, Debug)]
pub enum Message {
    Digit(u8),
    Dot,
    Exp,
    Ans,
    Binary(BinOp),
    Unary(UnaryOp),
    Percent,
    Equals,
    Backspace,
    ClearEntry,
    ClearAll,
    ToggleSign,
    SetBase(Base),
    ToggleAngle,
    Constant(Const),
    LParen,
    RParen,
    Recall(usize),
    ClearHistory,
    CopyResult,
    ToggleContext,
    SetMode(Mode),
    ToastClose(ToastId),
    Surface(cosmic::surface::Action),
    KeyPressed {
        key: keyboard::Key,
        physical: keyboard::key::Physical,
        modifiers: keyboard::Modifiers,
    },
}

/// Every engine-relevant mutation, as a pure state transition. Tests
/// drive the app through this function without constructing a Core.
pub fn reduce(state: &mut CalcState, msg: &Message) {
    match msg {
        Message::Digit(d) => state.input_digit(*d),
        Message::Dot => state.input_dot(),
        Message::Exp => state.input_exp(),
        Message::Ans => state.input_ans(),
        Message::Binary(op) => state.input_binary(*op),
        Message::Unary(op) => state.input_unary(*op),
        Message::Percent => state.input_percent(),
        Message::Equals => {
            state.equals();
        }
        Message::Backspace => state.backspace(),
        Message::ClearEntry => state.clear_entry(),
        Message::ClearAll => state.clear_all(),
        Message::ToggleSign => state.toggle_sign(),
        Message::SetBase(b) => state.set_base(*b),
        Message::ToggleAngle => state.toggle_angle(),
        Message::Constant(c) => state.input_const(*c),
        Message::LParen => state.input_lparen(),
        Message::RParen => state.input_rparen(),
        Message::Recall(i) => state.recall_history(*i),
        Message::ClearHistory => state.clear_history(),
        Message::SetMode(m) => state.set_mode(*m),
        _ => {}
    }
}

/// Map a physical key press to a Message, mode-aware.
fn key_message(
    key: &keyboard::Key,
    physical: keyboard::key::Physical,
    modifiers: keyboard::Modifiers,
    mode: Mode,
    base: Base,
) -> Option<Message> {
    use keyboard::key::{Code, Named, Physical};
    if modifiers.control() {
        if matches!(key.as_ref(), keyboard::Key::Named(Named::Insert)) {
            return Some(Message::CopyResult);
        }
        return match key.as_ref() {
            keyboard::Key::Character("c") | keyboard::Key::Character("C") => {
                Some(Message::CopyResult)
            }
            keyboard::Key::Character("h") | keyboard::Key::Character("H") => {
                Some(Message::ToggleContext)
            }
            _ => None,
        };
    }
    // numpad keys arrive as physical codes; operators/enter/decimal are
    // unambiguous regardless of numlock
    if let Physical::Code(code) = physical {
        match code {
            Code::NumpadEnter | Code::NumpadEqual => return Some(Message::Equals),
            Code::NumpadAdd => return Some(Message::Binary(BinOp::Add)),
            Code::NumpadSubtract => return Some(Message::Binary(BinOp::Sub)),
            Code::NumpadMultiply => return Some(Message::Binary(BinOp::Mul)),
            Code::NumpadDivide => return Some(Message::Binary(BinOp::Div)),
            Code::NumpadDecimal | Code::NumpadComma => return Some(Message::Dot),
            Code::NumpadBackspace => return Some(Message::Backspace),
            // digits only meaningful with numlock on, which produces
            // Character("0".."9") as the logical key — fall through
            _ => {}
        }
    }
    match key {
        keyboard::Key::Named(Named::Enter) => Some(Message::Equals),
        keyboard::Key::Named(Named::Backspace) => Some(Message::Backspace),
        keyboard::Key::Named(Named::Escape) => Some(Message::ClearAll),
        keyboard::Key::Named(Named::Delete) => Some(Message::ClearEntry),
        keyboard::Key::Character(c) => match c.as_str() {
            "0" => Some(Message::Digit(0)),
            "1" => Some(Message::Digit(1)),
            "2" => Some(Message::Digit(2)),
            "3" => Some(Message::Digit(3)),
            "4" => Some(Message::Digit(4)),
            "5" => Some(Message::Digit(5)),
            "6" => Some(Message::Digit(6)),
            "7" => Some(Message::Digit(7)),
            "8" => Some(Message::Digit(8)),
            "9" => Some(Message::Digit(9)),
            "." | "," => Some(Message::Dot),
            "+" => Some(Message::Binary(BinOp::Add)),
            "-" => Some(Message::Binary(BinOp::Sub)),
            "*" => Some(Message::Binary(BinOp::Mul)),
            "/" => Some(Message::Binary(BinOp::Div)),
            "^" => Some(Message::Binary(if mode == Mode::Programmer {
                BinOp::Xor
            } else {
                BinOp::Pow
            })),
            "%" => Some(Message::Percent),
            "=" => Some(Message::Equals),
            "(" => Some(Message::LParen),
            ")" => Some(Message::RParen),
            "!" => Some(Message::Unary(UnaryOp::Fact)),
            "&" => Some(Message::Binary(BinOp::And)),
            "|" => Some(Message::Binary(BinOp::Or)),
            "<" => Some(Message::Binary(BinOp::Shl)),
            ">" => Some(Message::Binary(BinOp::Shr)),
            "~" => Some(Message::Unary(UnaryOp::Not)),
            "p" | "P" if mode == Mode::Scientific => Some(Message::Constant(Const::Pi)),
            "e" | "E" if mode == Mode::Programmer && base == Base::Hex => Some(Message::Digit(14)),
            "a" | "A" | "b" | "B" | "c" | "C" | "d" | "D" | "f" | "F"
                if mode == Mode::Programmer && base == Base::Hex =>
            {
                // `c` is the matched arm text above, so this is always a
                // hex letter in practice; the filter keeps it total so
                // keyboard input can never panic here.
                c.to_ascii_lowercase()
                    .chars()
                    .next()
                    .filter(|ch| ('a'..='f').contains(ch))
                    .map(|ch| Message::Digit(ch as u8 - b'a' + 10))
            }
            // `h` is never a hex digit, so it is safe to use bare (D18).
            "h" | "H" => Some(Message::ToggleContext),
            _ => None,
        },
        _ => None,
    }
}

pub struct App {
    core: Core,
    state: CalcState,
    store: Option<Config>,
    toasts: Toasts<Message>,
}

/// Whether handling this message can mutate persisted state (mode,
/// angle unit, history). Everything else must skip the config write
/// so typing never touches the disk (P-1).
fn needs_save(msg: &Message) -> bool {
    matches!(
        msg,
        Message::Equals | Message::ClearHistory | Message::ToggleAngle | Message::SetMode(_)
    )
}

impl App {
    fn save(&self) {
        config::save(&self.store, &self.state);
    }
}

impl cosmic::Application for App {
    type Executor = executor::Default;
    type Flags = ();
    type Message = Message;
    const APP_ID: &'static str = APP_ID;

    fn core(&self) -> &Core {
        &self.core
    }

    fn core_mut(&mut self) -> &mut Core {
        &mut self.core
    }

    fn init(core: Core, _flags: Self::Flags) -> (Self, Task<Self::Message>) {
        // Mode switching lives in a visible text-button row in the
        // content view (see `mode_switcher`), not in a nav sidebar:
        // at calculator widths the sidebar is condensed away behind
        // an icon-only toggle whose COSMIC-specific icons may not be
        // installed at all, leaving no visible way to change modes.
        let store = config::store();
        let mut state = CalcState::new();
        if let Some(store) = &store {
            config::load(store, &mut state);
        }

        let mut app = Self {
            core,
            state,
            store,
            toasts: Toasts::new(Message::ToastClose),
        };
        app.set_header_title(fl!("app-title"));
        if let Some(id) = app.core.main_window_id() {
            let t = app.set_window_title(fl!("app-title"), id);
            return (app, t);
        }
        (app, Task::none())
    }

    fn header_end(&self) -> Vec<Element<'_, Self::Message>> {
        vec![widget::tooltip(
            button::icon(widget::icon::from_name("document-open-recent-symbolic"))
                .on_press(Message::ToggleContext)
                .description(fl!("history")),
            text::body(fl!("history")),
            widget::tooltip::Position::Bottom,
        )
        .into()]
    }

    fn context_drawer(&self) -> Option<context_drawer::ContextDrawer<'_, Self::Message>> {
        if !self.core.window.show_context {
            return None;
        }
        let spacing = theme::spacing();
        let mut list = column![]
            .spacing(spacing.space_xxs)
            .padding(spacing.space_s);
        if self.state.history.is_empty() {
            list = list.push(text::body(fl!("history-empty")));
        }
        for (i, h) in self.state.history.iter().enumerate() {
            list = list.push(
                button::custom(
                    column![text::body(&h.expr), text::title4(&h.result),]
                        .spacing(spacing.space_xxxs),
                )
                .class(theme::Button::MenuItem)
                .width(Length::Fill)
                .on_press(Message::Recall(i)),
            );
        }
        let content = scrollable(container(list).width(Length::Fill));
        Some(
            context_drawer::context_drawer(content, Message::ToggleContext)
                .title(fl!("history"))
                .footer(
                    button::destructive(fl!("history-clear"))
                        .width(Length::Fill)
                        .on_press_maybe(if self.state.history.is_empty() {
                            None
                        } else {
                            Some(Message::ClearHistory)
                        }),
                ),
        )
    }

    fn update(&mut self, message: Self::Message) -> Task<Self::Message> {
        match message {
            Message::CopyResult => {
                let text = self.state.result_display();
                let toast = self.toasts.push(Toast::new(fl!("copied")));
                return Task::batch([
                    cosmic::iced::clipboard::write(text),
                    toast.map(cosmic::Action::App),
                ]);
            }
            Message::ToastClose(id) => {
                self.toasts.remove(id);
            }
            Message::ToggleContext => {
                let show = !self.core.window.show_context;
                self.core_mut().set_show_context(show);
            }
            Message::Surface(a) => {
                return cosmic::task::message(cosmic::Action::Cosmic(
                    cosmic::app::Action::Surface(a),
                ));
            }
            Message::KeyPressed {
                key,
                physical,
                modifiers,
            } => {
                if let Some(m) =
                    key_message(&key, physical, modifiers, self.state.mode, self.state.base)
                {
                    // Shell-level messages are re-dispatched through update
                    // so copy-toast and drawer logic live in exactly one place.
                    return self.update(m);
                }
            }
            m => {
                let save = needs_save(&m);
                let old_mode = self.state.mode;
                reduce(&mut self.state, &m);
                if save {
                    self.save();
                }
                // Grow/shrink the window to fit the new pad (B15).
                // No-op when the mode did not actually change, and
                // harmless when maximized/tiled (the compositor
                // ignores the request and Fill layout adapts).
                if matches!(m, Message::SetMode(_)) && self.state.mode != old_mode {
                    if let Some(id) = self.core.main_window_id() {
                        return cosmic::iced::window::resize(id, mode_window_size(self.state.mode));
                    }
                }
            }
        }
        Task::none()
    }

    fn subscription(&self) -> Subscription<Self::Message> {
        event::listen_with(|event, _status, _id| match event {
            Event::Keyboard(keyboard::Event::KeyPressed {
                key,
                physical_key,
                modifiers,
                ..
            }) => Some(Message::KeyPressed {
                key,
                physical: physical_key,
                modifiers,
            }),
            _ => None,
        })
    }

    fn view(&self) -> Element<'_, Self::Message> {
        let spacing = theme::spacing();
        let mut root = column![]
            .spacing(spacing.space_xs)
            .padding(spacing.space_s)
            .width(Length::Fill)
            .height(Length::Fill);

        root = root.push(self.mode_switcher());
        root = root.push(self.display());
        root = root.push(match self.state.mode {
            Mode::Standard => self.standard_pad(),
            Mode::Scientific => self.scientific_pad(),
            Mode::Programmer => self.programmer_pad(),
        });
        widget::toaster::toaster(&self.toasts, root)
    }
}

// ---------- view helpers ----------

enum KeyKind {
    /// Digits, entry keys, basic operators: large label.
    Digit,
    Op,
    Action,
    /// Named functions (trig, logs, powers, ...): smaller label so
    /// multi-glyph captions fit narrow keys without clipping.
    Func,
    Equals,
}

fn key<'a>(label: impl Into<String>, kind: KeyKind, msg: Option<Message>) -> Element<'a, Message> {
    // Every key is a pill button: bare-text keys read as broken
    // labels next to real keys (B15). Only the label size varies,
    // by kind, identically in every mode.
    let label = match kind {
        KeyKind::Func => text::body(label.into()),
        KeyKind::Digit | KeyKind::Op | KeyKind::Action | KeyKind::Equals => {
            text::title4(label.into())
        }
    };
    let content = container(label)
        .align_x(Horizontal::Center)
        .align_y(Vertical::Center)
        .width(Length::Fill)
        .height(Length::Fill);
    button::custom(content)
        .class(match kind {
            KeyKind::Equals => theme::Button::Suggested,
            KeyKind::Digit | KeyKind::Op | KeyKind::Action | KeyKind::Func => {
                theme::Button::Standard
            }
        })
        .width(Length::Fill)
        .height(Length::Fill)
        .on_press_maybe(msg)
        .into()
}

/// Shrink-height pill button for the mode-switcher and base-selector
/// rows. Unlike pad `key()` cells (which Fill their grid row), these
/// rows size to content: a Fill-height button here would swallow the
/// window's leftover vertical space (B15).
fn pill_button<'a>(label: impl Into<String>, active: bool, msg: Message) -> Element<'a, Message> {
    let spacing = theme::spacing();
    button::custom(
        container(text::body(label.into()))
            .align_x(Horizontal::Center)
            .align_y(Vertical::Center)
            .width(Length::Fill)
            .padding([spacing.space_xxxs, spacing.space_xxs]),
    )
    .class(if active {
        theme::Button::Suggested
    } else {
        theme::Button::Standard
    })
    .width(Length::Fill)
    .on_press(msg)
    .into()
}

fn gap<'a>() -> Element<'a, Message> {
    widget::Space::new().width(Length::Fill).into()
}

fn grid_row<'a>(cells: Vec<Element<'a, Message>>) -> Element<'a, Message> {
    let spacing = theme::spacing();
    row::with_children(cells)
        .spacing(spacing.space_xxs)
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
}

fn pad_column<'a>(rows: Vec<Element<'a, Message>>) -> Element<'a, Message> {
    let spacing = theme::spacing();
    column::with_children(rows)
        .spacing(spacing.space_xxs)
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
}

impl App {
    /// Text-button mode switcher. Deliberately text, not icons: it
    /// must stay visible even when no usable icon theme is
    /// installed (B14).
    fn mode_switcher(&self) -> Element<'_, Message> {
        let spacing = theme::spacing();
        let mut modes = row![].spacing(spacing.space_xxs).width(Length::Fill);
        for (mode, label) in [
            (Mode::Standard, fl!("mode-standard")),
            (Mode::Scientific, fl!("mode-scientific")),
            (Mode::Programmer, fl!("mode-programmer")),
        ] {
            modes = modes.push(pill_button(
                label,
                self.state.mode == mode,
                Message::SetMode(mode),
            ));
        }
        modes.into()
    }

    fn display(&self) -> Element<'_, Message> {
        let spacing = theme::spacing();
        let expr = self.state.expression_display();
        // The engine stays libcosmic-free and reports "Error" for logs
        // and tests; the localized string is substituted at the view
        // boundary so translators see it.
        let result = if self.state.error.is_some() {
            fl!("error")
        } else {
            self.state.result_display()
        };

        let mut col = column![].spacing(spacing.space_xxxs).width(Length::Fill);

        // expression line + copy button
        let expr_row = row![
            text::caption(expr)
                .width(Length::Fill)
                .align_x(Horizontal::Right),
            button::icon(widget::icon::from_name("edit-copy-symbolic"))
                .on_press(Message::CopyResult)
                .description(fl!("copy")),
        ]
        .align_y(Vertical::Center);
        col = col.push(expr_row);

        col = col.push(
            text::title2(result)
                .size(34.)
                .width(Length::Fill)
                .align_x(Horizontal::Right),
        );

        if let Some((h, d, o, b)) = self.state.base_readout() {
            let readout = row![
                column![text::caption("HEX"), text::body(h)]
                    .align_x(Horizontal::Center)
                    .width(Length::Fill),
                column![text::caption("DEC"), text::body(d)]
                    .align_x(Horizontal::Center)
                    .width(Length::Fill),
                column![text::caption("OCT"), text::body(o)]
                    .align_x(Horizontal::Center)
                    .width(Length::Fill),
                column![text::caption("BIN"), text::body(b)]
                    .align_x(Horizontal::Center)
                    .width(Length::Fill),
            ];
            col = col.push(readout);

            // base selector
            let mut bases = row![].spacing(spacing.space_xxs).width(Length::Fill);
            for b_sel in [Base::Hex, Base::Dec, Base::Oct, Base::Bin] {
                bases = bases.push(pill_button(
                    b_sel.label(),
                    self.state.base == b_sel,
                    Message::SetBase(b_sel),
                ));
            }
            col = col.push(bases);
        }

        if self.state.mode == Mode::Scientific {
            let unit = match self.state.angle {
                AngleUnit::Deg => fl!("deg"),
                AngleUnit::Rad => fl!("rad"),
            };
            col = col.push(
                container(text::caption(unit))
                    .align_x(Horizontal::Right)
                    .width(Length::Fill),
            );
        }

        container(col)
            .width(Length::Fill)
            .padding([spacing.space_xxs, spacing.space_xs])
            .into()
    }

    fn standard_pad(&self) -> Element<'_, Message> {
        use BinOp::*;
        use KeyKind::*;
        pad_column(vec![
            grid_row(vec![
                key("%", Op, Some(Message::Percent)),
                key("CE", Action, Some(Message::ClearEntry)),
                key("C", Action, Some(Message::ClearAll)),
                key("Del", Action, Some(Message::Backspace)),
            ]),
            grid_row(vec![
                key("1/x", Func, Some(Message::Unary(UnaryOp::Recip))),
                key("x²", Func, Some(Message::Unary(UnaryOp::Square))),
                key("√", Func, Some(Message::Unary(UnaryOp::Sqrt))),
                key("÷", Op, Some(Message::Binary(Div))),
            ]),
            grid_row(vec![
                key("7", Digit, Some(Message::Digit(7))),
                key("8", Digit, Some(Message::Digit(8))),
                key("9", Digit, Some(Message::Digit(9))),
                key("×", Op, Some(Message::Binary(Mul))),
            ]),
            grid_row(vec![
                key("4", Digit, Some(Message::Digit(4))),
                key("5", Digit, Some(Message::Digit(5))),
                key("6", Digit, Some(Message::Digit(6))),
                key("−", Op, Some(Message::Binary(Sub))),
            ]),
            grid_row(vec![
                key("1", Digit, Some(Message::Digit(1))),
                key("2", Digit, Some(Message::Digit(2))),
                key("3", Digit, Some(Message::Digit(3))),
                key("+", Op, Some(Message::Binary(Add))),
            ]),
            grid_row(vec![
                key("±", Digit, Some(Message::ToggleSign)),
                key("0", Digit, Some(Message::Digit(0))),
                key(".", Digit, Some(Message::Dot)),
                key("=", Equals, Some(Message::Equals)),
            ]),
        ])
    }

    fn scientific_pad(&self) -> Element<'_, Message> {
        use BinOp::*;
        use KeyKind::*;
        use UnaryOp as U;
        let angle_label = match self.state.angle {
            AngleUnit::Deg => fl!("deg"),
            AngleUnit::Rad => fl!("rad"),
        };
        // 8 columns: left 4 = functions, right 4 = digit/operator block
        pad_column(vec![
            grid_row(vec![
                key("x²", Func, Some(Message::Unary(U::Square))),
                key("x³", Func, Some(Message::Unary(U::Cube))),
                key("xʸ", Func, Some(Message::Binary(Pow))),
                key("y√x", Func, Some(Message::Binary(YRoot))),
                key("CE", Action, Some(Message::ClearEntry)),
                key("C", Action, Some(Message::ClearAll)),
                key("Del", Action, Some(Message::Backspace)),
                key("÷", Op, Some(Message::Binary(Div))),
            ]),
            grid_row(vec![
                key("√", Func, Some(Message::Unary(U::Sqrt))),
                key("³√x", Func, Some(Message::Unary(U::Cbrt))),
                key("1/x", Func, Some(Message::Unary(U::Recip))),
                key("x!", Func, Some(Message::Unary(U::Fact))),
                key("7", Digit, Some(Message::Digit(7))),
                key("8", Digit, Some(Message::Digit(8))),
                key("9", Digit, Some(Message::Digit(9))),
                key("×", Op, Some(Message::Binary(Mul))),
            ]),
            grid_row(vec![
                key("sin", Func, Some(Message::Unary(U::Sin))),
                key("cos", Func, Some(Message::Unary(U::Cos))),
                key("tan", Func, Some(Message::Unary(U::Tan))),
                key("ln", Func, Some(Message::Unary(U::Ln))),
                key("4", Digit, Some(Message::Digit(4))),
                key("5", Digit, Some(Message::Digit(5))),
                key("6", Digit, Some(Message::Digit(6))),
                key("−", Op, Some(Message::Binary(Sub))),
            ]),
            grid_row(vec![
                key("sin⁻¹", Func, Some(Message::Unary(U::Asin))),
                key("cos⁻¹", Func, Some(Message::Unary(U::Acos))),
                key("tan⁻¹", Func, Some(Message::Unary(U::Atan))),
                key("log", Func, Some(Message::Unary(U::Log10))),
                key("1", Digit, Some(Message::Digit(1))),
                key("2", Digit, Some(Message::Digit(2))),
                key("3", Digit, Some(Message::Digit(3))),
                key("+", Op, Some(Message::Binary(Add))),
            ]),
            grid_row(vec![
                key("eˣ", Func, Some(Message::Unary(U::Exp))),
                key("10ˣ", Func, Some(Message::Unary(U::Pow10))),
                key("π", Func, Some(Message::Constant(Const::Pi))),
                key("e", Func, Some(Message::Constant(Const::E))),
                key("±", Digit, Some(Message::ToggleSign)),
                key("0", Digit, Some(Message::Digit(0))),
                key(".", Digit, Some(Message::Dot)),
                key("=", Equals, Some(Message::Equals)),
            ]),
            grid_row(vec![
                key(angle_label, Func, Some(Message::ToggleAngle)),
                key("|x|", Func, Some(Message::Unary(U::Abs))),
                key("EE", Func, Some(Message::Exp)),
                key("Ans", Func, Some(Message::Ans)),
                key("(", Op, Some(Message::LParen)),
                key(")", Op, Some(Message::RParen)),
                key("%", Op, Some(Message::Percent)),
                gap(),
            ]),
        ])
    }
}

impl App {
    fn programmer_pad(&self) -> Element<'_, Message> {
        use BinOp::*;
        use KeyKind::*;
        use UnaryOp as U;
        let hex = self.state.base == Base::Hex;
        let hex_key = |label: &'static str, d: u8| {
            key(
                label,
                Digit,
                if hex { Some(Message::Digit(d)) } else { None },
            )
        };
        // 6 columns; base selector lives in the display readout row
        pad_column(vec![
            grid_row(vec![
                hex_key("A", 10),
                hex_key("B", 11),
                hex_key("C", 12),
                hex_key("D", 13),
                hex_key("E", 14),
                hex_key("F", 15),
            ]),
            grid_row(vec![
                key("<<", Op, Some(Message::Binary(Shl))),
                key(">>", Op, Some(Message::Binary(Shr))),
                key("AND", Func, Some(Message::Binary(And))),
                key("OR", Func, Some(Message::Binary(Or))),
                key("XOR", Func, Some(Message::Binary(Xor))),
                key("NOT", Func, Some(Message::Unary(U::Not))),
            ]),
            grid_row(vec![
                key("(", Op, Some(Message::LParen)),
                key(")", Op, Some(Message::RParen)),
                key("%", Op, Some(Message::Percent)),
                key("CE", Action, Some(Message::ClearEntry)),
                key("C", Action, Some(Message::ClearAll)),
                key("Del", Action, Some(Message::Backspace)),
            ]),
            grid_row(vec![
                key("7", Digit, Some(Message::Digit(7))),
                key("8", Digit, Some(Message::Digit(8))),
                key("9", Digit, Some(Message::Digit(9))),
                key("±", Digit, Some(Message::ToggleSign)),
                key("÷", Op, Some(Message::Binary(Div))),
                key("×", Op, Some(Message::Binary(Mul))),
            ]),
            grid_row(vec![
                key("4", Digit, Some(Message::Digit(4))),
                key("5", Digit, Some(Message::Digit(5))),
                key("6", Digit, Some(Message::Digit(6))),
                key(".", Digit, None),
                key("−", Op, Some(Message::Binary(Sub))),
                key("+", Op, Some(Message::Binary(Add))),
            ]),
            grid_row(vec![
                key("1", Digit, Some(Message::Digit(1))),
                key("2", Digit, Some(Message::Digit(2))),
                key("3", Digit, Some(Message::Digit(3))),
                key("0", Digit, Some(Message::Digit(0))),
                gap(),
                key("=", Equals, Some(Message::Equals)),
            ]),
        ])
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use keyboard::key::{Code, Physical};

    fn phys() -> Physical {
        Physical::Code(Code::KeyH)
    }

    fn plain(key: keyboard::Key, mode: Mode, base: Base) -> Option<Message> {
        key_message(&key, phys(), keyboard::Modifiers::empty(), mode, base)
    }

    fn char_key(c: &str) -> keyboard::Key {
        keyboard::Key::Character(c.into())
    }

    #[test]
    fn keyboard_h_toggles_history() {
        for c in ["h", "H"] {
            let m = plain(char_key(c), Mode::Standard, Base::Dec);
            assert!(matches!(m, Some(Message::ToggleContext)), "{c:?} -> {m:?}");
            // No conflict with hex entry: `h` is not a hex digit.
            let m = plain(char_key(c), Mode::Programmer, Base::Hex);
            assert!(
                matches!(m, Some(Message::ToggleContext)),
                "hex {c:?} -> {m:?}"
            );
        }
    }

    #[test]
    fn keyboard_hex_digits_mode_scoped() {
        let m = plain(char_key("a"), Mode::Programmer, Base::Hex);
        assert!(matches!(m, Some(Message::Digit(10))), "{m:?}");
        // Outside programmer-hex, `a` types nothing.
        assert!(plain(char_key("a"), Mode::Standard, Base::Dec).is_none());
        assert!(plain(char_key("a"), Mode::Programmer, Base::Dec).is_none());
    }

    #[test]
    fn keyboard_ctrl_insert_copies() {
        let m = key_message(
            &keyboard::Key::Named(keyboard::key::Named::Insert),
            phys(),
            keyboard::Modifiers::CTRL,
            Mode::Standard,
            Base::Dec,
        );
        assert!(matches!(m, Some(Message::CopyResult)), "{m:?}");
    }

    #[test]
    fn mode_window_sizes_fit_each_pad() {
        // Regression test for B15: one width cannot serve 4/8/6
        // column pads, so each mode pins its own size. Widths must
        // order by column count (scientific 8 > programmer 6 >
        // standard 4) or labels clip / keys bloat.
        let std = mode_window_size(Mode::Standard);
        let sci = mode_window_size(Mode::Scientific);
        let prog = mode_window_size(Mode::Programmer);
        assert_eq!((std.width, std.height), (400., 580.));
        assert_eq!((sci.width, sci.height), (640., 600.));
        assert_eq!((prog.width, prog.height), (560., 660.));
        assert!(sci.width > prog.width && prog.width > std.width);
    }

    #[test]
    fn reduce_set_mode_switches_pads() {
        let mut state = CalcState::new();
        reduce(&mut state, &Message::SetMode(Mode::Scientific));
        assert_eq!(state.mode, Mode::Scientific);
        reduce(&mut state, &Message::SetMode(Mode::Standard));
        assert_eq!(state.mode, Mode::Standard);
    }

    fn icon_fixture(themes: &[&str]) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "gosh-calc-icon-test-{}-{}",
            std::process::id(),
            themes.join("+").replace('/', "_")
        ));
        for theme in themes {
            let theme_dir = dir.join("icons").join(theme);
            std::fs::create_dir_all(&theme_dir).unwrap();
            std::fs::write(theme_dir.join("index.theme"), "[Icon Theme]\n").unwrap();
        }
        dir.join("icons")
    }

    #[test]
    fn icon_theme_keeps_installed_configured_theme() {
        let icons = icon_fixture(&["Pop", "Adwaita"]);
        let dirs = vec![icons.clone()];
        assert_eq!(resolve_icon_theme_in("Pop", &dirs), None);
        std::fs::remove_dir_all(icons.parent().unwrap()).ok();
    }

    #[test]
    fn icon_theme_falls_back_when_configured_missing() {
        let icons = icon_fixture(&["Adwaita", "hicolor"]);
        let dirs = vec![icons.clone()];
        // "Pop" is configured but not installed; Cosmic is absent
        // too, so Adwaita wins over hicolor by preference order.
        assert_eq!(
            resolve_icon_theme_in("Pop", &dirs),
            Some("Adwaita".to_string())
        );
        std::fs::remove_dir_all(icons.parent().unwrap()).ok();
    }

    #[test]
    fn icon_theme_prefers_cosmic_fallback() {
        let icons = icon_fixture(&["Cosmic", "Adwaita", "hicolor"]);
        let dirs = vec![icons.clone()];
        assert_eq!(
            resolve_icon_theme_in("Pop", &dirs),
            Some("Cosmic".to_string())
        );
        std::fs::remove_dir_all(icons.parent().unwrap()).ok();
    }

    #[test]
    fn icon_theme_rejects_unsafe_names() {
        let icons = icon_fixture(&["Adwaita"]);
        let dirs = vec![icons.clone()];
        for bad in ["", "../Adwaita", "a/b", "a\\b", "..", &"x".repeat(65)] {
            assert_eq!(
                resolve_icon_theme_in(bad, &dirs),
                Some("Adwaita".to_string()),
                "{bad:?} must fall back, not probe outside the icon dirs"
            );
        }
        std::fs::remove_dir_all(icons.parent().unwrap()).ok();
    }

    #[test]
    fn icon_theme_no_fallback_when_nothing_installed() {
        let icons = icon_fixture(&[]);
        let dirs = vec![icons.clone()];
        assert_eq!(resolve_icon_theme_in("Pop", &dirs), None);
        std::fs::remove_dir_all(icons.parent().unwrap()).ok();
    }

    #[test]
    fn keyboard_caret_is_mode_scoped() {
        let m = plain(char_key("^"), Mode::Scientific, Base::Dec);
        assert!(matches!(m, Some(Message::Binary(BinOp::Pow))), "{m:?}");
        let m = plain(char_key("^"), Mode::Programmer, Base::Dec);
        assert!(matches!(m, Some(Message::Binary(BinOp::Xor))), "{m:?}");
    }

    #[test]
    fn save_gating_pins_persisted_state_policy() {
        // Persisted state = mode, angle, history: only these mutate it.
        for m in [
            Message::Equals,
            Message::ClearHistory,
            Message::ToggleAngle,
            Message::SetMode(Mode::Scientific),
        ] {
            assert!(needs_save(&m), "{m:?} must save");
        }
        for m in [
            Message::Digit(1),
            Message::Dot,
            Message::Backspace,
            Message::ClearEntry,
            Message::ClearAll,
            Message::Recall(0),
            Message::CopyResult,
            Message::ToggleContext,
            Message::SetBase(Base::Hex),
        ] {
            assert!(!needs_save(&m), "{m:?} must not save");
        }
    }
}
