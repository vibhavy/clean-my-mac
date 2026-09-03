# Clean Up My Machine

A small macOS app with one job: find storage you can get back, show you the
total, and delete it only after you confirm. Win95 chrome, because why not.

## Install

There are no prebuilt downloads — you build it once and copy it in. Takes about
ten seconds.

```bash
git clone git@github.com:vibhavy/clean-my-mac.git
cd clean-my-mac
./build.sh
cp -R "dist/Clean Up My Machine.app" /Applications/
```

Then launch it from Spotlight or:

```bash
open "/Applications/Clean Up My Machine.app"
```

Requires macOS 13+ and the Xcode command line tools (`xcode-select --install`) for
the Swift compiler.

### First launch

The bundle is **ad-hoc signed**, not notarised — there is no Apple Developer
account behind it. A locally built copy opens normally. But if you move it
between machines by download or AirDrop, macOS quarantines it and refuses to open
it with a "damaged" or "unidentified developer" warning. Clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine "/Applications/Clean Up My Machine.app"
```

Right-click → **Open** works too, once, and gives you an "Open anyway" button.

### Keep it in the menu bar

The app puts a drive icon in the menu bar and stays there after you close the
window. To have it there after every reboot, add it under **System Settings →
General → Login Items → Open at Login**.

### Installing on another Mac

`build.sh` leaves a runnable bundle in `dist/`. To hand it to another machine,
zip it with `ditto` rather than Finder's Compress — that preserves the bundle's
symlinks and signature:

```bash
ditto -c -k --keepParent "dist/Clean Up My Machine.app" CleanUpMyMachine.zip
```

On the other Mac, unzip, drag to `/Applications`, and clear the quarantine flag
as above.

### Update

```bash
git pull && ./build.sh && cp -R "dist/Clean Up My Machine.app" /Applications/
```

Quit the app from the menu bar first, otherwise you are copying over a running
binary.

### Uninstall

```bash
rm -rf "/Applications/Clean Up My Machine.app"
```

It writes no preferences, no support files and no login items of its own, so
that is the whole of it.

## Build from source

To run it without installing:

```bash
./build.sh
open "dist/Clean Up My Machine.app"
```

`build.sh` compiles with SwiftPM, renders the icon, assembles the bundle and
ad-hoc signs it. Everything lands in `dist/`, which is gitignored.

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
