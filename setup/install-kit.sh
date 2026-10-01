#!/usr/bin/env bash
# Copy the kit source to ~/work/kit with a progress display, check it, start the menu.
# Usage: bash ~/work-kit/setup/install-kit.sh
set -euo pipefail
trap 'echo "install-kit.sh stopped at line $LINENO (exit $?)" >&2' ERR
# Background jobs of a script ignore Ctrl+C: stop the copy and the check with the script,
# never leave them running unseen.
copy_pid=""; sum_pid=""; pidfile=""
stop_all() {
  trap - ERR
  local p
  for p in $copy_pid $sum_pid $( [ -n "$pidfile" ] && cat "$pidfile" 2>/dev/null ); do
    pkill -TERM -P "$p" 2>/dev/null || true
    kill -TERM "$p" 2>/dev/null || true
  done
  printf '\nStopped. Nothing is lost: run this script again to finish.\n' >&2
  exit 130
}
trap stop_all INT TERM HUP

SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$SOURCE/kit"
DEST="$HOME/work/kit"
# -f, not -x: a stick mounted without execute bits (exFAT fmask, noexec) must still work
[ -f "$SRC/install" ] || { echo "kit not found at $SRC"; exit 1; }
[ -f "$SRC/offline/SHA256SUMS" ] || { echo "The kit source is incomplete. Run bash '$SOURCE/setup/fetch-offline.sh' (kit/offline/SHA256SUMS is missing)."; exit 1; }
while IFS= read -r entry; do
  file="${entry:66}"
  [ -f "$SRC/offline/$file" ] || { echo "The kit source is incomplete: kit/offline/$file is missing. Run bash '$SOURCE/setup/fetch-offline.sh'."; exit 1; }
done <"$SRC/offline/SHA256SUMS"

echo "Measuring the kit source ..."
total_mb="$(du -sm "$SRC" | cut -f1)"
free_mb="$(df -Pm "$HOME" | awk 'NR==2 {print $4}')"
# An existing copy is overwritten in place, so its space counts as free.
if [ -d "$DEST" ]; then
  old_mb="$(du -sm "$DEST" 2>/dev/null | cut -f1 || true)"
  free_mb=$((free_mb + ${old_mb:-0}))
fi
# A first install unpacks about 20 GB; an update only reinstalls the changed modules, whose old
# files are already on the disk (the 20 GB counted again stopped an update with 14 GB free, 28.09.).
install_mb=20000; install_what="the install"
if [ -f "${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/install-state.json" ]; then
  install_mb=3000; install_what="updating the installed modules"
fi
need_mb=$((total_mb + install_mb))
if [ "$free_mb" -lt "$need_mb" ]; then
  echo "Not enough disk space: the kit needs about ${need_mb} MB (${total_mb} MB copy + about ${install_mb} MB for ${install_what}), free ${free_mb} MB."
  echo "Free about $((need_mb - free_mb)) MB more."
  exit 1
fi

# Seconds between progress updates (tests use a smaller value).
TICK="${KIT_PROGRESS_INTERVAL:-2}"

mkdir -p "$HOME/work"
if [ -e "$DEST" ]; then
  echo "$DEST exists already: files are replaced with the kit source version."
fi

# An update skips the offline files whose checksum is the same in the old and the new
# SHA256SUMS (the check below verifies them again) and copies the rest, when an rsync with
# progress output is there; a first copy, or a system without such an rsync, copies everything with tar.
rsync_info=""
# not "rsync --help | grep -q": with pipefail, grep's early exit fails the pipe
command -v rsync >/dev/null 2>&1 && case "$(rsync --help 2>&1 || true)" in *--info=*) rsync_info=1 ;; esac
if [ -f "$DEST/offline/SHA256SUMS" ] && [ -n "$rsync_info" ]; then
  echo "Comparing with the kit source ..."
  same="$(mktemp)"
  # same "checksum  path" line in both lists -> unchanged; rsync pattern chars are escaped
  LC_ALL=C comm -12 <(LC_ALL=C sort "$DEST/offline/SHA256SUMS") <(LC_ALL=C sort "$SRC/offline/SHA256SUMS") \
    | sed -e 's/^[0-9a-f]*  //' -e 's/[][*?\\]/\\&/g' -e 's|^|/offline/|' >"$same" || true
  # exFAT keeps times to 10 ms and FAT to 2 s: --modify-window=2 treats those as equal
  rs=(rsync -rt --modify-window=2 --no-inc-recursive --exclude-from="$same")
  change_b="$(LC_ALL=C "${rs[@]}" --dry-run --stats "$SRC/" "$DEST/" 2>/dev/null \
    | awk -F': ' '/^Total transferred file size/ { gsub(/[^0-9]/, "", $2); print $2 }' || true)"
  change_mb=$(( ${change_b:-0} / 1048576 ))
  if [ "$change_mb" -gt 0 ]; then
    echo "Updating $DEST: ${change_mb} of ${total_mb} MB differ from the kit source and are copied ..."
  else
    echo "Updating $DEST: less than 1 MB differs from the kit source ..."
  fi
  plog="$(mktemp)"
  LC_ALL=C "${rs[@]}" --info=progress2 "$SRC/" "$DEST/" >"$plog" 2>&1 &
  copy_pid=$!
  while kill -0 "$copy_pid" 2>/dev/null; do
    done_b="$(tail -c 400 "$plog" 2>/dev/null | tr '\r' '\n' \
      | awk '$1 ~ /^[0-9,]+$/ { x = $1 } END { gsub(/,/, "", x); print x + 0 }' || true)"
    done_mb=$(( ${done_b:-0} / 1048576 ))
    [ "$done_mb" -gt "$change_mb" ] && done_mb=$change_mb
    [ "$change_mb" -gt 0 ] && printf '\r  %5d / %d MB (%d%%)   ' "$done_mb" "$change_mb" $((done_mb * 100 / change_mb))
    sleep "$TICK"
  done
  if ! wait "$copy_pid"; then
    printf '\n'
    grep -v '^ *[0-9,]' "$plog" | tail -n 10 || true
    rm -f "$plog" "$same"
    echo "Copy error: see the lines above, then run this script again."
    exit 1
  fi
  copy_pid=""
  rm -f "$plog" "$same"
  if [ "$change_mb" -gt 0 ]; then printf '\r  %5d / %d MB (100%%)   \n' "$change_mb" "$change_mb"; else echo "  done"; fi
else
  echo "Copying ${total_mb} MB to $DEST ..."
  # Progress = bytes the reading tar has read (/proc/<pid>/io); an old copy in $DEST would make
  # the size of $DEST useless. Without /proc (macOS) the size of $DEST is used.
  pidfile="$(mktemp)"
  # sh -c writes its own pid, then becomes tar (exec keeps the pid)
  sh -c 'echo $$ >"$1"; cd "$2" && exec tar -cf - .' sh "$pidfile" "$SRC" \
    | ( mkdir -p "$DEST" && cd "$DEST" && exec tar -xf - ) &
  copy_pid=$!
  while kill -0 "$copy_pid" 2>/dev/null; do
    read_pid="$(cat "$pidfile" 2>/dev/null || true)"
    if [ -n "$read_pid" ] && [ -r "/proc/$read_pid/io" ]; then
      done_mb=$(( $(awk '/^rchar:/ {print $2}' "/proc/$read_pid/io" 2>/dev/null || echo 0) / 1048576 ))
    else
      # du fails on files tar replaces at that moment; that must not stop the script
      done_mb="$(du -sm "$DEST" 2>/dev/null | cut -f1 || true)"
    fi
    [ "${done_mb:-0}" -gt "$total_mb" ] && done_mb=$total_mb
    printf '\r  %5d / %d MB (%d%%)   ' "${done_mb:-0}" "$total_mb" $((${done_mb:-0} * 100 / (total_mb > 0 ? total_mb : 1)))
    sleep "$TICK"
  done
  wait "$copy_pid"
  copy_pid=""
  rm -f "$pidfile"; pidfile=""
  printf '\r  %5d / %d MB (100%%)   \n' "$total_mb" "$total_mb"
fi

# Files of an older kit that this source no longer has would be installed again from ~/work/kit:
# move them out (kept, not deleted) so ~/work/kit matches the source exactly.
lists="$(mktemp -d)"
( cd "$SRC" && find . \( -type f -o -type l \) | LC_ALL=C sort ) >"$lists/src"
( cd "$DEST" && find . \( -type f -o -type l \) | LC_ALL=C sort ) >"$lists/dest"
LC_ALL=C comm -13 "$lists/src" "$lists/dest" >"$lists/stale"
if [ -s "$lists/stale" ]; then
  old_dir="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/backups/work-kit/$(date +%Y%m%d-%H%M%S)"
  while IFS= read -r f; do
    mkdir -p "$old_dir/$(dirname "$f")"
    mv "$DEST/$f" "$old_dir/$f"
  done <"$lists/stale"
  find "$DEST" -depth -type d -empty -delete 2>/dev/null || true
  echo "$(grep -c . "$lists/stale") file(s) of the older kit are no longer in the kit source: moved to $old_dir"
fi
# keep the last five old-kit backups
old_root="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/backups/work-kit"
if [ -d "$old_root" ]; then
  ls -1d "$old_root"/*/ 2>/dev/null | LC_ALL=C sort \
    | awk '{ a[NR] = $0 } END { for (i = 1; i <= NR - 5; i++) print a[i] }' \
    | while IFS= read -r d; do rm -rf "$d"; done || true
fi
rm -rf "$lists"

echo "Checking file integrity ..."
sums="$DEST/offline/SHA256SUMS"
[ -f "$sums" ] || { echo "The kit source is incomplete. Run bash '$SOURCE/setup/fetch-offline.sh'."; exit 1; }
total_files="$(grep -c . "$sums")"
sumlog="$(mktemp)"
trap 'rm -f "$sumlog"' EXIT   # the success path removes it before exec
line_buffered=""
command -v stdbuf >/dev/null 2>&1 && line_buffered="stdbuf -oL"
( cd "$DEST/offline" && $line_buffered sha256sum -c SHA256SUMS >"$sumlog" 2>&1 ) &
sum_pid=$!
# The percentage follows the bytes read (/proc/<pid>/io, Linux): the big model files come last
# and would hold a file count at 97 % for minutes. Without /proc it follows the file count.
offline_mb="$(du -sm "$DEST/offline" 2>/dev/null | cut -f1 || true)"
by_mb=""
while kill -0 "$sum_pid" 2>/dev/null; do
  checked="$(grep -c ': ' "$sumlog" 2>/dev/null || true)"
  pct=$((checked * 100 / (total_files > 0 ? total_files : 1)))
  hash_pid="$(pgrep -n -P "$sum_pid" sha256sum 2>/dev/null || true)"
  [ -z "$hash_pid" ] && [ "$(cat "/proc/$sum_pid/comm" 2>/dev/null)" = sha256sum ] && hash_pid=$sum_pid
  if [ -n "$hash_pid" ] && [ -r "/proc/$hash_pid/io" ] && [ "${offline_mb:-0}" -gt 0 ]; then
    read_mb=$(( $(awk '/^rchar:/ {print $2}' "/proc/$hash_pid/io" 2>/dev/null || echo 0) / 1048576 ))
    [ "$read_mb" -gt "$offline_mb" ] && read_mb=$offline_mb
    pct=$((read_mb * 100 / offline_mb))
    # Show the same unit as the percentage (a file count next to a byte percentage disagrees).
    by_mb=1
    printf '\r  %6d / %d MB checked (%d%%)   ' "$read_mb" "$offline_mb" "$pct"
  elif [ -z "$by_mb" ]; then
    printf '\r  %6d / %d files checked (%d%%)   ' "$checked" "$total_files" "$pct"
  fi
  sleep "$TICK"
done
sum_ok=""; wait "$sum_pid" && sum_ok=1; sum_pid=""
if [ -n "$sum_ok" ] && [ -n "$by_mb" ]; then
  printf '\r  %6d / %d MB checked (100%%)   \n' "$offline_mb" "$offline_mb"
elif [ -n "$sum_ok" ]; then
  printf '\r  %6d / %d files checked (100%%)   \n' "$total_files" "$total_files"
else
  printf '\n'
  # A file an update skipped can differ from its old checksum (damaged on disk): copy the failed
  # files from the kit source once more and check them again before giving up.
  failed="$(grep -v ': OK$' "$sumlog" | sed -n 's/: FAILED.*$//p' || true)"
  retry_ok=""
  if [ -n "$failed" ]; then
    echo "$(grep -c . <<<"$failed") file(s) differ: copying them again from the kit source ..."
    retry_ok=1
    while IFS= read -r f; do
      mkdir -p "$DEST/offline/$(dirname "$f")"
      cp "$SRC/offline/$f" "$DEST/offline/$f" || retry_ok=""
    done <<<"$failed"
    if [ -n "$retry_ok" ]; then
      recheck="$(mktemp)"
      while IFS= read -r f; do grep -F "  $f" "$sums" | awk -v f="$f" 'substr($0, 67) == f'; done <<<"$failed" >"$recheck"
      ( cd "$DEST/offline" && sha256sum -c "$recheck" >"$sumlog" 2>&1 ) || retry_ok=""
      rm -f "$recheck"
    fi
  fi
  if [ -z "$retry_ok" ]; then
    grep -v ': OK$' "$sumlog" | head -n 10
    echo "Checksum error. Run bash '$SOURCE/setup/fetch-offline.sh', then rerun this installer."
    exit 1
  fi
  echo "  all files checked (100%)"
fi
rm -f "$sumlog"
# Restore execute bits that a stick mounted without them (exFAT fmask, noexec) dropped.
if [ -f "$DEST/.exec-files" ]; then
  ( cd "$DEST" && while IFS= read -r f; do [ -f "$f" ] && chmod u+x,go+rx "$f"; done <.exec-files ) || true
fi
echo "Copy OK. Starting the menu."
exec bash "$DEST/install" "$@"
