# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A reversible theming tool. `hannahmontanaify.sh` rebrands a mounted Linux root filesystem as Hannah Montana Linux 26: OS identity files, hostname, GRUB, Plymouth, the LightDM/SDDM login screen, icon themes and wallpapers, plus per-user fastfetch/avatar/dconf settings. There is no build step and no test suite — the only code is one POSIX `sh` script; everything else under `assets/` is theme payload copied from the upstream HML v26 project.

## Running

```sh
sudo ./hannahmontanaify.sh /mnt/target          # target = a mounted root filesystem
HML_HOSTNAME= HML_SKIP_USERS=1 sudo ./hannahmontanaify.sh /mnt/target
```

The target root comes from arg 1 or, in FishFish payload mode, from `FF_MOUNTPOINT` (FishFish invokes the script once per mounted filesystem). Test against a throwaway mock root directory rather than a live system. Undo on a booted target with `sudo hannahmontanaifier-restore`.

### Live testing on the running machine (no USB)

`test-live.sh` / `restore-live.sh` in the repo root apply and undo the prank on the *currently booted* system, for quick testing without a live USB:

```sh
sudo ./test-live.sh      # -y skips the confirmation prompt
sudo ./restore-live.sh
```

`test-live.sh` runs the main script against `/` with `HML_SKIP_CHROOT=1` (the main script's chroot/bind-mount block is meant for an offline mounted target and would self-bind `/dev /proc /sys /run` onto themselves against a live `/`), then does the target's-own-userland steps directly on the host: `update-grub`, `plymouth-set-default-theme -R hannah-montana`, `dconf update` for the GDM greeter, and a live wallpaper/icon switch in the invoking user's session (`sudo -u "$SUDO_USER"` with `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus`). It also swaps a background into GNOME Shell's theme gresource — see below.

Lint changes with `shellcheck hannahmontanaify.sh` (note: the script targets `/bin/sh`, not bash).

## Architecture

Everything operates on `$TARGET` — the mounted root of the *victim* filesystem — never on paths relative to `/` on the running machine. Every path passed around internally (in `bcp`, `put`, `puttree`, `track`) is relative to `$TARGET`; only the generated restore script uses absolute `/` paths, because it runs later on the booted target.

Key invariants to preserve when editing:

- **Idempotency / safety guard**: the script exits early if `$TARGET/etc/os-release` already reports `ID=hml`, so it never re-pranks the real HML partition or a system it already touched.
- **Reversibility contract**: any change to an *existing* file must first call `bcp` (backs the original up to `$BACKUP/files`, mirroring its absolute path). Any *newly created* file must be registered with `track` (appended to `$BACKUP/installed.list`). Use the `put`/`puttree` helpers, which already do the right one based on whether the destination exists; before writing a file directly (`printf >`, `sed -i`), call `claim <relative path>`, never a bare `bcp` — `bcp` is a no-op for files that don't exist yet, so a newly created file would be left behind on restore. `claim` also replaces a symlinked destination (e.g. Debian/Mint's `/etc/os-release -> ../usr/lib/os-release`) with a regular file so writes never go through into a package-owned file; the restore kit restores symlink backups as links. Parent directories that `claim`/`puttree` create are recorded in `$BACKUP/dirs.list` (via `mkparents`) and `rmdir`'d deepest-first on restore, so only still-empty ones go. The restore script consumes both: it copies backed-up files back and deletes tracked files. Breaking this pairing makes the prank non-reversible.
- **Feature detection**: each subsystem is gated on the target actually having it (e.g. `[ -d "$TARGET/etc/lightdm" ]`, `[ -e "$TARGET/usr/bin/sddm" ]`, `[ -d "$TARGET/etc/gdm3" ]`). KDE/Plasma assets are installed unconditionally but are harmless on other desktops.
- **Display-manager theming**: LightDM (slick-greeter) and SDDM are themed with plain config files. GDM is split in two: the main script writes `/etc/gdm3/greeter.dconf-defaults` (logo, banner, icon-theme — reversible via the normal backup machinery), but GDM's login *background* can only be set inside GNOME Shell's compiled `gnome-shell-theme.gresource`, so that swap lives in `test-live.sh` only (it needs `gresource`/`glib-compile-resources` and is version-fragile). The gresource swap backs up the original to `/var/backups/hannahmontanaifier/gnome-shell-theme.gresource.orig`; `restore-live.sh` copies it back *before* invoking the restore kit, because the kit deletes that backup dir on exit.
- **State captured for restore**: `$OLD_PLYMOUTH_THEME` (read from the target's plymouth config, defaulting to `bgrt`) and `$OLD_HOSTNAME` are captured before overwriting and interpolated into the heredoc that writes `/usr/local/sbin/hannahmontanaifier-restore`. When editing that heredoc, mind which `$`/backslashes are escaped: unescaped ones expand now (install-time values), escaped `\$` ones are literal and expand when the restore script runs.
- **Chroot section**: `update-grub`, `plymouth-set-default-theme`, and `update-initramfs` need the target's own userland, so they run via `chroot "$TARGET"` after bind-mounting `/dev /proc /sys /run`; binds are tracked in `$BINDS` and always unwound with `undo_binds`. Where `plymouth-set-default-theme` doesn't exist (Ubuntu/Mint), the splash is chosen by the `default.plymouth` alternative: the theme is registered and `--set` there (in the chroot, or by `test-live.sh` live), and the restore kit `--remove`s it and re-`--set`s the original only if it was in manual mode (`$OLD_PLY_ALT_MODE`/`$OLD_PLY_ALT`). All chroot calls are best-effort (`|| warn`, non-fatal) so a target without those tools still gets themed.
- **Per-user changes**: `install_user_stuff` and `dconf_wallpaper` iterate real users (uid ≥ 1000 with an existing home) from `$TARGET/etc/passwd`; the same skel files are also installed into `/etc/skel` for future users. `dconf_wallpaper` picks Cinnamon/MATE/GNOME gsettings keys by detecting the DE binary and only runs with a working chroot. Before overwriting any gsettings key, save its current value to `$BACKUP/gsettings/<user>` as `schema key value` lines (`dconf_wallpaper` does this in the chroot, `test-live.sh` for the live session); the restore kit and `restore-live.sh` replay that file with `gsettings set`, falling back to `gsettings reset` only when no saved copy exists.
