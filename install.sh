#!/usr/bin/env bash
# wmaker-super-keys installer: macOS-style Super-key shortcuts for Window Maker.
# Run ./install.sh --help for the options. Everything it changes is reversible with ./install.sh --uninstall.
set -euo pipefail

NAME=wmaker-super-keys
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PREFIX="${PREFIX:-$HOME/.local}"
DRY=0 UNINSTALL=0 DO_AUTOSTART=1 DO_WMKEYS=1 DO_XTERM=1 DO_ROFI=1 DO_RESTART=1 DO_DEPS=1 INSTALL_DEPS=0

usage() {
  cat <<USAGE
Usage: ./install.sh [options]

  --uninstall        remove everything this installer added and restore the Window Maker keys it changed
  --dry-run          show what would be done, change nothing
  --prefix DIR       install the scripts into DIR/bin (default: \$HOME/.local)
  --install-deps     install missing dependencies with 'sudo apt-get install' (Debian and derivatives)
  --no-autostart     do not add xbindkeys to Window Maker's autostart file
  --no-wmaker-keys   do not change Window Maker's own shortcuts (Super+W, Super+M, Super+Tab ...)
  --no-xterm         do not add Super+C / Super+V copy and paste to xterm
  --no-rofi          do not create a rofi config that lets Super+Space close the launcher
  --no-restart       do not restart xbindkeys / reload X resources now
  -h, --help         this help
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --uninstall) UNINSTALL=1 ;;
    --dry-run) DRY=1 ;;
    --prefix) PREFIX="${2:?--prefix needs a directory}"; shift ;;
    --install-deps) INSTALL_DEPS=1 ;;
    --skip-deps-check) DO_DEPS=0 ;;
    --no-autostart) DO_AUTOSTART=0 ;;
    --no-wmaker-keys) DO_WMKEYS=0 ;;
    --no-xterm) DO_XTERM=0 ;;
    --no-rofi) DO_ROFI=0 ;;
    --no-restart) DO_RESTART=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

BIN="$PREFIX/bin"
GNUSTEP="${GNUSTEP_USER_ROOT:-$HOME/GNUstep}"
WM_DEFAULTS="$GNUSTEP/Defaults/WindowMaker"
WM_AUTOSTART="$GNUSTEP/Library/WindowMaker/autostart"
XBINDKEYSRC="$HOME/.xbindkeysrc"
XRESOURCES="$HOME/.Xresources"
ROFI_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/config.rasi"
STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/$NAME"
STATE_FILE="$STATE_DIR/previous-windowmaker-keys.json"
EDIT=(python3 "$HERE/lib/edit.py")
DRYFLAG=()
[ "$DRY" = 1 ] && DRYFLAG=(--dry)

say() { printf '%s\n' "$*"; }
act() { if [ "$DRY" = 1 ]; then say "[dry-run] $*"; else "$@"; fi; }
have() { command -v "$1" >/dev/null 2>&1; }
x_available() { [ -n "${DISPLAY:-}" ] && have xrdb; }

restart_xbindkeys() {
  [ "$DO_RESTART" = 1 ] && [ "$DRY" = 0 ] && x_available || return 0
  pkill -x xbindkeys 2>/dev/null || true
  sleep 0.3
  if have xbindkeys && [ "$UNINSTALL" = 0 ]; then (setsid xbindkeys >/dev/null 2>&1 &); say "  restarted xbindkeys"; fi
}

uninstall() {
  say "Uninstalling $NAME ..."
  for f in "$HERE"/bin/*; do act rm -f "$BIN/$(basename "$f")"; done
  "${EDIT[@]}" block-remove "$XBINDKEYSRC" '#' "${DRYFLAG[@]}"
  "${EDIT[@]}" block-remove "$WM_AUTOSTART" '#' "${DRYFLAG[@]}"
  "${EDIT[@]}" block-remove "$XRESOURCES" '!' "${DRYFLAG[@]}"
  if [ -f "$STATE_FILE" ]; then "${EDIT[@]}" wm-restore "$WM_DEFAULTS" "$STATE_FILE" "${DRYFLAG[@]}"; fi
  if [ -f "$ROFI_CONFIG" ] && cmp -s "$ROFI_CONFIG" "$HERE/config/rofi-config.rasi"; then act rm -f "$ROFI_CONFIG"; fi
  [ "$DRY" = 1 ] || rmdir "$STATE_DIR" 2>/dev/null || true
  restart_xbindkeys
  say "Done. Window Maker re-reads its shortcuts when it restarts (root menu > Window Maker > Restart)."
}

check_dependencies() {
  local missing=() pkgs=()
  have xbindkeys || { missing+=(xbindkeys); pkgs+=(xbindkeys); }
  have wmctrl    || { missing+=(wmctrl); pkgs+=(wmctrl); }
  { have xprop && have xwininfo; } || { missing+=("xprop/xwininfo"); pkgs+=(x11-utils); }
  have python3   || { missing+=(python3); pkgs+=(python3); }
  have rofi      || say "Note: rofi is not installed; Super+Space and Super+R (the launcher) need it."
  if [ "${#missing[@]}" -gt 0 ]; then
    say "Missing: ${missing[*]}"
    if [ "$INSTALL_DEPS" = 1 ] && have apt-get; then
      act sudo apt-get install -y "${pkgs[@]}" rofi
    else
      say "Install them first, e.g.:  sudo apt install ${pkgs[*]} rofi   (or re-run with --install-deps)"
      [ "$DRY" = 1 ] || exit 1
    fi
  fi
}

install_all() {
  say "Installing $NAME into $BIN ..."
  [ "$DO_DEPS" = 1 ] && check_dependencies

  # 1. scripts
  for f in "$HERE"/bin/*; do act install -D -m 755 "$f" "$BIN/$(basename "$f")"; done

  # 2. xbindkeys bindings (a marked block; the scripts are referenced by absolute path)
  tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
  sed "s#\"wmsk-#\"$BIN/wmsk-#; s#|| wmsk-#|| $BIN/wmsk-#" "$HERE/config/xbindkeys-super.conf" > "$tmp"
  "${EDIT[@]}" block-add "$XBINDKEYSRC" '#' "$tmp" "${DRYFLAG[@]}"
  say "  bindings added to $XBINDKEYSRC"
  if [ -f "$XBINDKEYSRC" ]; then
    # warn about Super combinations that were already bound outside our block
    outside=$(awk -v b="# >>> $NAME >>>" -v e="# <<< $NAME <<<" '$0==b{s=1} !s{print} $0==e{s=0}' "$XBINDKEYSRC")
    dupes=$(grep -E '^\s+Mod4' "$HERE/config/xbindkeys-super.conf" | sed 's/^ *//' | sort -u | while read -r k; do grep -qxF "    $k" <<<"$outside" && echo "$k"; done || true)
    [ -z "$dupes" ] || say "  warning: these Super keys are also bound elsewhere in $XBINDKEYSRC (the first binding wins):" $'\n'"$dupes"
  fi

  # 3. Window Maker's own shortcuts
  if [ "$DO_WMKEYS" = 1 ]; then
    [ "$DRY" = 1 ] || mkdir -p "$STATE_DIR"
    "${EDIT[@]}" wm-set "$WM_DEFAULTS" "$HERE/config/windowmaker-keys.conf" "$STATE_FILE" "${DRYFLAG[@]}"
    say "  Window Maker shortcuts set in $WM_DEFAULTS (originals remembered for --uninstall)"
  fi

  # 4. start xbindkeys with Window Maker
  if [ "$DO_AUTOSTART" = 1 ]; then
    printf '%s\n' '# Start the Super-key shortcuts once the session has settled' '( sleep 3; pkill -x xbindkeys; exec xbindkeys ) >/dev/null 2>&1 &' > "$tmp"
    [ -f "$WM_AUTOSTART" ] || { act mkdir -p "$(dirname "$WM_AUTOSTART")"; [ "$DRY" = 1 ] || printf '#!/bin/sh\nexit 0\n' > "$WM_AUTOSTART"; }
    "${EDIT[@]}" block-add "$WM_AUTOSTART" '#' "$tmp" --before-exit "${DRYFLAG[@]}"
    act chmod +x "$WM_AUTOSTART"
    say "  xbindkeys added to $WM_AUTOSTART"
  fi

  # 5. xterm copy / paste
  if [ "$DO_XTERM" = 1 ]; then
    "${EDIT[@]}" block-add "$XRESOURCES" '!' "$HERE/config/xterm-copy-paste.Xresources" "${DRYFLAG[@]}"
    say "  xterm Super+C / Super+V added to $XRESOURCES"
    [ "$DO_RESTART" = 1 ] && [ "$DRY" = 0 ] && x_available && xrdb -merge "$XRESOURCES" && say "  X resources reloaded (open xterms need a restart)"
  fi

  # 6. rofi: let Super+Space close the launcher
  if [ "$DO_ROFI" = 1 ]; then
    if [ ! -f "$ROFI_CONFIG" ]; then
      act install -D -m 644 "$HERE/config/rofi-config.rasi" "$ROFI_CONFIG"; say "  rofi config created: $ROFI_CONFIG"
    elif ! grep -q 'Super+space' "$ROFI_CONFIG"; then
      say "  note: you already have a rofi config; add this to it so Super+Space closes the launcher:  kb-cancel: \"Escape,Super+space\";"
    fi
  fi

  restart_xbindkeys
  case ":$PATH:" in *":$BIN:"*) ;; *) say "  note: $BIN is not on your PATH (the bindings use absolute paths, so they work anyway)." ;; esac
  say ""
  say "Done. For Window Maker's own shortcuts (Super+W, Super+M, Super+Tab ...) use the root menu >"
  say "Window Maker > Restart, or log out and in. Remove everything again with: ./install.sh --uninstall"
}

if [ "$UNINSTALL" = 1 ]; then uninstall; else install_all; fi
