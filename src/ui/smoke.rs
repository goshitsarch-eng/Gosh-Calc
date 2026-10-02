//! Only compiled with `ui-test`; runs in the actual platform desktop WebView.
use dioxus::prelude::*;
pub fn install() {
    use_future(|| async {
        if std::env::var_os("GOSH_CALC_UI_TEST").is_none() {
            return;
        }
        tokio::time::sleep(std::time::Duration::from_secs(2)).await;
        let mut evaluation = document::eval(include_str!("../../tests/desktop.js"));
        let result = evaluation.recv::<serde_json::Value>().await;
        let _ = evaluation.send(true);
        let status = match result {
            Ok(value) => {
                println!("DESKTOP_TEST_RESULT={value}");
                if value["passed"] == true {
                    0
                } else {
                    1
                }
            }
            Err(error) => {
                eprintln!("Desktop test evaluation failed: {error}");
                1
            }
        };
        if let Some(path) = std::env::var_os("GOSH_CALC_UI_TEST_RESULT") {
            if let Err(error) = std::fs::write(path, status.to_string()) {
                eprintln!("Cannot write desktop test result: {error}");
            }
        }
        // A normal window close lets the settings worker flush; the runner
        // inspects the explicitly reported test outcome as well as exit status.
        dioxus_desktop::window().close();
    });
}
