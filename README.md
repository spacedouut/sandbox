# sandbox

Playing with what you can squeeze out of GitHub's free Apple Silicon CI VMs
(`macos-14`/`macos-15`/`macos-26` = arm64 macOS on Apple Silicon).

## macos-vm workflow

Dispatch it from Actions → `macos-vm` → Run workflow. Options:

- **runner**: which macOS image (all arm64; `macos-13` is the only Intel one)
- **minutes**: keep-alive time (GitHub-hosted jobs hard-cap at ~6h)
- **enable_ssh**: turns on Remote Login, installs your
  [GitHub ssh keys](https://github.com/spacedouut.keys) into `runner`'s
  `authorized_keys`
- **enable_vnc**: enables Screen Sharing, sets a legacy VNC password, creates an
  admin `vncuser` (for Apple Screen Sharing auth)
- **enable_sunshine**: installs [Sunshine](https://app.lizardbyte.dev/Sunshine)
  via the LizardByte Homebrew tap and runs it as a LaunchAgent under `vncuser`
  — connect with any Moonlight client for a hardware-H.264/HEVC stream that is
  *dramatically* faster than VNC (the paravirtualized AVE media engine does the
  encoding; see Notes)
- **benchmark**: networkQuality, openssl throughput, disk dd, all-core burn

### Access

The runner joins your tailnet. Either:

- set repo secret **`TS_AUTHKEY`** (reusable, ideally ephemeral+tagged), or
- leave it unset — the log prints a `https://login.tailscale.com/a/…` URL; open
  it to approve the node.

Then, from any tailnet device:

```sh
tailscale status              # find gh-macos-<run_id>
ssh runner@<100.x.y.z>
open vnc://<100.x.y.z>:5900   # legacy VNC password or vncuser creds are in the logs
```

**Sunshine/Moonlight** (recommended — hardware-encoded, feels native):

1. Moonlight → Add PC → `<100.x.y.z>` → note the 4-digit PIN
2. Open `https://<100.x.y.z>:47990` (self-signed) → `admin` / `sunshine`
   (or `SUNSHINE_WEB_PASSWORD` if you set it) → PIN page → pair
3. Launch **Desktop**

Sunshine streams `vncuser`'s session when it has an Aqua login (keeps the
`runner` CI identity off the streamed desktop); otherwise it falls back to the
console user's session.

### Optional secrets

| secret | purpose |
|---|---|
| `TS_AUTHKEY` | non-interactive tailnet join |
| `VNC_PASSWORD` | fixed legacy VNC pw (random per-run otherwise) |
| `VNC_USER_PASSWORD` | fixed `vncuser` pw (random per-run otherwise) |
| `SUNSHINE_WEB_PASSWORD` | Sunshine web UI pw (default `sunshine`) |

## Notes

- **VNC black screen fix**: `screensharingd` doesn't have the
  *Screen & System Audio Recording* TCC grant on these images, and as a
  platform binary it can never prompt — so it serves only the menu bar +
  wallpaper (i.e. a black screen). SIP is disabled on GH runners, so the
  workflow writes grants straight into `TCC.db` (`screensharingd`,
  `ScreensharingAgent`, `ARDAgent`, plus `sshd-keygen-wrapper` which is the
  TCC "responsible binary" for anything spawned over SSH, and `screencapture`).
- The `runner` user is auto-logged-in on the console, so VNC shows a live
  desktop. `runner`'s password can't be changed (SecureToken) — if the console
  ever shows a lock screen, `vncuser`'s password is yours to set via `dscl`.
- The runner is a `VirtualMac2,1` (Apple Virtualization.framework, Anka-hosted),
  3 cores, ~7 GB RAM, black stock wallpaper.
- **No real GPU**: no `AGX` kexts, no `AppleDisplay`, the only display is a
  legacy VGA-class PCI framebuffer. `Metal` sees an "Apple Paravirtual device"
  stub (~15 MB VRAM, zero feature families, ~CPU-speed compute). All
  compositing is software — that's why VNC is slow.
- The console framebuffer only exposes a few modes (≤1344x1008) —
  `resolution` input uses `displayplacer`.
- `CGVirtualDisplay` (private API à la BetterDisplay) fails to instantiate —
  likely entitlement-gated — so a second virtual display isn't a path.
- **But the media engine is real**: `pci106b,1a03` is a virtio function driven by
  `AppleVideoToolboxParavirtualization` — guest VT calls execute on the *host*'s
  AVE hardware. Verified: H.264 enc ~370fps / dec ~590fps @720p, plus
  `IsHardwareAccelerated` HEVC and even JPEG (`ajpeg`) encoders. There's also
  `pci106b,1a08` = `AvpFairPlayDriver` (FairPlay DRM passthrough).
  Encode/decode is a job-queue interface so it's trivially virtualized; the 3D
  GPU is deeply stateful, which is why it's only a stub.
- The `pci106b,1a0x` family is the standard Apple Virtualization.framework
  device set (block, platform, video, USB, fairplay, guest-agent messenger).
- The missing-GPU thing is a *host-side choice*, not a platform limit:
  `VZMacGraphicsDeviceConfiguration` + Paravirtualized Graphics give macOS
  guests real Metal acceleration (WWDC22; Anka enables it by default on ARM,
  tart works "with no additional setup"). GitHub's runtime just doesn't offer
  the accelerated device — presumably deliberate on a shared CI fleet.
- macOS 15 `kTCCServiceScreenCapture` checks the **per-user** `TCC.db`
  (`~/Library/Application Support/com.apple.TCC/TCC.db`), not just the system
  one — grants must land in both or daemons still prompt. The setup script
  writes to both.
- VNC password is truncated to 8 chars by the legacy auth scheme.
- ToS note: Actions on public repos is free but meant for "production, testing,
  deployment, or publication" of software. Keep it honest-ish.
