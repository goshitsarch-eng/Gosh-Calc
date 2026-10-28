class_name GcApp
extends RefCounted
## Application identity and the platform-specific keyboard policy.

const APP_ID := "dev.goshapps.calc"
const APP_NAME := "Gosh Calc"


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


static func is_macos() -> bool:
	return OS.get_name() == "macOS"


static func history_shortcut_label() -> String:
	return "h / ⌘ Shift H" if is_macos() else "h / Ctrl H"


## The key name the shared keyboard map expects (like DOM KeyboardEvent.key):
## the modified logical character, or a name for non-text keys. "" when the
## event carries no usable key.
static func key_name(event: InputEventKey) -> String:
	var code: int = event.keycode if event.keycode != 0 else event.physical_keycode
	match code:
		KEY_ENTER, KEY_KP_ENTER:
			return "Enter"
		KEY_ESCAPE:
			return "Escape"
		KEY_DELETE:
			return "Delete"
		KEY_BACKSPACE:
			return "Backspace"
		KEY_INSERT:
			return "Insert"
		KEY_F1:
			return "F1"
	var unicode: int = event.unicode
	if unicode >= 32 and unicode != 127:
		return char(unicode)
	# Ctrl/Cmd combinations carry no text; fall back to the unmodified key
	if code >= KEY_A and code <= KEY_Z:
		return char(code + 32)
	if code >= KEY_0 and code <= KEY_9:
		return char(code)
	if code == KEY_COMMA:
		return ","
	return ""


## Maps a physical keystroke to a command, applying the platform policy:
## Command is the primary modifier on macOS and Ctrl elsewhere, Ctrl+Insert
## copies everywhere, and Command+H stays macOS's native Hide.
static func keyboard_command(key: String, control: bool, meta: bool, alt: bool, shift: bool,
		mode: int, base: int) -> Variant:
	var mac := is_macos()
	if mac and meta and not shift and key.to_lower() == "h":
		return null
	var primary := (meta if mac else control) or (control and key == "Insert")
	return GcCommands.keyboard(key, primary, alt, mode, base)


## Command-line handling for arguments after `--` (Godot keeps `--help` and
## `--version` for itself, so `gosh-calc -- --version` reaches the app).
## Returns {"handled": bool, "output": String, "exit_code": int}.
static func cli(args: PackedStringArray) -> Dictionary:
	if args.is_empty() or not args[0].begins_with("-"):
		return {"handled": false, "output": "", "exit_code": 0} # positional arguments are ignored
	match args[0]:
		"--version", "-V":
			return {"handled": true, "output": "%s %s" % [APP_NAME, version()], "exit_code": 0}
		"--help", "-h":
			return {
				"handled": true, "exit_code": 0,
				"output": "%s\n\nUsage: gosh-calc -- [--help | --version]\n\nA desktop calculator with standard, scientific and programmer modes." % APP_NAME,
			}
	return {"handled": true, "output": "Unknown option: %s. Try --help." % args[0], "exit_code": 1}
