# Building

Everything needs only **Godot 4.7.2 (standard build)**; no other SDK. Put the
`godot` binary on `PATH` or set `GODOT=/path/to/godot`.

```sh
godot --path .                       # run from source
scripts/test.sh                      # all tests (UI checks need a display or xvfb-run)
scripts/test.sh --core               # display-free tests only
```

Linux test dependencies: `xvfb`, Mesa (`libgl1-mesa-dri`), `libxcursor1`,
`libxinerama1`, `libxi6`, `libxrandr2`. UI checks use software GL.

## Release packages

Install the matching **export templates** (Editor → Manage Export Templates, or
unpack `Godot_v4.7.2-stable_export_templates.tpz` into
`~/.local/share/godot/export_templates/4.7.2.stable/`), then:

```sh
scripts/export.sh        # writes dist/*.tar.gz, *.zip and SHA256SUMS
```

The presets are in `export_presets.cfg` (Linux x86_64/arm64, Windows x86_64,
macOS universal). `tests/`, `docs/`, packaging and metadata files are excluded
from the shipped pack. All four exports were produced on Linux; only the Linux
x86_64 build has been run.

* **Windows:** the executable has its icon/version resources embedded by Godot.
  There is no installer or code signing.
* **macOS:** the preset produces an unsigned, un-notarized `.app` in a zip. To
  sign/notarize, set the `codesign/*` and `notarization/*` options in the preset
  (an Apple Developer ID is required) and export on or for macOS.
* **Flatpak (local bundle, not yet built):**
  ```sh
  scripts/export.sh   # or just the Linux x86_64 preset
  flatpak-builder --user --install --force-clean build-dir flatpak/dev.goshapps.calc.yml
  flatpak run dev.goshapps.calc
  ```
  It needs `org.freedesktop.Platform//25.08` and the SDK from Flathub and grants
  only display sockets, IPC and DRI.

## Environment variables

`GOSH_CALC_CONFIG_DIR` (isolated settings directory), `GOSH_CALC_SCALE` (force
UI scale, e.g. `2`).
