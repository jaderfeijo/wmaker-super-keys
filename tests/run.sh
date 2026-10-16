#!/usr/bin/env bash
# Tests: script syntax, install / re-install / uninstall in a throwaway HOME, and a scan that makes sure
# nothing about the machine that runs them can end up in the repository.
set -uo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FAILS=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

echo "syntax"
for f in "$REPO"/bin/* "$REPO"/install.sh "$REPO"/tests/run.sh; do
  case $(head -1 "$f") in
    *python*) python3 -I -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$f" ;;
    *) bash -n "$f" ;;
  esac && ok "$(basename "$f")" || fail "$(basename "$f")"
done
python3 -I -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$REPO/lib/edit.py" && ok "lib/edit.py" || fail "lib/edit.py"

echo "bindings"
check "every command in the bindings is a script that exists" '
  grep -oE "wmsk-[a-z-]+" "$REPO/config/xbindkeys-super.conf" | sort -u | while read -r c; do [ -f "$REPO/bin/$c" ] || { echo "missing $c" >&2; exit 1; }; done'
check "no key combination is bound twice" '
  [ -z "$(grep -E "^\s+Mod4" "$REPO/config/xbindkeys-super.conf" | sort | uniq -d)" ]'

echo "install in a throwaway HOME"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T" ; unset XDG_CONFIG_HOME XDG_DATA_HOME GNUSTEP_USER_ROOT DISPLAY
mkdir -p "$T/GNUstep/Defaults" "$T/GNUstep/Library/WindowMaker"
cat > "$T/GNUstep/Defaults/WindowMaker" <<'WM'
{
  FocusMode = sloppy;
  CloseKey = "Mod1+F4";
  MiniaturizeKey = ("Mod1+M", "Mod1+H");
  RaiseDelay = 1;
}
WM
printf '#!/bin/sh\nxrdb -merge ~/.Xresources\nexit 0\n' > "$T/GNUstep/Library/WindowMaker/autostart"
printf '# my own binding\n"echo hi"\n    Mod1 + x\n' > "$T/.xbindkeysrc"
printf 'Xft.dpi: 96\n' > "$T/.Xresources"
cp "$T/GNUstep/Defaults/WindowMaker" "$T/wm.before"

"$REPO/install.sh" --skip-deps-check --no-restart --dry-run > "$T/dry.out" 2>&1
check "--dry-run changes nothing" '! [ -d "$T/.local/bin" ] && cmp -s "$T/GNUstep/Defaults/WindowMaker" "$T/wm.before"'

"$REPO/install.sh" --skip-deps-check --no-restart > "$T/install.out" 2>&1 || { cat "$T/install.out"; fail "install exited with an error"; }
check "scripts installed and executable" '
  n=$(ls "$REPO/bin" | wc -l); [ "$(ls "$T/.local/bin"/wmsk-* | wc -l)" = "$n" ] && [ -z "$(find "$T/.local/bin" -type f ! -perm -u+x)" ]'
check "bindings use absolute script paths" 'grep -q "\"$T/.local/bin/wmsk-snap left\"" "$T/.xbindkeysrc"'
check "existing xbindkeys binding kept" 'grep -qF "\"echo hi\"" "$T/.xbindkeysrc"'
check "Window Maker keys set" 'grep -q "CloseKey = \"Mod4+W\";" "$T/GNUstep/Defaults/WindowMaker" && grep -q "HideKey = \"Mod4+H\";" "$T/GNUstep/Defaults/WindowMaker"'
check "unrelated Window Maker settings kept" 'grep -q "FocusMode = sloppy;" "$T/GNUstep/Defaults/WindowMaker" && grep -q "RaiseDelay = 1;" "$T/GNUstep/Defaults/WindowMaker"'
check "autostart block is before exit 0" '[ "$(tail -1 "$T/GNUstep/Library/WindowMaker/autostart")" = "exit 0" ] && grep -q "exec xbindkeys" "$T/GNUstep/Library/WindowMaker/autostart"'
check "xterm copy/paste added, Xft.dpi kept" 'grep -q "Mod4 <Key>c" "$T/.Xresources" && grep -q "Xft.dpi: 96" "$T/.Xresources"'
check "rofi config created" '[ -f "$T/.config/rofi/config.rasi" ]'

find "$T" -type f ! -name '*.out' ! -name 'wm.before' ! -name 'state?' -exec sha1sum {} + | sort -k2 > "$T/state1"
"$REPO/install.sh" --skip-deps-check --no-restart > /dev/null 2>&1
find "$T" -type f ! -name '*.out' ! -name 'wm.before' ! -name 'state?' -exec sha1sum {} + | sort -k2 > "$T/state2"
check "installing twice changes nothing (idempotent)" 'cmp -s "$T/state1" "$T/state2" || { diff "$T/state1" "$T/state2" >&2; false; }'
check "second install keeps one block per file" '[ "$(grep -c ">>> wmaker-super-keys >>>" "$T/.xbindkeysrc")" = 1 ]'

echo "uninstall"
"$REPO/install.sh" --no-restart --uninstall > /dev/null 2>&1
check "scripts removed" '[ -z "$(ls "$T/.local/bin" 2>/dev/null)" ]'
check "Window Maker keys restored exactly" 'cmp -s "$T/GNUstep/Defaults/WindowMaker" "$T/wm.before"'
check "own xbindkeys binding survives" 'grep -qF "\"echo hi\"" "$T/.xbindkeysrc" && ! grep -q "wmaker-super-keys" "$T/.xbindkeysrc"'
check "Xresources back to the original" '[ "$(cat "$T/.Xresources")" = "Xft.dpi: 96" ]'
check "autostart back to the original" '! grep -q "wmaker-super-keys" "$T/GNUstep/Library/WindowMaker/autostart" && grep -q "^exit 0" "$T/GNUstep/Library/WindowMaker/autostart"'

echo "privacy: nothing about the machine that runs these tests is in the repository"
cd "$REPO"
files=$(git ls-files 2>/dev/null || find . -type f -not -path './.git/*')
scan() {  # scan LABEL REGEX
  hits=$(echo "$files" | xargs grep -nIE -e "$2" 2>/dev/null | grep -v '^tests/run.sh:' || true)
  if [ -z "$hits" ]; then ok "$1"; else fail "$1"; echo "$hits" | head -5 | sed 's/^/        /'; fi
}
REAL_HOME=${REAL_HOME:-}
scan "no absolute home directories"           '(/home/[a-z_][a-z0-9_-]*|/Users/[A-Za-z0-9_-]+|/root/)'
scan "no e-mail addresses"                    '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
scan "no IP or MAC addresses"                 '([0-9]{1,3}\.){3}[0-9]{1,3}|([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}'
scan "no tokens or private keys"              '(ghp_|gho_|github_pat_|BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16})'
if [ -n "${PRIVACY_TERMS:-}" ]; then scan "none of the extra terms in \$PRIVACY_TERMS (host name, user name, ...)" "$PRIVACY_TERMS"; fi

echo
if [ "$FAILS" = 0 ]; then echo "all tests passed"; else echo "$FAILS test(s) failed"; exit 1; fi
