# Fullscreen viewport restoration on the hostnet stack

This follow-up is layered on the Wi-Fi/Bluetooth/startup-progress feature
commit `e24a3d0`, based on `codex/native-opengl-hdr`. It restores the earlier
Cocoa fullscreen padding patch; it does not replace the hostnet implementation.

## Geometry

Normal app launches enable clean fullscreen geometry unless
`OMARCHY_COCOA_CLEAN_FULLSCREEN=0` is supplied explicitly. The runtime rounds
fullscreen backing height down to a multiple of 16, with fewer than 16 unused
rows. A 4112×2582 backing area therefore advertises and renders 4112×2576.
Windowed output is unchanged. Rendering, absolute mouse coordinates and host
cursor placement use the same effective height. Guest monitor rules still
need to match that viewport; no user configuration is overwritten.

## Source reproducibility

The upstream VirGL v1.0.42 tag moved away from the previously verified source.
The first fresh runtime attempt correctly rejected the changed archive. The
build now uses the original commit `63d8574e05af478cb14215c2401d7033050bb221`
through its immutable archive URL. All 52 source entries were compared with
the previously qualified archive, including modes, links and file contents;
the source tree is unchanged. The archive checksum and extraction root were
updated together and validated by another full runtime source build.

## Local qualification

- Full pinned runtime rebuild: passed; 17 self-contained Mach-O images,
  macOS 15 compatibility checks and signature validation.
- Full signed app build: passed; 22 Mach-O compatibility checks. It bundles the
  exact branch's `try-omarchy 0.1.0-35` with the existing qualified factory.
  The local networking-service override matches the installed test app.
- Standard `make test` encountered the known local `TestingMacros` lookup
  failure. All **447 Swift tests in 95 suites** passed with the documented
  explicit plug-in directory; every remaining group passed with
  `make -o test-swift -j4 test-all`.
- Compiled viewport tests passed for 4112×2582 → 4112×2576, already clean
  heights, disabled/windowed cases, the minimum-size guard and 7,585 heights.
  App launch tests verify default-on and the explicit diagnostic override.
- Real native OpenGL HDR shader and Cocoa FP16-layer tests passed, including
  paired desktop white, PQ values, gamma, orientation and ten-bit input.
- Runtime cache tests, shell syntax and `git diff --check` passed.

The combined app's windowed disposable E2E run passed **97 checks, 0 failed,
11 notes in 190 seconds**, with `0.1.0-35` installed through the normal boot
path. Both boots reported the packaged `0.56.2-7.323` compositor, selected DKMS
driver, ten-bit `hdredid` output and reference 100. Hostnet was active, Mac GPU
VirGL rendering passed, and shutdown, persistence and the second desktop
passed. The Wi-Fi and Bluetooth panel services were inactive notes in this
synthetic owner session; this is not a repeat of the original paired-device
interaction verification.

The working VM was not restarted during preparation. A live fullscreen
backing/drawable measurement and the user's text-artifact comparison remain
post-install checks. Windowed disposable tests do not establish fullscreen
text quality or physical presentation cadence. Paired Bluetooth actions from
the original feature were not repeated as part of this rendering-only change.
