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
use cosmic::widget::{self, button, column, container, nav_bar, row, scrollable, text};
use cosmic::{executor, theme, Element};

use engine::{AngleUnit, Base, BinOp, CalcState, Const, Mode, UnaryOp};

pub const APP_ID: &str = "dev.goshapps.calc";

fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("warn")).init();
    i18n::init();
    let settings = Settings::default().size(Size::new(430., 560.));
    cosmic::app::run::<App>(settings, ())?;
    Ok(())
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
            "e" | "E" if mode == Mode::Programmer && base == Base::Hex => {
                Some(Message::Digit(14))
            }
            "a" | "A" | "b" | "B" | "c" | "C" | "d" | "D" | "f" | "F"
                if mode == Mode::Programmer && base == Base::Hex =>
            {
                let d = c.to_ascii_lowercase().chars().next().unwrap() as u8 - b'a' + 10;
                Some(Message::Digit(d))
            }
            _ => None,
        },
        _ => None,
    }
}

pub struct App {
    core: Core,
    nav_model: nav_bar::Model,
    state: CalcState,
    store: Option<Config>,
}

impl App {
    fn active_mode(&self) -> Mode {
        self.nav_model
            .active_data::<Mode>()
            .copied()
            .unwrap_or(Mode::Standard)
    }

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
        let mut nav_model = nav_bar::Model::default();
        nav_model
            .insert()
            .text(fl!("mode-standard"))
            .data::<Mode>(Mode::Standard);
        nav_model
            .insert()
            .text(fl!("mode-scientific"))
            .data::<Mode>(Mode::Scientific);
        nav_model
            .insert()
            .text(fl!("mode-programmer"))
            .data::<Mode>(Mode::Programmer);

        let store = config::store();
        let mut state = CalcState::new();
        if let Some(store) = &store {
            config::load(store, &mut state);
        }

        // activate nav item matching the persisted mode
        let mode = state.mode;
        let pos = match mode {
            Mode::Standard => 0,
            Mode::Scientific => 1,
            Mode::Programmer => 2,
        };
        nav_model.activate_position(pos);

        let mut app = Self {
            core,
            nav_model,
            state,
            store,
        };
        app.set_header_title(fl!("app-title"));
        if let Some(id) = app.core.main_window_id() {
            let t = app.set_window_title(fl!("app-title"), id);
            return (app, t);
        }
        (app, Task::none())
    }

    fn nav_model(&self) -> Option<&nav_bar::Model> {
        Some(&self.nav_model)
    }

    fn on_nav_select(&mut self, id: nav_bar::Id) -> Task<Self::Message> {
        self.nav_model.activate(id);
        self.state.set_mode(self.active_mode());
        self.save();
        Task::none()
    }

    fn header_end(&self) -> Vec<Element<'_, Self::Message>> {
        vec![widget::tooltip(
            button::icon(widget::icon::from_name("view-sort-ascending-symbolic"))
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
        let mut list = column![].spacing(spacing.space_xxs).padding(spacing.space_s);
        if self.state.history.is_empty() {
            list = list.push(text::body(fl!("history-empty")));
        }
        for (i, h) in self.state.history.iter().enumerate() {
            list = list.push(
                button::custom(
                    column![
                        text::body(&h.expr),
                        text::title4(&h.result),
                    ]
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
                        .on_press(Message::ClearHistory),
                ),
        )
    }

    fn update(&mut self, message: Self::Message) -> Task<Self::Message> {
        match message {
            Message::CopyResult => {
                return cosmic::iced::clipboard::write(self.state.result_display());
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
                    if let Message::CopyResult = m {
                        return cosmic::iced::clipboard::write(self.state.result_display());
                    }
                    if let Message::ToggleContext = m {
                        let show = !self.core.window.show_context;
                        self.core_mut().set_show_context(show);
                        return Task::none();
                    }
                    reduce(&mut self.state, &m);
                    self.save();
                }
            }
            m => {
                reduce(&mut self.state, &m);
                self.save();
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

        root = root.push(self.display());
        root = root.push(match self.state.mode {
            Mode::Standard => self.standard_pad(),
            Mode::Scientific => self.scientific_pad(),
            Mode::Programmer => self.programmer_pad(),
        });
        root.into()
    }
}

// ---------- view helpers ----------

enum KeyKind {
    Digit,
    Op,
    Action,
    Equals,
}

fn key<'a>(label: impl Into<String>, kind: KeyKind, msg: Option<Message>) -> Element<'a, Message> {
    let content = container(text::title4(label.into()))
        .align_x(Horizontal::Center)
        .align_y(Vertical::Center)
        .width(Length::Fill)
        .height(Length::Fill);
    button::custom(content)
        .class(match kind {
            KeyKind::Digit => theme::Button::Standard,
            KeyKind::Op => theme::Button::Text,
            KeyKind::Action => theme::Button::Standard,
            KeyKind::Equals => theme::Button::Suggested,
        })
        .width(Length::Fill)
        .height(Length::Fill)
        .on_press_maybe(msg)
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
    fn display(&self) -> Element<'_, Message> {
        let spacing = theme::spacing();
        let expr = self.state.expression_display();
        let result = self.state.result_display();

        let mut col = column![].spacing(spacing.space_xxxs).width(Length::Fill);

        // expression line + copy button
        let expr_row = row![
            text::caption(expr).width(Length::Fill).align_x(Horizontal::Right),
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
                column![text::caption("HEX"), text::body(h)].align_x(Horizontal::Center).width(Length::Fill),
                column![text::caption("DEC"), text::body(d)].align_x(Horizontal::Center).width(Length::Fill),
                column![text::caption("OCT"), text::body(o)].align_x(Horizontal::Center).width(Length::Fill),
                column![text::caption("BIN"), text::body(b)].align_x(Horizontal::Center).width(Length::Fill),
            ];
            col = col.push(readout);

            // base selector
            let mut bases = row![].spacing(spacing.space_xxs);
            for b_sel in [Base::Hex, Base::Dec, Base::Oct, Base::Bin] {
                bases = bases.push(key(
                    b_sel.label(),
                    if self.state.base == b_sel {
                        KeyKind::Equals
                    } else {
                        KeyKind::Op
                    },
                    Some(Message::SetBase(b_sel)),
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
                key("1/x", Op, Some(Message::Unary(UnaryOp::Recip))),
                key("x²", Op, Some(Message::Unary(UnaryOp::Square))),
                key("√", Op, Some(Message::Unary(UnaryOp::Sqrt))),
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
                key("x²", Op, Some(Message::Unary(U::Square))),
                key("x³", Op, Some(Message::Unary(U::Cube))),
                key("xʸ", Op, Some(Message::Binary(Pow))),
                key("y√x", Op, Some(Message::Binary(YRoot))),
                key("CE", Action, Some(Message::ClearEntry)),
                key("C", Action, Some(Message::ClearAll)),
                key("Del", Action, Some(Message::Backspace)),
                key("÷", Op, Some(Message::Binary(Div))),
            ]),
            grid_row(vec![
                key("√", Op, Some(Message::Unary(U::Sqrt))),
                key("∛", Op, Some(Message::Unary(U::Cbrt))),
                key("1/x", Op, Some(Message::Unary(U::Recip))),
                key("x!", Op, Some(Message::Unary(U::Fact))),
                key("7", Digit, Some(Message::Digit(7))),
                key("8", Digit, Some(Message::Digit(8))),
                key("9", Digit, Some(Message::Digit(9))),
                key("×", Op, Some(Message::Binary(Mul))),
            ]),
            grid_row(vec![
                key("sin", Op, Some(Message::Unary(U::Sin))),
                key("cos", Op, Some(Message::Unary(U::Cos))),
                key("tan", Op, Some(Message::Unary(U::Tan))),
                key("ln", Op, Some(Message::Unary(U::Ln))),
                key("4", Digit, Some(Message::Digit(4))),
                key("5", Digit, Some(Message::Digit(5))),
                key("6", Digit, Some(Message::Digit(6))),
                key("−", Op, Some(Message::Binary(Sub))),
            ]),
            grid_row(vec![
                key("sin⁻¹", Op, Some(Message::Unary(U::Asin))),
                key("cos⁻¹", Op, Some(Message::Unary(U::Acos))),
                key("tan⁻¹", Op, Some(Message::Unary(U::Atan))),
                key("log", Op, Some(Message::Unary(U::Log10))),
                key("1", Digit, Some(Message::Digit(1))),
                key("2", Digit, Some(Message::Digit(2))),
                key("3", Digit, Some(Message::Digit(3))),
                key("+", Op, Some(Message::Binary(Add))),
            ]),
            grid_row(vec![
                key("eˣ", Op, Some(Message::Unary(U::Exp))),
                key("10ˣ", Op, Some(Message::Unary(U::Pow10))),
                key("π", Op, Some(Message::Constant(Const::Pi))),
                key("e", Op, Some(Message::Constant(Const::E))),
                key("±", Digit, Some(Message::ToggleSign)),
                key("0", Digit, Some(Message::Digit(0))),
                key(".", Digit, Some(Message::Dot)),
                key("=", Equals, Some(Message::Equals)),
            ]),
            grid_row(vec![
                key(angle_label, Action, Some(Message::ToggleAngle)),
                key("|x|", Op, Some(Message::Unary(U::Abs))),
                key("EE", Op, Some(Message::Exp)),
                key("Ans", Op, Some(Message::Ans)),
                key("(", Op, Some(Message::LParen)),
                key(")", Op, Some(Message::RParen)),
                key("%", Op, Some(Message::Percent)),
                gap(),
            ]),
        ])
    }

    fn programmer_pad(&self) -> Element<'_, Message> {
        use BinOp::*;
        use KeyKind::*;
        use UnaryOp as U;
        let hex = self.state.base == Base::Hex;
        let hex_key = |label: &'static str, d: u8| {
            key(label, Digit, if hex { Some(Message::Digit(d)) } else { None })
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
                key("AND", Op, Some(Message::Binary(And))),
                key("OR", Op, Some(Message::Binary(Or))),
                key("XOR", Op, Some(Message::Binary(Xor))),
                key("NOT", Op, Some(Message::Unary(U::Not))),
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
