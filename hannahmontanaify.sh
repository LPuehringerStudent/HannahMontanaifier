#!/bin/sh
# hannahmontanaify.sh — prank payload: make an existing Linux install look and
# feel like Hannah Montana Linux 26 (without touching any user data).
#
# Usage:
#   ./hannahmontanaify.sh /mnt/target        # from any live USB, as root
#   FishFish payload mode: runs automatically per mounted filesystem using
#   the FF_* environment (FF_MOUNTPOINT etc.).
#
# Everything is reversible: originals are backed up to
# /var/backups/hannahmontanaifier/ on the target and a restore script is
# installed at /usr/local/sbin/hannahmontanaifier-restore.
#
# Optional env knobs:
#   HML_HOSTNAME=hannahmontana   # new hostname; set empty to skip renaming
#   HML_SKIP_USERS=1             # skip per-user changes (fastfetch, avatar, wallpaper)
#   HML_SKIP_CHROOT=1            # don't chroot the target to rebuild GRUB/initramfs/dconf
#                                # (use when TARGET is the running "/" — see test-live.sh)

set -u

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ASSETS="$SELF_DIR/assets"
SYS="$ASSETS/system"
TARGET="${1:-${FF_MOUNTPOINT:-}}"
HML_HOSTNAME="${HML_HOSTNAME-hannahmontana}"

log()  { printf '[hml] %s\n' "$*"; }
warn() { printf '[hml] WARNING: %s\n' "$*" >&2; }
die()  { printf '[hml] ERROR: %s\n' "$*" >&2; exit 1; }

[ -n "$TARGET" ] || die "no target given (arg 1 or FF_MOUNTPOINT)"
TARGET="${TARGET%/}"
[ -d "$TARGET/etc" ] || die "$TARGET does not look like a Linux root filesystem"
[ -d "$SYS" ] || die "assets not found at $SYS (run from the HannahMontanaifier repo)"

# Don't re-prank the real Hannah Montana Linux partition (e.g. the legacy
# dual-boot install) or an already-pranked system.
if grep -q '^ID=hml' "$TARGET/etc/os-release" 2>/dev/null; then
    log "$TARGET already is Hannah Montana Linux — nothing to do. Sweet niblets."
    exit 0
fi

BACKUP="$TARGET/var/backups/hannahmontanaifier"
FILES="$BACKUP/files"          # mirrors absolute paths of overwritten originals
INSTALLED="$BACKUP/installed.list"  # newly created files (deleted on restore)
mkdir -p "$FILES"
: >> "$INSTALLED"

# bcp <absolute path> — back up an existing target file before overwriting it.
bcp() {
    rel="${1#/}"
    if [ -e "$TARGET/$rel" ] && [ ! -e "$FILES/$rel" ]; then
        mkdir -p "$FILES/$(dirname "$rel")"
        cp -a "$TARGET/$rel" "$FILES/$rel" 2>/dev/null || warn "backup failed: /$rel"
    fi
}

# track <relative path> — remember a newly created file for the restore script.
track() {
    grep -qxF "$1" "$INSTALLED" 2>/dev/null || printf '%s\n' "$1" >> "$INSTALLED"
}

# put <src> <dest relative path> — install a file, backing up any original.
put() {
    src="$1"; rel="$2"
    if [ -e "$TARGET/$rel" ]; then
        bcp "/$rel"
    else
        track "$rel"
    fi
    mkdir -p "$TARGET/$(dirname "$rel")"
    cp -a "$src" "$TARGET/$rel" || warn "install failed: /$rel"
}

# puttree <src dir> <dest relative dir> — install a directory tree.
puttree() {
    src="$1"; rel="$2"
    [ -e "$TARGET/$rel" ] || track "$rel"
    mkdir -p "$TARGET/$(dirname "$rel")"
    cp -a "$src" "$TARGET/$rel" || warn "install failed: /$rel"
}

log "target: $TARGET"
log "HannahMontanaifying… this is the best of both worlds."

# ---------------------------------------------------------------- themes ----
log "installing HML26 theme assets"
puttree "$SYS/usr/share/icons/HannahMontana"            usr/share/icons/HannahMontana
puttree "$SYS/usr/share/icons/HannahMontanaDark"        usr/share/icons/HannahMontanaDark
puttree "$SYS/usr/share/plymouth/themes/hannah-montana" usr/share/plymouth/themes/hannah-montana
puttree "$SYS/usr/share/desktop-base/hannah-montana-theme" usr/share/desktop-base/hannah-montana-theme
puttree "$SYS/usr/share/wallpapers/HannahMontanaTheme"  usr/share/wallpapers/HannahMontanaTheme
put     "$SYS/usr/share/color-schemes/PrettyPink.colors"     usr/share/color-schemes/PrettyPink.colors
put     "$SYS/usr/share/color-schemes/PrettyPinkDark.colors" usr/share/color-schemes/PrettyPinkDark.colors
# KDE-only bits: harmless on other DEs, glorious on Plasma.
puttree "$SYS/usr/share/plasma/look-and-feel/org.hml.desktop"       usr/share/plasma/look-and-feel/org.hml.desktop
puttree "$SYS/usr/share/plasma/look-and-feel/org.hmldark.desktop"   usr/share/plasma/look-and-feel/org.hmldark.desktop
puttree "$SYS/usr/share/plasma/desktoptheme/hannah-montana-theme"   usr/share/plasma/desktoptheme/hannah-montana-theme
puttree "$SYS/usr/share/plasma/desktoptheme/hannah-montana-theme-dark" usr/share/plasma/desktoptheme/hannah-montana-theme-dark
puttree "$SYS/usr/share/sddm/themes/hannah-montana-sddm" usr/share/sddm/themes/hannah-montana-sddm

# Convenience wallpaper copies (neutral location, referenced by greeter/dconf).
put "$SYS/usr/share/desktop-base/hannah-montana-theme/wallpaper/contents/images/1920x1080.png" \
    usr/share/backgrounds/hannahmontanaifier/wallpaper.png
put "$SYS/usr/share/desktop-base/hannah-montana-theme/login/background.png" \
    usr/share/backgrounds/hannahmontanaifier/login.png
put "$SYS/usr/share/desktop-base/hannah-montana-theme/lockscreen/contents/images/1920x1080.png" \
    usr/share/backgrounds/hannahmontanaifier/lockscreen.png
put "$ASSETS/system/etc/calamares/branding/hannah-montana-linux/hml-logo.png" \
    usr/share/backgrounds/hannahmontanaifier/hml-logo.png
WALLPAPER=/usr/share/backgrounds/hannahmontanaifier/wallpaper.png
LOGO=/usr/share/backgrounds/hannahmontanaifier/hml-logo.png
LOGIN_BG=/usr/share/backgrounds/hannahmontanaifier/login.png

# -------------------------------------------------------------- identity ----
log "rewriting OS identity (os-release, lsb-release, issue)"
put "$SYS/etc/os-release" etc/os-release
if [ -e "$TARGET/etc/lsb-release" ]; then
    bcp /etc/lsb-release
    printf '%s\n' \
        'DISTRIB_ID=HannahMontana' \
        'DISTRIB_RELEASE=26.0' \
        'DISTRIB_CODENAME=montana' \
        'DISTRIB_DESCRIPTION="Hannah Montana Linux 26"' \
        > "$TARGET/etc/lsb-release"
fi
bcp /etc/issue
printf 'Hannah Montana Linux 26 \\n \\l\n\n' > "$TARGET/etc/issue"
[ -e "$TARGET/etc/issue.net" ] && bcp /etc/issue.net || track etc/issue.net
printf 'Hannah Montana Linux 26\n' > "$TARGET/etc/issue.net"

if [ -n "$HML_HOSTNAME" ]; then
    log "renaming host to '$HML_HOSTNAME'"
    OLD_HOSTNAME=$(cat "$TARGET/etc/hostname" 2>/dev/null || true)
    bcp /etc/hostname
    printf '%s\n' "$HML_HOSTNAME" > "$TARGET/etc/hostname"
    bcp /etc/hosts
    if [ -n "$OLD_HOSTNAME" ] && grep -qw "$OLD_HOSTNAME" "$TARGET/etc/hosts" 2>/dev/null; then
        sed -i "s/\\b$OLD_HOSTNAME\\b/$HML_HOSTNAME/g" "$TARGET/etc/hosts"
    else
        printf '127.0.1.1\t%s\n' "$HML_HOSTNAME" >> "$TARGET/etc/hosts"
    fi
fi

# ------------------------------------------------------------------ grub ----
if [ -e "$TARGET/etc/default/grub" ]; then
    log "theming GRUB (background + menu label)"
    put "$SYS/usr/share/desktop-base/hannah-montana-theme/grub/grub-16x9.png" boot/grub/hml-grub.png
    bcp /etc/default/grub
    sed -i '/^GRUB_DISTRIBUTOR=/d;/^GRUB_BACKGROUND=/d;/^GRUB_THEME=/d' "$TARGET/etc/default/grub"
    printf '%s\n' \
        'GRUB_DISTRIBUTOR="Hannah Montana Linux 26"' \
        'GRUB_BACKGROUND=/boot/grub/hml-grub.png' \
        >> "$TARGET/etc/default/grub"
fi

# --------------------------------------------------------------- plymouth ---
if [ -d "$TARGET/usr/share/plymouth" ] || [ -d "$TARGET/etc/plymouth" ]; then
    log "setting plymouth boot splash"
    OLD_PLYMOUTH_THEME=$(sed -n 's/^Theme=//p' "$TARGET/etc/plymouth/plymouthd.conf" 2>/dev/null | head -1)
    [ -n "$OLD_PLYMOUTH_THEME" ] || OLD_PLYMOUTH_THEME=$(sed -n 's/^Theme=//p' "$TARGET/usr/share/plymouth/plymouthd.defaults" 2>/dev/null | head -1)
    [ -n "$OLD_PLYMOUTH_THEME" ] || OLD_PLYMOUTH_THEME="bgrt"
    bcp /etc/plymouth/plymouthd.conf
    mkdir -p "$TARGET/etc/plymouth"
    printf '[Daemon]\nTheme=hannah-montana\nShowDelay=0\n' > "$TARGET/etc/plymouth/plymouthd.conf"
fi

# ------------------------------------------------------- display manager ----
if [ -d "$TARGET/etc/lightdm" ] || [ -e "$TARGET/usr/sbin/lightdm" ]; then
    log "theming LightDM greeter"
    bcp /etc/lightdm/slick-greeter.conf
    mkdir -p "$TARGET/etc/lightdm"
    printf '%s\n' \
        '[Greeter]' \
        'background=/usr/share/backgrounds/hannahmontanaifier/login.png' \
        'draw-user-backgrounds=false' \
        'icon-theme-name=HannahMontana' \
        > "$TARGET/etc/lightdm/slick-greeter.conf"
fi
if [ -e "$TARGET/usr/bin/sddm" ] || [ -d "$TARGET/etc/sddm.conf.d" ]; then
    log "theming SDDM"
    mkdir -p "$TARGET/etc/sddm.conf.d"
    [ -e "$TARGET/etc/sddm.conf.d/kde_settings.conf" ] && bcp /etc/sddm.conf.d/kde_settings.conf || track etc/sddm.conf.d/kde_settings.conf
    cp "$SYS/etc/sddm.conf.d/kde_settings.conf" "$TARGET/etc/sddm.conf.d/kde_settings.conf"
fi
# GDM's greeter reads dconf defaults from /etc/gdm3/greeter.dconf-defaults
# (Debian/Ubuntu/Mint). We can set the login logo, a banner and the icon theme
# there; it can't set a background image (that lives in the gnome-shell theme
# gresource — test-live.sh does that part on the live system).
if [ -d "$TARGET/etc/gdm3" ] || [ -e "$TARGET/usr/sbin/gdm3" ]; then
    log "theming GDM greeter (logo + banner + icons)"
    bcp /etc/gdm3/greeter.dconf-defaults
    mkdir -p "$TARGET/etc/gdm3"
    [ -e "$TARGET/etc/gdm3/greeter.dconf-defaults" ] || track etc/gdm3/greeter.dconf-defaults
    printf '%s\n' \
        '[org/gnome/login-screen]' \
        "logo='$LOGO'" \
        'banner-message-enable=true' \
        "banner-message-text='Hannah Montana Linux 26 — the best of both worlds'" \
        '' \
        '[org/gnome/desktop/interface]' \
        "icon-theme='HannahMontana'" \
        > "$TARGET/etc/gdm3/greeter.dconf-defaults"
fi

# --------------------------------------------------------------- per-user ---
# install_user_stuff <home> <uid> <gid>
install_user_stuff() {
    home="$1"; uid="$2"; gid="$3"
    put "$SYS/etc/skel/.config/fastfetch/config.jsonc"  "${home#/}/.config/fastfetch/config.jsonc"
    put "$SYS/etc/skel/.config/fastfetch/hml-ascii.txt" "${home#/}/.config/fastfetch/hml-ascii.txt"
    put "$SYS/etc/skel/.face"       "${home#/}/.face"
    put "$SYS/etc/skel/.face.icon"  "${home#/}/.face.icon"
    chown -R "$uid:$gid" "$TARGET/$home/.config/fastfetch" "$TARGET/$home/.face" "$TARGET/$home/.face.icon" 2>/dev/null || true
}

# gsettings_as <user> <chroot cmd...> — best-effort, only with a real chroot.
dconf_wallpaper() {
    user="$1"
    [ "${HML_SKIP_CHROOT:-0}" = "1" ] && return 0   # done on the live system instead
    [ -x "$TARGET/usr/bin/gsettings" ] || return 0
    cmd=""
    if [ -e "$TARGET/usr/bin/cinnamon" ]; then
        cmd="gsettings set org.cinnamon.desktop.background picture-uri 'file://$WALLPAPER'; gsettings set org.cinnamon.desktop.background picture-options 'zoom'; gsettings set org.cinnamon.desktop.interface icon-theme 'HannahMontana'"
    elif [ -e "$TARGET/usr/bin/mate-session" ]; then
        cmd="gsettings set org.mate.background picture-filename '$WALLPAPER'; gsettings set org.mate.interface icon-theme 'HannahMontana'"
    elif [ -e "$TARGET/usr/bin/gnome-shell" ]; then
        cmd="gsettings set org.gnome.desktop.background picture-uri 'file://$WALLPAPER'; gsettings set org.gnome.desktop.background picture-uri-dark 'file://$WALLPAPER'; gsettings set org.gnome.desktop.interface icon-theme 'HannahMontana'"
    fi
    [ -n "$cmd" ] || return 0
    if [ -x "$TARGET/usr/bin/dbus-run-session" ]; then
        chroot "$TARGET" su - "$user" -c "dbus-run-session -- sh -c '$cmd'" 2>/dev/null \
            || warn "dconf wallpaper failed for $user (non-fatal)"
    fi
}

if [ "${HML_SKIP_USERS:-0}" != "1" ]; then
    log "applying per-user glitter (fastfetch, avatar, wallpaper)"
    # /etc/skel for future users
    put "$SYS/etc/skel/.config/fastfetch/config.jsonc"  etc/skel/.config/fastfetch/config.jsonc
    put "$SYS/etc/skel/.config/fastfetch/hml-ascii.txt" etc/skel/.config/fastfetch/hml-ascii.txt
    put "$SYS/etc/skel/.face" etc/skel/.face

    while IFS=: read -r user _ uid gid _ home _shell; do
        case "$uid" in ''|*[!0-9]*) continue;; esac
        [ "$uid" -ge 1000 ] || continue
        [ -d "$TARGET/$home" ] || continue
        install_user_stuff "$home" "$uid" "$gid"
        dconf_wallpaper "$user"
    done < "$TARGET/etc/passwd"
fi

# ------------------------------------------------------------ chroot bits ---
# update-grub / initramfs rebuild need the target's own userland.
chrootable() { [ -e "$TARGET/bin/sh" ] || [ -e "$TARGET/usr/bin/sh" ]; }
BINDS=""
do_bind() { mount --bind "$1" "$TARGET/$1" 2>/dev/null && BINDS="$1 $BINDS"; }
undo_binds() { for b in $BINDS; do umount "$TARGET/$b" 2>/dev/null; done; }

if [ "${HML_SKIP_CHROOT:-0}" = "1" ]; then
    log "HML_SKIP_CHROOT=1 — skipping in-target update-grub/initramfs/dconf"
    log "  (rebuild boot config on the live system yourself, e.g. via test-live.sh)"
elif chrootable && [ -e "$TARGET/usr/sbin/update-grub" -o -e "$TARGET/usr/sbin/plymouth-set-default-theme" ]; then
    log "rebuilding GRUB config and initramfs inside target"
    for d in /dev /proc /sys /run; do [ -d "$TARGET$d" ] && do_bind "$d"; done
    if [ -e "$TARGET/usr/sbin/plymouth-set-default-theme" ]; then
        chroot "$TARGET" plymouth-set-default-theme -R hannah-montana 2>/dev/null \
            || warn "plymouth theme activation failed (non-fatal)"
    elif [ -e "$TARGET/usr/sbin/update-initramfs" ]; then
        chroot "$TARGET" update-initramfs -u 2>/dev/null \
            || warn "update-initramfs failed (non-fatal)"
    fi
    if [ -e "$TARGET/usr/sbin/update-grub" ]; then
        chroot "$TARGET" update-grub 2>/dev/null \
            || warn "update-grub failed (non-fatal)"
    fi
    undo_binds
else
    log "no chrootable userland (or not root) — skipping update-grub/initramfs"
fi

# ----------------------------------------------------------- restore kit ----
log "installing restore kit"
cat > "$TARGET/usr/local/sbin/hannahmontanaifier-restore" <<EOF
#!/bin/sh
# hannahmontanaifier-restore — undo the Hannah Montana Linux prank.
# Run as root on the booted system:  sudo hannahmontanaifier-restore
set -u
BACKUP=/var/backups/hannahmontanaifier
[ -d "\$BACKUP/files" ] || { echo "no backup found at \$BACKUP"; exit 1; }

echo "[restore] putting original files back"
( cd "\$BACKUP/files" && find . -type f | while read -r f; do
    rel=\${f#./}
    mkdir -p "/\$(dirname "\$rel")"
    cp -a "\$f" "/\$rel" && echo "  restored /\$rel"
done )

echo "[restore] removing prank files"
while read -r rel; do
    [ -n "\$rel" ] && rm -rf "/\$rel" && echo "  removed /\$rel"
done < "\$BACKUP/installed.list"

if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    echo "[restore] reverting plymouth theme to '$OLD_PLYMOUTH_THEME'"
    plymouth-set-default-theme -R "$OLD_PLYMOUTH_THEME" 2>/dev/null || \\
        update-initramfs -u 2>/dev/null || true
fi
if command -v update-grub >/dev/null 2>&1; then
    echo "[restore] rebuilding GRUB config"
    update-grub 2>/dev/null || true
fi

# Reset per-user wallpaper/icon overrides back to desktop defaults.
for home in /home/*; do
    [ -d "\$home" ] || continue
    user=\$(basename "\$home")
    if command -v dbus-run-session >/dev/null 2>&1 && command -v gsettings >/dev/null 2>&1; then
        su - "\$user" -c "dbus-run-session -- sh -c '
            gsettings reset org.cinnamon.desktop.background picture-uri 2>/dev/null
            gsettings reset org.cinnamon.desktop.interface icon-theme 2>/dev/null
            gsettings reset org.mate.background picture-filename 2>/dev/null
            gsettings reset org.mate.interface icon-theme 2>/dev/null
            gsettings reset org.gnome.desktop.background picture-uri 2>/dev/null
            gsettings reset org.gnome.desktop.background picture-uri-dark 2>/dev/null
            gsettings reset org.gnome.desktop.interface icon-theme 2>/dev/null
            true'" 2>/dev/null || true
    fi
done

rm -rf "\$BACKUP" /usr/local/sbin/hannahmontanaifier-restore
echo "[restore] done. The best of both worlds, restored."
EOF
chmod +x "$TARGET/usr/local/sbin/hannahmontanaifier-restore"
track usr/local/sbin/hannahmontanaifier-restore

log "done. Nobody's perfect… but this prank is."
log "undo later with: sudo hannahmontanaifier-restore (on the booted system)"
exit 0
