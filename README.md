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

### Optional secrets

| secret | purpose |
|---|---|
| `TS_AUTHKEY` | non-interactive tailnet join |
| `VNC_PASSWORD` | fixed legacy VNC pw (random per-run otherwise) |
| `VNC_USER_PASSWORD` | fixed `vncuser` pw (random per-run otherwise) |

## Notes

- The `runner` user is auto-logged-in on the console, so VNC shows a live
  desktop, not a lock screen.
- `runner` has passwordless sudo. SecureToken means you can't reset its
  password, hence `vncuser`.
- VNC password is truncated to 8 chars by the legacy auth scheme.
- macOS VMs on GH runners are themselves VMs — no nested Hypervisor.framework.
- ToS note: Actions on public repos is free but meant for "production, testing,
  deployment, or publication" of software. Keep it honest-ish.
