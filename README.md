# NiceOS

> ⚠️ **Early Development Warning**
> NiceOS is in very early stages and does not yet live up to its intended purpose.
> Large parts of this project are vibe-coded and may break in unexpected ways.
> Use at your own risk, and expect things to change dramatically.

---

NiceOS is a pre-configured NixOS framework that aims to make NixOS as easy and friendly to use as possible — batteries included, sensible defaults, and a one-command install.

The goal is that anyone comfortable with Linux can install NiceOS and get a beautiful, functional desktop without having to understand the Nix language.

## Requirements

- A working NixOS installation
- `git`
- An internet connection

## Install

```bash
curl -sSL https://raw.githubusercontent.com/IceCubeMaker/NiceOS/main/core/scripts/install.sh | bash
```

After install, your config lives at `/etc/nice-configs/configuration.nix`. Edit it with sudo and run `rebuild` to apply changes.

## Commands

| Command | Description |
|---|---|
| `rebuild` | Commit and rebuild the system |
| `rebuild --turbo` | Rebuild using all CPU cores |
| `niceos-install` | Re-run the installer |