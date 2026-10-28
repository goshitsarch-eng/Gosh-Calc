# Security

The calculator makes no network requests and runs no external commands or
dynamic code: the project contains no use of `OS.execute`, `HTTPRequest`,
sockets, `Expression` or similar (grep-able). History is rendered as text.

* Settings and legacy-import reads are bounded to 1 MiB; history to 100 records
  and 256 bytes per field; expression tokens and nesting are bounded; integer
  arithmetic is overflow-checked.
* Saving writes a unique temporary file in the same directory and renames it
  over the target. This code does not call `fsync` (unlike 0.2): data is flushed but
  not forced to disk before the rename; a power loss at the wrong instant could
  lose the latest save (never corrupt the previous file's content in place).
* Corrupt settings and legacy imports retain backups; future schemas and
  oversized files disable saving instead of overwriting.
* The only dependencies are Godot Engine (a stock official export template, MIT)
  and two bundled fonts. Release builds use the engine's release templates
  (no debugger or editor). The stock template contains networking and scripting
  engine code that this application never calls. Track Godot security releases
  and rebuild when they ship.
* Flatpak permissions are limited to display sockets, IPC and graphics.
* No packages are signed or notarized in this series.

Report vulnerabilities privately via the repository's security advisory page.
