# Clean Up My Machine

A small macOS app with one job: find storage you can get back, show you the
total, and delete it only after you confirm. Win95 chrome, because why not.

## Build

```bash
./build.sh
open "dist/Clean Up My Machine.app"
```

Produces an ad-hoc signed `.app` in `dist/`. Requires Swift 5.9+ (Xcode 15+).

## How it works

Four screens: **idle → review → cleaning → results**, in a fixed-size window with
native macOS window controls.

On launch the app scans quietly in the background, so the total is already known by
the time you look at it. It also installs a **menu bar item** listing everything
recoverable — click any row (or *Open Clean Up My Machine*) to bring up the window.
Closing the window leaves the app running in the menu bar; *Quit* exits.

Nothing is deleted during the scan. The review screen lists every candidate with
its size and a checkbox, split into two groups:

- **Caches** — regenerate on their own. Checked by default.
- **Build output** — rebuildable, but costs you compile time. Unchecked by default,
  so you opt in deliberately.

Anything the app *can't* remove itself (SIP-protected, needs sudo, or blocked by
TCC) is never silently skipped — it appears on the results screen with the exact
shell command and a Copy button.

## What it looks for

| Group | Items |
|---|---|
| Caches | npm/npx, Gradle, Cargo registry, yarn/pnpm/bun, pip, CocoaPods, Playwright, Homebrew downloads, VS Code caches, Xcode DerivedData, app updater (ShipIt) leftovers, orphaned simulators, Trash |
| Build output | iOS DeviceSupport, Rust `target/`, `node_modules`, `.next` / `.open-next` / `dist` / `.turbo` |
| Blocked | Simulator dyld cache (SIP), Docker leftovers (TCC), `/usr/local` MySQL (sudo) |

Discovery is conservative on purpose:

- `node_modules` is only offered when the project has a **lockfile**, so the
  reinstall is deterministic.
- `target/` is only offered when a sibling **Cargo.toml** proves it is a Cargo
  build directory. Vendored downloads inside `target/` (e.g. Tauri's CEF) are kept.
- Sizes come from `du -sk`, which counts allocated blocks — so sparse files
  like `Docker.raw` are measured honestly rather than by apparent size.

## Safety

Every path goes through `Guardrail.isSafe` before deletion. A path must sit
**strictly inside** one of a fixed set of container directories, so a bug cannot
remove a container itself (`~/Library/Caches`, `~/Projects`, …), your home
directory, or anything outside the allowlist. `~/.Trash` is the one exception,
and it is only ever emptied, never removed.

`--selftest` exercises this against a throwaway directory, including a negative
case that points the cleaner at `~/Documents` and asserts it is refused.

## Command line

```bash
./.build/release/CleanupApp --scan            # dry run: print findings, delete nothing
./.build/release/CleanupApp --scan --verbose  # with scan progress on stderr
./.build/release/CleanupApp --scan --menu     # also print the menu bar structure
./.build/release/CleanupApp --selftest        # guardrail + delete-path checks
```

## Known limits

- Reading `~/.Trash` needs Full Disk Access; without it the Trash row reports 0.
- The scan shells out to `find` over `~/Projects`, so a very large tree takes a
  few seconds.
- The bundle is ad-hoc signed. On first launch macOS may need right-click → Open.

## Layout

| File | Role |
|---|---|
| `AppDelegate.swift` | Window (fixed size, hide-on-close) and the menu bar item |
| `CleanupEngine.swift` | Sizing, discovery, guardrail, deletion, menu row builder |
| `ContentView.swift` | The four screens and the shared `Model` |
| `RetroUI.swift` | Win95 palette, bevels, buttons, checkboxes, progress bar |
| `tools/make-icon.swift` | Renders `AppIcon.iconset`; `build.sh` turns it into `.icns` |
