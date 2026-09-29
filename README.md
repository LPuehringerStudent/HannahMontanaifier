# HannahMontanaifier

Prank software: a script that makes any Linux distro look like it was wiped and
replaced with Hannah Montana Linux.

## Usage

Boot the target machine from a live USB (or use
[FishFish](../FishFish) for fully automatic injection), mount the victim root
filesystem, and run as root:

```bash
./hannahmontanaify.sh /mnt/target
```

To try it on the machine you're sitting at, with no USB and no mounting, use the
live wrappers (they theme the running system and are fully reversible):

```bash
sudo ./test-live.sh        # apply to this booted system
sudo ./restore-live.sh     # undo
```

What it changes (everything is backed up and reversible — user data is never
touched):

- `/etc/os-release`, `/etc/lsb-release`, `/etc/issue` → "Hannah Montana Linux 26"
- hostname → `hannahmontana` (updates `/etc/hosts` too, sudo keeps working)
- GRUB menu entries + background image (rebuilds `grub.cfg` via `update-grub`)
- Plymouth boot splash → `hannah-montana` theme (rebuilds initramfs)
- Login screen: LightDM slick-greeter / SDDM / GDM greeter (logo, banner, icons;
  GDM background via `test-live.sh`) + HML login background
- Per-user: HML fastfetch config + ASCII logo, `.face` avatar, wallpaper and
  `HannahMontana` icon theme via dconf (Cinnamon / MATE / GNOME)
- System-wide: HML26 icon themes, Plasma 6 global themes, color schemes,
  wallpapers

The script refuses to touch a filesystem that already reports `ID=hml`, so the
real Hannah Montana Linux dual-boot partition is left alone.

Environment knobs: `HML_HOSTNAME=` (empty = keep hostname),
`HML_SKIP_USERS=1` (skip per-user changes).

### Undo

```bash
sudo hannahmontanaifier-restore   # on the booted system
```

Restores every original file from `/var/backups/hannahmontanaifier/`, removes
all installed assets, reverts the boot splash and GRUB config, and resets the
dconf wallpaper/icon overrides. Tested end-to-end against a mock Mint root.

### FishFish integration

Copy `hannahmontanaify.sh` + `assets/` next to FishFish's `src/fishfish/`
payload (or symlink `payload.sh` to `hannahmontanaify.sh`). FishFish calls the
payload once per mounted filesystem with `FF_MOUNTPOINT` set; the script runs
standalone exactly the same way. Keep `HALT_ON_LUKS=true` — the prank can't
(and shouldn't) touch encrypted roots. Use FishFish's `TARGET_FILTER` with the
Mint partition's UUID so only the intended filesystem gets glittered.

## Assets

`assets/` contains the official theme assets from **Hannah Montana Linux v26.0**
(the modern Debian-based remaster by Noah Cagle), pulled from
<https://gitlab.com/DecaCagle/hannahmontanalinux26> and licensed GPLv3+
(see `assets/LICENSE`).

Layout:

- `assets/images/` — raw artwork (wallpapers, GRUB backgrounds, logo, Calamares
  installer slides, panel backgrounds, start-here icons in 48/64/128 px)
- `assets/system/` — drop-in filesystem mirror of the v26 theme payload:
  - `usr/share/plasma/look-and-feel/org.hml{,dark}.desktop` — Plasma global themes
  - `usr/share/plasma/desktoptheme/hannah-montana-theme{,-dark}` — Plasma styles
  - `usr/share/icons/HannahMontana{,Dark}` — icon themes
  - `usr/share/color-schemes/` — KDE color schemes
  - `usr/share/sddm/themes/hannah-montana-sddm` — login screen theme
  - `usr/share/plymouth/themes/hannah-montana` — boot splash
  - `usr/share/desktop-base/hannah-montana-theme` — wallpaper/login/lockscreen/GRUB set
  - `usr/share/wallpapers/HannahMontanaTheme` — wallpaper package
  - `etc/os-release`, `etc/sddm.conf.d/`, `etc/xdg/kcm-about-distrorc`,
    `etc/skel/` — OS identity + default user config (fastfetch etc.)
  - `etc/calamares/branding/hannah-montana-linux` — installer branding/slideshow
- `assets/isolinux/` — boot menu splash
