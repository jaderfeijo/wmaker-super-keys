# wmaker-super-keys

> Part of [wmodern](https://github.com/jaderfeijo/wmodern), a modern desktop on Window Maker: `wmodern install super-keys` installs it and keeps it up to date.

macOS-style **Super-key shortcuts for [Window Maker](https://www.windowmaker.org/)** (Super = the Windows key,
standing in for Cmd). Window Maker only binds a handful of keys out of the box and has no tiling, no "focus the
window to my left" and no "show desktop". This adds them with small shell and Python scripts on top of
[`xbindkeys`](https://www.nongnu.org/xbindkeys/) and [`wmctrl`](https://github.com/Conservatory/wmctrl), plus a few
settings in Window Maker itself.

## What you get

| Shortcut | Action |
|---|---|
| `Super+Space` | App launcher ([rofi](https://github.com/davatorium/rofi)); a second press closes it |
| `Super+R` | Run a command (rofi) |
| `Super+Ctrl+Q` | Lock the screen (`loginctl lock-session`) |
| `Super+W` / `Super+M` / `Super+H` | Close / minimize / hide the window (Window Maker's own shortcuts) |
| `Super+Tab`, `Super+Shift+Tab` | Next / previous window (Window Maker) |
| ``Super+` `` | Cycle through the windows of the **same application** |
| `Super+N` | New window of the focused application |
| `Super+←` `→` `↑` `↓` | Focus the nearest window in that direction |
| `Super+Shift+←` / `→` | Tile the window to the left / right half of the screen |
| `Super+Shift+C` | Center the window (keeps its size) |
| `Super+Shift+Return` | Maximize (press again to restore the previous size) |
| `Super+Shift+↓` / `↑` | Minimize / bring back the last minimized window |
| `Super+Shift+R` | Restore the window's original size and position after tiling |
| `Super+1` … `9`, `0` | Go to desktop 1–10, **creating it** if it does not exist yet |
| `Super+Shift+1` … `0` | Move the focused window to that desktop |
| `Super+Ctrl+←` / `→` | Previous / next desktop (Window Maker) |
| `Super+Ctrl+F` | Maximize (Window Maker) |
| `Super+Shift+H` | Hide every window on this desktop; press again to bring them back |
| `Super+C` / `Super+V` | Copy / paste in xterm |

Tiling and maximizing leave room for the Window Maker dock (it is detected automatically, on the left or the right).

## Requirements

* Window Maker on X11
* `xbindkeys`, `wmctrl`, `xprop` and `xwininfo` (package `x11-utils`), Python 3
* `rofi` for the launcher
* optional: a screen locker that reacts to `loginctl lock-session` (for example `xss-lock` with `i3lock`)

On Debian and Ubuntu: `sudo apt install xbindkeys wmctrl x11-utils python3 rofi`.

## Install

```
git clone https://github.com/jaderfeijo/wmaker-super-keys.git
cd wmaker-super-keys
./install.sh --dry-run      # see what it would do
./install.sh                # do it (add --install-deps to apt-install what is missing)
```

Then use **Window Maker > Restart** from the root menu (or log out and in) so Window Maker picks up its own
shortcuts. The `xbindkeys` shortcuts work immediately.

The installer is careful with an existing setup. It never replaces a config file; it adds a clearly marked block
(`# >>> wmaker-super-keys >>>`) to `~/.xbindkeysrc`, to Window Maker's `autostart` and to `~/.Xresources`. For
Window Maker's own shortcuts it records the value each key had before, so `--uninstall` puts them back. It tells
you if one of the Super combinations is already bound somewhere else.

| Option | |
|---|---|
| `--dry-run` | show what would be done, change nothing |
| `--uninstall` | remove everything and restore the Window Maker keys it changed |
| `--prefix DIR` | install the scripts into `DIR/bin` instead of `~/.local/bin` |
| `--install-deps` | `sudo apt-get install` any missing dependencies |
| `--no-autostart` | do not start `xbindkeys` from Window Maker's autostart file |
| `--no-wmaker-keys` | leave Window Maker's own shortcuts alone |
| `--no-xterm`, `--no-rofi` | skip the xterm paste shortcuts / the rofi config |
| `--no-show-desktop` | do not bind `Super+Shift+H` (another tool may want that key) |
| `--no-restart` | do not restart `xbindkeys` or reload X resources right now |

## Customize

* **Change a key:** edit `config/xbindkeys-super.conf` and re-run `./install.sh` (or edit the block it added to
  `~/.xbindkeysrc`). Run `xbindkeys -k` to see how a key is spelled.
* **Dock size:** set `WMSK_DOCK_LEFT` / `WMSK_DOCK_RIGHT` (pixels) in `~/.config/wmaker-super-keys/config`
  to override the automatic detection, for example `WMSK_DOCK_LEFT=64`.
* **Window Maker's shortcuts:** `config/windowmaker-keys.conf`.

## How it works

* `xbindkeys` runs the `wmsk-*` scripts in `bin/` when a Super combination is pressed.
* Tiling, desktops and focus use the standard EWMH window-manager hooks through `wmctrl` and `xprop`.
* "Hide all" and "bring back the last minimized window" need Window Maker's own *hide* behaviour, which has no
  public hook, so `wmsk-show-desktop` presses Window Maker's hide key through the X `XTEST` extension, window by
  window.
* Window Maker's shortcuts (`CloseKey`, `MiniaturizeKey`, ...) are plain entries in `~/GNUstep/Defaults/WindowMaker`.

## Limits

* X11 only, and written for Window Maker; other window managers may need the key names adjusted.
* Cmd+C / Cmd+V inside ordinary applications are not remapped (that would also change the terminal's `Ctrl+C`).
  Only xterm gets `Super+C` / `Super+V`.
* Window Maker only reads its own shortcuts at startup, so a restart is needed after installing.

## Tests

```
tests/run.sh
```

Syntax checks, then install / re-install / uninstall inside a throwaway `HOME` (your real configuration is never
touched), then a scan that fails if anything machine-specific (home directories, e-mail addresses, IP or MAC
addresses, tokens) is in the repository. Set `PRIVACY_TERMS='host|user'` to add your own words to that scan.

## License

MIT, see [LICENSE](LICENSE).
