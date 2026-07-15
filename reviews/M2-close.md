# Review — M2 Close (macOS host)

**Status:** M2.1 and M2.2 complete. M2.3 partially met — two acceptance criteria cannot be met
as written, both for reasons outside the host pipeline, both escalated below rather than worked
around. `check.sh` green in `host/` and `client/`.
**Scope:** ScreenCaptureKit capture, VideoToolbox encode, full-Mac loopback measurement.

---

## 1. Decisions taken (asked before building)

| Decision | Chosen | Note |
|---|---|---|
| Rust ↔ ScreenCaptureKit | **objc2 crates**, not an ObjC shim | SCK is public and fully bound; `SCStreamErrorCode::UserDeclined` is a typed constant, so the TCC failure is a match arm. The shim planned for M6.3 exists because CGVirtualDisplay is *private* — that reason doesn't transfer |
| Capture pixel format | **`420v` (NV12)** from SCK | GPU does RGB→YUV; `nv12.rs` only splits chroma. Same BT.601 **video range** `convert.rs` produces on Linux — `420f` would not match |
| Capture trait | **No trait** | Backends are `cfg`-exclusive, never both compiled; nothing needs polymorphism. `loomd`'s `Source` enum is the seam. ROADMAP M2.1 says "behind the trait", but that trait never existed |
| Encode ≤ 6 ms at 1440p | **Record the floor, escalate §10** | See §4 |
| 1440p e2e | **Fix client freshness; report 720p** | See §4 |

---

## 2. What changed

| Repo | Change | Why |
|---|---|---|
| host | target-gate the portal path (`3bbc28c`) | M1.4 broke the Mac build outright: unconditional `ashpd`/`pipewire` deps |
| host | ScreenCaptureKit capture (`183b9f4`, `63ba541`) | M2.1 |
| host | VideoToolbox encode + `annexb` (`2d3251d`, `577db97`) | M2.2 |
| host | NV12 input + `encode_us` instrumentation (`9ef1753`) | M2.3; see §3 |
| client | cap the decoder hand-off at 2 AUs (`d0ead0e`) | M2.3; see §4.2 |

---

## 3. Measured (loopback, idle machine, SCK + VideoToolbox unless noted)

| Config | encode mean | e2e | note |
|---|---|---|---|
| 720p72 | **3.15 ms** | **11 ms** | passes both budgets |
| 1440p72 | **8.69 ms** | 82 ms | encode over budget; e2e client-bound (§4.2) |
| 1440p72, synthetic source | 10.24 ms | — | capture is not the cost — identical to live capture |
| 720p72, x265 (M1 baseline) | 5.95 ms | 18 ms | |
| 1440p72, x265 | 17.13 ms | — | **also fails ≤ 6 ms**, and holds only 64 fps |

- **IDR recovery, real VideoToolbox path: 13.7 ms** (budget 200 ms) — `videotoolbox_freeze_idr_request_recovery_under_200ms`.
- **30-min soak, 720p72:** 129,678 frames = **72.0/s**, encode 3.83 ms mean, e2e **18 ms with no drift**,
  RSS **50.0 → 50.3 MB** (+0.4 MB), 0% loss. M1.5's soak criterion met.
- **§5 conformance:** the M1 reference parser (ffprobe/libavcodec) passes on VideoToolbox output —
  no B-frames, IDRs only at `[0, forced]`, VPS/SPS/PPS per IDR (which proves `loom-encode`'s
  injection, since VT emits none in-band).

### Why encode is 8.69 ms and not less

Chased rather than reported. **Not** the flush (per-frame tagged latency without it: 8.98 ms),
**not** the I420 round-trip (own memcpy: 0.11 ms), **not** a software fallback
(`RequireHardwareAcceleratedVideoEncoder` changes nothing: 10.71 vs 10.95), **not** QoS (flat
across all four classes), **not** rate-coupled (flat 30→240 fps `ExpectedFrameRate`).

What *was* recoverable: feeding the engine planar `y420` made VideoToolbox convert to NV12
internally — **inside** the encode, invisible to a caller timing its own copy. Fixed: **10.21 →
8.69 ms**.

The remaining ~8.4 ms is the engine's per-frame latency **under §5.3**. Warm-pipe measurement:
latency 8.43 ms, throughput 118 fps — *equal*, i.e. only one frame is ever in flight, because
single-reference with no reordering makes frame N depend on N-1. The encoder is a serial chain by
construction. (ffmpeg reaches 176 fps at 1440p precisely because it is unconstrained —
multi-reference, reordering allowed — so it is not a comparable number.)

Incidental: `EnableLowLatencyRateControl` is **load-bearing for §5.3**, not just latency —
without it `ReferenceBufferCount` is rejected outright and single-reference is unachievable.

---

## 4. Not met — escalations

### 4.1 Encode ≤ 6 ms at 1440p72 (ROADMAP M1.5, inherited by M2.3)

**Measured floor: 8.69 ms.** Not reachable on this hardware (§3). x265 fails the same criterion at
17.13 ms, so nothing on this Mac has ever met it — the figure is NVENC-shaped.

**ARCHITECTURE §10 claims "3–6 ms" for "NVENC / VideoToolbox low-latency". That claim is false for
VideoToolbox on an M4 Max at 1440p.** `spec/` is read-only here, so this is a spec correction for
the human to make. Note the *stage* budget is blown while the *total* ≤ 45 ms may still close.

Open question: the NVENC 5 ms figure it is being compared against has no recorded provenance —
nothing measured encode time on either host until `encode_us` (`9ef1753`). That counter is
encoder-agnostic and lands in `frame_sent`, so **running the same measurement on the Linux box
would settle it like-for-like** and give M1.5 the encode evidence it never had. Throughput and
latency differ by ~1.5× here, so it matters which one 5 ms is.

### 4.2 e2e ≤ 45 ms at 1440p72

**Not the host.** The SDL client decodes in software (`sdl/src/decoder.cpp:13`,
`avcodec_find_decoder` with no hwaccel) and sustains **59.4 fps against 72**, with decode at
7.1 ms/frame. M1-close.md documented this backlog; the M2 brief's claim that the client "decodes
natively with VideoToolbox" does not hold for the current code.

Fixed what was defensible: the decoder hand-off was **unbounded**, so the deficit surfaced as
4300 ms of silently growing latency reporting 0% loss. Now capped (`d0ead0e`): **e2e 4300 → 82 ms**,
with the deficit visible as **84.6% loss at 4.5 fps** — the §3.6 IDR floor, i.e. a keyframe
slideshow. 720p improved too: **18 → 11 ms at 0% loss**.

This bounds the latency; it does not make 1440p work. **Only client hardware decode does** — M3.2's
territory. Until then 720p is the measured configuration.

### 4.3 Over WiFi to a second machine

Not run — no second machine available. M2.3's WiFi leg is **unmet**, loopback evidence only.

---

## 5. Carried debt

- [ ] **§5.5 (one slice per frame) is unverified for all three encoders** — M1.2's test never checked
      it; pre-existing, not new. A VCL-NAL-per-AU count would close it cheaply.
- [ ] Linux `check.sh` unrun since the Step-0 target-gating and the `media/mod.rs` cfg arms.
- [ ] Zero-copy SCK `CVPixelBuffer` → VideoToolbox: **not worth it for encode** (the copy is 0.11 ms),
      but it would still remove `nv12.rs`'s split on the capture thread. Deferred, unquantified.
- [ ] ROADMAP's M1 status line still says "M1.4–M1.5 await the Linux box"; both landed.
