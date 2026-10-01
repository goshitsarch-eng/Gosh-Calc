//! Text clipboard through native APIs; Linux uses the existing WebKit host.
use std::cell::RefCell;

#[cfg(target_os = "linux")]
type NativeClipboard = gtk::Clipboard;
#[cfg(not(target_os = "linux"))]
type NativeClipboard = arboard::Clipboard;

#[derive(Default)]
pub struct Clipboard(RefCell<Option<NativeClipboard>>);
impl Clipboard {
    pub fn copy(&self, text: String) -> Result<(), String> {
        let mut clipboard = self.0.borrow_mut();
        #[cfg(target_os = "linux")]
        {
            if clipboard.is_none() {
                let display = gtk::gdk::Display::default()
                    .ok_or_else(|| "No native display is available.".to_string())?;
                *clipboard = gtk::Clipboard::default(&display);
            }
            let clipboard = clipboard
                .as_ref()
                .ok_or_else(|| "The native clipboard is unavailable.".to_string())?;
            clipboard.set_text(&text);
            Ok(())
        }
        #[cfg(not(target_os = "linux"))]
        {
            if clipboard.is_none() {
                *clipboard = Some(arboard::Clipboard::new().map_err(|e| e.to_string())?);
            }
            clipboard
                .as_mut()
                .ok_or_else(|| "The native clipboard is unavailable.".to_string())?
                .set_text(text)
                .map_err(|e| e.to_string())
        }
    }
}
