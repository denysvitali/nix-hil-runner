# Contributing

## Requirements

Nix with flakes enabled (`experimental-features = nix-command flakes` in
`nix.conf`). No other tooling required; everything is pinned by the flake.

## Building

Native on aarch64:

```bash
nix build .#packages.aarch64-linux.image
```

Cross-compile from x86_64:

```bash
nix build .#packages.x86_64-linux.image
nix build .#packages.x86_64-linux.update-package
```

Fast eval-only checks (no build):

```bash
nix flake check --no-build
```

## Coding conventions

- Each file under `modules/*.nix` owns one responsibility. See the module map
  in `CLAUDE.md` before adding a new one — extend an existing module if it
  fits.
- Runtime configuration (runner URL, token, labels, hostname, SSH keys) lives
  on `/perm` and is consumed by services at start. It is **not** part of the
  NixOS configuration. Do not bake per-device values into the image.
- The hostname is set via `lib.mkDefault "hil-runner"` so `hostnamectl
  set-hostname` works at runtime without rebuild conflicts. Preserve this
  pattern for any other runtime-mutable setting.

## Commits and branches

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(scripts): add hil-rollback
fix(sysupdate): correct partition GUID
```

Branch names use `type/what`, e.g. `feature/rollback-script`,
`fix/perm-sync-race`. Only create a feature branch when explicitly asked;
otherwise commit to `master`.

## Testing on hardware

Flash the built image to an SD card:

```bash
gzip -dc result/*.raw.gz | sudo dd of=/dev/sdX bs=4M conv=fsync
sync
```

Boot the Pi, then SSH in with the first-boot credentials:

```bash
ssh root@<pi-ip>   # password: root
hil-setup
```

The wizard writes `/perm/*` and reboots into hardened mode.

To reset the device for another round of testing:

```bash
sudo rm /perm/configured && sudo reboot
```

This drops the device back into first-boot mode without reflashing.

## CI

The release pipeline lives in `.github/workflows/release.yml`. Pushing to
`master` triggers a build and auto-tags the commit using CalVer; the
resulting `image` and `update-package` artifacts are attached to the
GitHub Release.
