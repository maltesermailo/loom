#!/usr/bin/env bash
# Loom loopback demo (M1.1-M1.3). loomd streams the synthetic test pattern to
# loom-sdl over QUIC on 127.0.0.1; after ~10 s of streaming the SDL client's
# overlay numbers (e2e / rtt / decode / loss / bitrate) are printed. Release
# builds. Streams 1280x720 so software decode keeps up on the Mac (1440p software
# decode backlogs — hardware decode in M2.2/M3.2 removes that).
#
# In a GUI session an SDL window opens with the video + overlay; headless, the
# decode + overlay-print path still runs and the numbers are captured from stdout.
set -euo pipefail

cd "$(dirname "$0")/.."  # superrepo root

PORT=47800
WIDTH=1280
HEIGHT=720

host_log="$(mktemp)"
client_log="$(mktemp)"
host_pid=""
client_pid=""

cleanup() {
  [ -n "$client_pid" ] && kill "$client_pid" 2>/dev/null || true
  [ -n "$host_pid" ] && kill "$host_pid" 2>/dev/null || true
}
trap cleanup EXIT

wait_for() {  # wait_for <file> <pattern> <what>
  for _ in $(seq 1 240); do
    grep -q "$2" "$1" && return 0
    sleep 0.5
  done
  echo "demo: timed out waiting for $3" >&2
  cat "$1" >&2
  return 1
}

echo "== building + launching loomd (${WIDTH}x${HEIGHT} @ 127.0.0.1:${PORT}) =="
# Quiet the per-frame media flood but keep the 1/s STATS log line.
RUST_LOG="warn,loom::stats=info" \
  host/scripts/demo.sh --port "$PORT" --width "$WIDTH" --height "$HEIGHT" \
  >"$host_log" 2>&1 &
host_pid=$!
wait_for "$host_log" "listening on" "loomd to listen"

echo "== building + launching loom-sdl =="
client/scripts/demo.sh 127.0.0.1 "$PORT" >"$client_log" 2>&1 &
client_pid=$!
wait_for "$client_log" "STREAMING" "loom-sdl to start streaming"

echo "== streaming for 10 s =="
sleep 10

echo
echo "== overlay numbers (loom-sdl, last sample) =="
grep '^overlay:' "$client_log" | tail -1 || echo "(no overlay line captured)"

echo
echo "== host STATS (last sample) =="
grep '"event":"stats"' "$host_log" | tail -1 || echo "(no STATS captured)"
