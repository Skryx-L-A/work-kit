#!/usr/bin/env bash
# kit-desk term: Ghostty fallback with fake terminals (no display needed).
# Ghostty that reports an old OpenGL late (56 s in a VM, here 4 s) must still fall back.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD="$(cd "$HERE/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }

setup() { # setup <ghostty body>: fresh HOME with kit-desk, a fake ghostty and a fake alacritty
  export HOME="$T/h$RANDOM"; mkdir -p "$HOME/bin" "$HOME/.local/share/work-kit/desktop/share/lib"
  cp "$MOD/lib/"*.sh "$HOME/.local/share/work-kit/desktop/share/lib/"
  printf '#!/usr/bin/env bash\n%s\n' "$1" >"$HOME/bin/ghostty"
  printf '#!/usr/bin/env bash\necho "alacritty $*" >>"$HOME/started"\n' >"$HOME/bin/alacritty"
  chmod +x "$HOME/bin/ghostty" "$HOME/bin/alacritty"
  export PATH="$HOME/bin:/usr/bin:/bin"
}
run() { # kit-desk term with a 60 s watchdog (macOS has no timeout(1))
  bash "$MOD/bin/kit-desk" term 2>/dev/null & local p=$! n=0
  while kill -0 "$p" 2>/dev/null && [ "$n" -lt 600 ]; do sleep 0.1; n=$((n + 1)); done
  kill "$p" 2>/dev/null; wait "$p" 2>/dev/null || true
}
broken() { [ -f "$HOME/.local/share/work-kit/desktop/state/ghostty-broken" ] || find "$HOME" -name ghostty-broken | grep -q .; }

setup 'sleep 4; echo "warning(opengl): OpenGL version is too old. Ghostty requires OpenGL 4.3" >&2; sleep 30'
start=$(date +%s); run; took=$(( $(date +%s) - start ))
grep -q '^alacritty' "$HOME/started" 2>/dev/null && ok "late OpenGL error falls back to the next terminal" || bad "late OpenGL error falls back to the next terminal"
broken && ok "late OpenGL error marks Ghostty broken" || bad "late OpenGL error marks Ghostty broken"
[ "$took" -lt 20 ] && ok "fallback does not wait for Ghostty to exit (${took}s)" || bad "fallback waited ${took}s"

setup 'echo "warning(gtk_ghostty_surface): surface failed to initialize err=error.SurfaceError" >&2; exit 0'
run
grep -q '^alacritty' "$HOME/started" 2>/dev/null && ok "quick surface error falls back" || bad "quick surface error falls back"

setup 'echo "info(opengl): loaded OpenGL 4.6" >&2; sleep 3; echo "ghostty closed" >>"$HOME/started"'
run
grep -q '^alacritty' "$HOME/started" 2>/dev/null && bad "working Ghostty does not fall back" || ok "working Ghostty does not fall back"
broken && bad "working Ghostty is not marked broken" || ok "working Ghostty is not marked broken"

# the kit's Ghostty (in the kit bin dir) with the software OpenGL pack: second start with llvmpipe
swsetup() { # swsetup <body when state/ghostty-sw exists>
  setup 'exit 9'
  local st="$HOME/.local/share/work-kit/desktop/state"
  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/work-kit/desktop/apps/ghostty-gl" "$st"
  rm -f "$HOME/bin/ghostty"
  printf '#!/usr/bin/env bash\nif [ -f "%s/ghostty-sw" ]; then %s; fi\necho "info(opengl): loaded OpenGL 3.3" >&2; echo "warning(opengl): OpenGL version is too old. Ghostty requires OpenGL 4.3" >&2\n' "$st" "$1" >"$HOME/.local/bin/ghostty"
  chmod +x "$HOME/.local/bin/ghostty"; export PATH="$HOME/.local/bin:$PATH"
}
swsetup 'echo "info(opengl): loaded OpenGL 4.5" >&2; echo "ghostty sw" >>"$HOME/started"; sleep 3; exit 0'
run
grep -q '^ghostty sw' "$HOME/started" 2>/dev/null && ok "no OpenGL 4.3: Ghostty starts again with the software OpenGL" || bad "no OpenGL 4.3: Ghostty starts again with the software OpenGL"
grep -q '^alacritty' "$HOME/started" 2>/dev/null && bad "software OpenGL Ghostty does not fall back" || ok "software OpenGL Ghostty does not fall back"
[ -f "$HOME/.local/share/work-kit/desktop/state/ghostty-sw" ] && ! broken && ok "ghostty-sw set, Ghostty not marked broken" || bad "ghostty-sw set, Ghostty not marked broken"
swsetup 'echo "warning(opengl): OpenGL version is too old. Ghostty requires OpenGL 4.3" >&2; exit 0'
run
grep -q '^alacritty' "$HOME/started" 2>/dev/null && broken && ok "software OpenGL fails too: Alacritty, Ghostty marked broken" || bad "software OpenGL fails too: Alacritty, Ghostty marked broken"

echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
