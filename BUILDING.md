# Building Gosh Calc

Use stable Rust, Python 3.11+ for packaging, and the committed Cargo.lock.
Commands run from the checkout root. Dioxus 0.7.10 is used as a Cargo library;
the Dioxus CLI is optional and is not needed for these builds.

Linux instructions below were exercised on Debian 13 with Rust 1.99.0.
Windows/macOS/Flatpak instructions and CI jobs are prepared but unexecuted in
this cloud environment. Their actual status is in PLATFORM_SUPPORT.md.

## Portable core

```sh
cargo test --locked --no-default-features
python3 scripts/verify.py --core
```

No GUI libraries or display are required. The desktop binary is disabled when
the desktop feature is disabled; this command does not verify the UI.

## Linux native

Debian 13 / Ubuntu 24.04 prerequisites:

```sh
sudo apt-get update
sudo apt-get install --no-install-recommends build-essential pkg-config \
  libwebkit2gtk-4.1-dev libgtk-3-dev libxdo-dev \
  libayatana-appindicator3-dev librsvg2-dev
cargo build --locked
cargo run --locked
```

Fedora equivalents include `gcc`, `gcc-c++`, `pkgconf-pkg-config`,
`webkit2gtk4.1-devel`, `gtk3-devel`, `libappindicator-gtk3-devel`, `libxdo-devel`
and `librsvg2-devel`; package names may vary by release and this distribution
has not been tested here. GTK hosts the system WebView; application components
are Dioxus rather than GTK widgets.

```sh
python3 scripts/verify.py
cargo build --locked --features ui-test
python3 scripts/smoke.py target/debug/gosh-calc
cargo build --release --locked
python3 scripts/package.py --arch x86_64
python3 scripts/verify_release.py --dir dist --version 0.2.0-alpha.1
```

For display-free X11 QA, also install `xvfb dbus-x11`, then run
`xvfb-run -a dbus-run-session -- python3 scripts/smoke.py target/debug/gosh-calc`.
WebKit's sandbox stays enabled. A container needs supported user namespaces;
do not disable the WebKit sandbox to hide a container setup problem.
A Wayland compositor and its socket are needed for Wayland testing.

The archive contains the executable and desktop assets, not WebKit/GTK system
libraries. Build on your oldest supported distribution for a native release;
a Debian 13 build is not evidence of compatibility with older glibc versions.
Flatpak supplies a controlled runtime instead.

## Windows x86_64 MSVC

Install stable Rust through rustup, Visual Studio 2022 Build Tools with Desktop
development with C++ and a Windows SDK, Python 3.11+, and Evergreen WebView2
Runtime. Use an MSVC developer shell when necessary:

```powershell
rustup default stable-x86_64-pc-windows-msvc
cargo build --locked
cargo run --locked
python scripts/verify.py
cargo build --locked --features ui-test
python scripts/smoke.py target/debug/gosh-calc.exe
```

For an MSI and portable archive install .NET SDK and WiX 5.0.2:

```powershell
dotnet tool install --global wix --version 5.0.2
cargo build --release --locked
python scripts/package.py --arch x86_64
python scripts/verify_release.py --dir dist --version 0.2.0-alpha.1
```

The installer is per user under Local AppData, has a fixed UpgradeCode, a Start
Menu entry, optional desktop shortcut, major upgrade detection and uninstall.
It does not bundle WebView2. Native CI builds a predecessor MSI fixture, installs
it, upgrades to the current MSI and uninstalls. This fixture tests installer
mechanics; it is not a historical Windows version of the Linux-only app.
MSI numeric builds reserve 100 slots per SemVer patch: alpha.N adds N, beta.N
adds 30+N, rc.N adds 60+N, and stable adds 99 (N is 1–29). Thus 0.2.0-alpha.1
is MSI 0.2.1 and 0.2.0 stable is MSI 0.2.99, preserving upgrade order.
Settings are retained under `%APPDATA%\dev.goshapps.calc`.
Release binaries have Windows version/icon resources and no extra console window.
Windows ARM64 is not part of the required release set yet.

## macOS Apple Silicon and Intel

Install Xcode Command Line Tools, stable Rust and Python 3.11+:

```sh
xcode-select --install
cargo build --locked
cargo run --locked
python3 scripts/verify.py
cargo build --locked --features ui-test
python3 scripts/smoke.py target/debug/gosh-calc
cargo build --release --locked
python3 scripts/package.py --arch aarch64  # x86_64 on an Intel host
python3 scripts/verify_release.py --dir dist --version 0.2.0-alpha.1
```

Build natively on each architecture. Packaging creates `Gosh Calc.app` with
Info.plist, identifier, ICNS icon, Retina support and an ad hoc signature, then
uses ditto to preserve executable permissions in the zip. The declared minimum
macOS version is 11.0, but release CI runs on newer systems; older-OS deployment
compatibility still needs an actual runtime test.

To sign with credentials already installed in Keychain, set
`MACOS_SIGNING_IDENTITY` to the Developer ID identity. Set `MACOS_NOTARY_PROFILE`
to an existing `notarytool store-credentials` profile for submission, waiting,
stapling and repackaging. Without these variables, local build/testing requires
no certificate. Do not store signing credentials in the repository.

Separate Intel and Apple Silicon bundles avoid pretending an untested universal
binary works. A universal build is feasible with `lipo -create` on the two native
executables, but would need both builds and a fresh signature/runtime QA.

## Flatpak

Install `flatpak flatpak-builder elfutils librsvg2-common` and enable user
namespaces. This manifest targets GNOME 49 for GTK3/WebKitGTK 4.1:

```sh
flatpak remote-add --user --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user -y flathub org.gnome.Platform//49 org.gnome.Sdk//49 \
  org.freedesktop.Sdk.Extension.rust-stable//25.08
python3 flatpak/flatpak-cargo-generator.py Cargo.lock -o flatpak/cargo-sources.json
python3 scripts/flatpak.py --out dist
flatpak install --user -y dist/*.flatpak
flatpak run dev.goshapps.calc
```

Source downloads are checked against Cargo.lock hashes. The build is offline
and includes the documented GLib safety backport under vendor/. Regenerate the
source list whenever Cargo.lock changes. The SDK itself and in-sandbox WebKit
availability have not been verified here because dl.flathub.org is blocked.
Manifest parsing and source-list consistency checks passed.

Test the actual sandbox with a separate QA bundle, never a published binary:

```sh
python3 scripts/flatpak.py --ui-test --out qa-dist
flatpak install --user -y --reinstall qa-dist/*.flatpak
python3 scripts/smoke.py --flatpak
```

This grants only the test's temporary output directory for result collection.
Production finish-args allow Wayland, fallback X11, IPC (X11 shared memory) and
DRI (WebView rendering). There is no host filesystem, network or device-all
grant. No file workflow requires a portal dialog. The app retains its original
Flatpak ID, so existing app-scoped XDG RON data can be imported in place.

## Troubleshooting

- Missing `webkit2gtk-4.1.pc`: install the 4.1 development package, not 4.0.
- No WebView2: install Microsoft's Evergreen Runtime before launching Windows.
- Native library/helper lookup in an extracted non-root Linux sysroot: the
  cloud setup uses a read-only mount of the verified libraries at their expected
  paths. An ordinary system package installation needs no such wrapper.
- Persistence failure: read the visible notice; logs do not contain history.
  `RUST_LOG=gosh_calc=debug` enables application diagnostics.
- A future settings schema disables saving to protect existing data. Use a
  separate `GOSH_CALC_CONFIG_DIR` for an older executable rather than deleting it.
