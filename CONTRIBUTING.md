# Contributing

Read ARCHITECTURE.md for the layer boundaries and BUILDING.md for setup.

```sh
scripts/test.sh          # must pass; UI checks are not optional for UI changes
```

Rules of thumb:

* Domain math lives in `core/engine.gd`, availability and actions in
  `core/commands.gd`/`core/app_state.gd`, persistence in `core/store.gd`. All UI
  entry points go through `run(command)` in `ui/main.gd`; never duplicate the reducer.
* Behavior is pinned by `tests/golden`. A deliberate behavior change must update
  the corpus knowingly (and say so); an unintended diff is a regression.
* Use checked integer math, bounded parsing, visible errors and backups. Never
  use Godot's `to_float`/`str(float)` for calculator values: use `GcNum`.
* No mutable data beside the executable; do not log calculation history; no
  network or external commands (see SECURITY.md).
* New `class_name` scripts need `godot --headless --path . --import` once before
  tests can see them. Commit the `.uid` and `.import` files.

Manual QA before a stable release: every visible control and menu, real
shortcuts/clipboard, error recovery, all bases, history recall/clear, settings
persistence after close/reopen, corrupted settings, minimum and maximized
windows, high DPI, keyboard focus, screen readers, all theme modes (including
live OS dark-mode changes), and each platform package. Record evidence rather
than inferring support from a successful export.

Versions `0.3.0-alpha.N` are the Godot rewrite preview series. A `v*` tag runs
`.github/workflows/release.yml`, which re-runs the tests and packages.
