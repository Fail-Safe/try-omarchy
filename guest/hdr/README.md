# HDR guest compatibility patches

These are review inputs for the opt-in native OpenGL HDR prototype, not factory
package integration. The ordinary factory remains SDR. See
[the host prototype](../../docs/native-opengl-hdr.md) for the tested boundaries.

`virtio-gpu-hdr.patch` targets Linux 7.2.5's DRM virtio driver. The companion
manifest records the unmodified source files under
`https://raw.githubusercontent.com/gregkh/linux/v7.2.5/drivers/gpu/drm/virtio/`.
It adds ten-bit formats, BT.2020/PQ connector properties, and the private HDR
command paired with the QEMU patch. The interface follows the earlier HDR work
in [PR #168](https://github.com/omacom/try-omarchy/pull/168); this draft changes
host presentation to native Apple OpenGL.

The tested persistent guest used `7.2.5-1-aarch64-ARCH` with the module in
`updates/omarchy-hdr/virtio-gpu.ko`. This patch must be reviewed and rebuilt for
the factory's exact kernel, with matching headers, packaging, initramfs and
source pins. Do not install that persistent guest's module into another kernel.
That factory integration and fresh factory boot are not complete in this draft.

`../patches/hyprland/client-sdr-white.patch` makes output and preferred-surface
image descriptions advertise the monitor's SDR-white policy. It preserves the
internal HDR render description, peak luminance, and SDR/ICC behavior. The patch
was built and tested with Hyprland 0.56.1/Aquamarine 0.14.0, and applies cleanly
to the pinned 0.56.2 source (that version has not been rebuilt with it). The ordinary guest
package pins and reproducible binary checksum are deliberately unchanged;
factory registration requires rebuilding and revalidating the pinned package.

Guest display helpers must honor the `TO-SDR:<nits>` EDID hint instead of
forcing a white level calibrated for a previous presenter. Per-output monitor
rules take precedence over catch-all rules. Compare the actual monitor policy
with the reference white received over Wayland, then verify ordinary app whites
and HDR streams separately. Both are required for a useful HDR desktop.

## Later local brightness corrections

The host now advertises a paired **100-nit encoding reference** in HDR mode.
The guest monitor SDR maximum and client reference must both use 100 for this
contract. This supersedes the historical 600-nit local configuration; it does
not mean the panel can only produce 100 nits.

`../patches/hyprland/hdr-content-peak.patch` targets Hyprland 0.56.2 and uses
MaxCLL, then mastering peak, for PQ tone-mapping decisions rather than treating
PQ's 10,000-nit encoding range as the content peak. Missing content metadata
retains the previous fallback. It was built with the client-white correction
and deployed locally as 0.56.2-7.322; package pins and factory integration in
this draft remain unchanged.

`mpv-wayland-opengl-color-description.patch` is an isolated diagnostic-player
patch against mpv 0.41.0. With `MPV_WAYLAND_OPENGL_COLOR_MANAGEMENT=1`, it lets
gpu-next/Wayland OpenGL explicitly describe its PQ surface. Stock mpv in this
test rendered PQ but left its surface unlabelled, so the compositor interpreted
it as sRGB. This is a review/reproduction input, not a replacement system mpv.

On the tested Vivaldi build, `--enable-features=UseDisplaySDRMaxLuminanceNits`
prevented an additional 100/203 scaling of PQ video. This was verified with
HDR10 VP9 profile 2 and ordinary SDR white; HLG and AGTM were not qualified.
No factory browser flag is installed by this PR. See the
[brightness measurements](../../docs/evidence/native-opengl-hdr-brightness.md).
