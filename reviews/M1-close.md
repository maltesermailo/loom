# Review — M1 Close (STEP 4)

**Status:** Complete. Clean clones of both repos pass `check.sh` end to end; the loopback demo
prints live overlay numbers; format gates added; ready for the ROADMAP tick + `sync.sh record`.
**Scope:** verification + demo + closing housekeeping for M1.1–M1.3. No new protocol behavior.

---

## 1. Decisions taken (asked before building)

| Decision | Chosen | Note |
|---|---|---|
| Demo layout | **Superrepo orchestrator + thin per-repo demo.sh** | `scripts/demo.sh` (super) drives `host/` + `client/` halves |
| Demo resolution | **loomd `--width/--height`, demo at 1280×720** | 720p software decode keeps up → stable low e2e |
| Numbers source | **loom-sdl prints its overlay line to stdout 1/s** | includes bitrate (STATS omits it); works headless |

---

## 2. What changed

| Repo | Change | Why |
|---|---|---|
| host | `loomd --width/--height` (`5dfdf4b`) | demo streams a decode-friendly size; defaults stay 1440p |
| host | `scripts/demo.sh` + `cargo fmt --all --check` gate (`02cb601`) | build+launch loomd; formatting can't regress |
| host | rustfmt the whole workspace (`cc5dbb9`) | check.sh never enforced fmt; made it clean |
| client | `loom-sdl` 1/s overlay stdout + `scripts/demo.sh` + clang-format gate (`54fead4`) | surface numbers headless; enforce format |
| super | `scripts/demo.sh` orchestrator | the loopback demo |

---

## 3. Verification

- **Clean clone → check.sh (both repos).** Fresh `git clone` of each repo into `/tmp` (spec submodule
  sourced from the local spec repo, `protocol.file.allow=always`), then `./check.sh`:
  - host: `[1/4] fmt · [2/4] test · [3/4] clippy · [4/4] vectors` → **ALL CHECKS PASSED**
  - client: `[1/4] clang-format · [2/4] build · [3/4] ctest · [4/4] vectors` → **ALL CHECKS PASSED**
- **Loopback demo (`scripts/demo.sh`).** loomd streams the synthetic pattern to loom-sdl at 720p; after
  10 s the captured numbers agree across both sides:
  - client overlay: `e2e 16 ms  rtt 7 ms  decode 1.9 ms  loss 0.00%  bitrate 15048 kbps`
  - host STATS: `frames_received:73  frames_dropped:0  datagrams:1439  jitter_ms:3.7  decode_us:2224  rtt_us:7684  e2e_us:18122`
  - `frames_received≈73`/s ≈ 72 fps, 0% loss, e2e ~18 ms stable — confirms the M1.3 backlog was
    resolution-bound (720p decode keeps up).

---

## 4. Notes

- The format gates were added after finding the host Rust was never rustfmt-checked (check.sh ran
  test+clippy only). The client clang-format gate skips with a warning if clang-format is absent, so
  the gate stays "runs anywhere".
- The superrepo/host/client `spec` gitlinks are all current at `ae29ceb`.

---

## 5. Remaining close steps (this step, pending your input)

1. **ROADMAP tick** — spec is read-only, so the exact edit is presented for approval before applying.
2. **`sync.sh record`** — record the updated host/client (and spec, after the tick) gitlinks in the
   superrepo.
