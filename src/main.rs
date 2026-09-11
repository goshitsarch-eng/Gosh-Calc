// Copyright (c) 2026 goshitsarch-eng
// SPDX-License-Identifier: MIT

use cosmic::app::{Core, Settings, Task};
use cosmic::prelude::*;
use cosmic::{executor, Element};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::init();
    cosmic::app::run::<App>(Settings::default(), ())?;
    Ok(())
}

#[derive(Clone, Debug)]
enum Message {}

struct App {
    core: Core,
}

impl cosmic::Application for App {
    type Executor = executor::Default;
    type Flags = ();
    type Message = Message;
    const APP_ID: &'static str = "dev.goshapps.calc";

    fn core(&self) -> &Core {
        &self.core
    }

    fn core_mut(&mut self) -> &mut Core {
        &mut self.core
    }

    fn init(core: Core, _flags: Self::Flags) -> (Self, Task<Self::Message>) {
        (Self { core }, Task::none())
    }

    fn view(&self) -> Element<'_, Self::Message> {
        cosmic::widget::text::title1("Gosh Calc").into()
    }
}
