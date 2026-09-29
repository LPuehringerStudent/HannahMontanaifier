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
DIRS="$BACKUP/dirs.list"       # newly created parent dirs (rmdir'd on restore if empty)
mkdir -p "$FILES"
: >> "$INSTALLED"
: >> "$DIRS"

# Restore-kit state; the plymouth section overwrites these when it runs.
OLD_PLYMOUTH_THEME=bgrt
PLY_ALT_LINK=""       # Debian/Ubuntu/Mint default.plymouth alternative, if any
OLD_PLY_ALT=""
OLD_PLY_ALT_MODE=""
HML_PLYMOUTH=/usr/share/plymouth/themes/hannah-montana/hannah-montana.plymouth

# bcp <absolute path> — back up an existing target file before overwriting it.
# A symlink is backed up as the link itself (cp -a), so restore puts the link back.
bcp() {
    rel="${1#/}"
    if { [ -e "$TARGET/$rel" ] || [ -L "$TARGET/$rel" ]; } && [ ! -e "$FILES/$rel" ] && [ ! -L "$FILES/$rel" ]; then
        mkdir -p "$FILES/$(dirname "$rel")"
        cp -a "$TARGET/$rel" "$FILES/$rel" 2>/dev/null || warn "backup failed: /$rel"
    fi
}

# track <relative path> — remember a newly created file for the restore script.
track() {
    grep -qxF "$1" "$INSTALLED" 2>/dev/null || printf '%s\n' "$1" >> "$INSTALLED"
}

# claim <relative path> — make a target file safe to (over)write: back up an
# existing original, or track it as new. A symlink (e.g. Debian's
# /etc/os-release -> ../usr/lib/os-release) is replaced by a regular copy of
# its content, so writes never go through it into a package-owned file.
claim() {
    rel="$1"
    if [ -e "$TARGET/$rel" ] || [ -L "$TARGET/$rel" ]; then
        bcp "/$rel"
        if [ -L "$TARGET/$rel" ]; then
            lt=$(readlink "$TARGET/$rel")
            case "$lt" in
                /*) lsrc="$TARGET$lt" ;;
                *)  lsrc="$TARGET/$(dirname "$rel")/$lt" ;;
            esac
            if cp "$lsrc" "$TARGET/$rel.hml-tmp" 2>/dev/null; then
                mv -f "$TARGET/$rel.hml-tmp" "$TARGET/$rel"
            else
                rm -f "$TARGET/$rel.hml-tmp" "$TARGET/$rel"
            fi
        fi
    else
        track "$rel"
    fi
    mkparents "$rel"
}

# mkparents <relative path> — create the parent dirs of a target path,
# recording each one that didn't exist so restore can remove it again.
mkparents() {
    d=$(dirname "$1")
    while [ "$d" != . ] && [ "$d" != / ] && [ ! -d "$TARGET/$d" ]; do
        grep -qxF "$d" "$DIRS" 2>/dev/null || printf '%s\n' "$d" >> "$DIRS"
        d=$(dirname "$d")
    done
    mkdir -p "$TARGET/$(dirname "$1")"
}

# put <src> <dest relative path> — install a file, backing up any original.
# Installed as root; install_user_stuff re-chowns files in home directories.
put() {
    src="$1"; rel="$2"
    claim "$rel"
    cp -a "$src" "$TARGET/$rel" || warn "install failed: /$rel"
    chown 0:0 "$TARGET/$rel" 2>/dev/null || true
}

# puttree <src dir> <dest relative dir> — install a directory tree.
puttree() {
    src="$1"; rel="$2"
    [ -e "$TARGET/$rel" ] && existed=1 || { existed=0; track "$rel"; }
    mkparents "$rel"
    cp -a "$src" "$TARGET/$rel" || warn "install failed: /$rel"
    [ "$existed" = 1 ] || chown -R 0:0 "$TARGET/$rel" 2>/dev/null || true
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
    claim etc/lsb-release
    printf '%s\n' \
        'DISTRIB_ID=HannahMontana' \
        'DISTRIB_RELEASE=26.0' \
        'DISTRIB_CODENAME=montana' \
        'DISTRIB_DESCRIPTION="Hannah Montana Linux 26"' \
        > "$TARGET/etc/lsb-release"
fi
claim etc/issue
printf 'Hannah Montana Linux 26 \\n \\l\n\n' > "$TARGET/etc/issue"
claim etc/issue.net
printf 'Hannah Montana Linux 26\n' > "$TARGET/etc/issue.net"

if [ -n "$HML_HOSTNAME" ]; then
    log "renaming host to '$HML_HOSTNAME'"
    OLD_HOSTNAME=$(cat "$TARGET/etc/hostname" 2>/dev/null || true)
    claim etc/hostname
    printf '%s\n' "$HML_HOSTNAME" > "$TARGET/etc/hostname"
    claim etc/hosts
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
    claim etc/default/grub
    sed -i '/^GRUB_DISTRIBUTOR=/d;/^GRUB_BACKGROUND=/d;/^GRUB_THEME=/d' "$TARGET/etc/default/grub"
    printf '%s\n' \
        'GRUB_DISTRIBUTOR="Hannah Montana Linux 26"' \
        'GRUB_BACKGROUND=/boot/grub/hml-grub.png' \
        >> "$TARGET/etc/default/grub"
    # Mint/Ubuntu source /etc/default/grub.d/*.cfg AFTER /etc/default/grub and
    # can reset GRUB_DISTRIBUTOR there (e.g. Mint's 50_linuxmint.cfg), which
    # would undo the label above. Drop a late-sorting override that wins.
    if [ -d "$TARGET/etc/default/grub.d" ]; then
        claim etc/default/grub.d/99-hannah-montana.cfg
        printf '%s\n' \
            'GRUB_DISTRIBUTOR="Hannah Montana Linux 26"' \
            'GRUB_BACKGROUND=/boot/grub/hml-grub.png' \
            > "$TARGET/etc/default/grub.d/99-hannah-montana.cfg"
    fi
fi

# --------------------------------------------------------------- plymouth ---
if [ -d "$TARGET/usr/share/plymouth" ] || [ -d "$TARGET/etc/plymouth" ]; then
    log "setting plymouth boot splash"
    OLD_PLYMOUTH_THEME=$(sed -n 's/^Theme=//p' "$TARGET/etc/plymouth/plymouthd.conf" 2>/dev/null | head -1)
    [ -n "$OLD_PLYMOUTH_THEME" ] || OLD_PLYMOUTH_THEME=$(sed -n 's/^Theme=//p' "$TARGET/usr/share/plymouth/plymouthd.defaults" 2>/dev/null | head -1)
    [ -n "$OLD_PLYMOUTH_THEME" ] || OLD_PLYMOUTH_THEME="bgrt"
    # Debian/Ubuntu/Mint without plymouth-set-default-theme: the initramfs hook
    # takes the splash from the default.plymouth alternative, so remember its
    # current mode and value for the restore kit.
    if [ -f "$TARGET/var/lib/dpkg/alternatives/default.plymouth" ]; then
        OLD_PLY_ALT_MODE=$(sed -n 1p "$TARGET/var/lib/dpkg/alternatives/default.plymouth")
        PLY_ALT_LINK=$(sed -n 2p "$TARGET/var/lib/dpkg/alternatives/default.plymouth")
        OLD_PLY_ALT=$(readlink "$TARGET/etc/alternatives/default.plymouth" 2>/dev/null || true)
    fi
    claim etc/plymouth/plymouthd.conf
    printf '[Daemon]\nTheme=hannah-montana\nShowDelay=0\n' > "$TARGET/etc/plymouth/plymouthd.conf"
fi

# ------------------------------------------------------- display manager ----
if [ -d "$TARGET/etc/lightdm" ] || [ -e "$TARGET/usr/sbin/lightdm" ]; then
    log "theming LightDM greeter"
    claim etc/lightdm/slick-greeter.conf
    printf '%s\n' \
        '[Greeter]' \
        'background=/usr/share/backgrounds/hannahmontanaifier/login.png' \
        'draw-user-backgrounds=false' \
        'icon-theme-name=HannahMontana' \
        > "$TARGET/etc/lightdm/slick-greeter.conf"
fi
if [ -e "$TARGET/usr/bin/sddm" ] || [ -d "$TARGET/etc/sddm.conf.d" ]; then
    log "theming SDDM"
    claim etc/sddm.conf.d/kde_settings.conf
    cp "$SYS/etc/sddm.conf.d/kde_settings.conf" "$TARGET/etc/sddm.conf.d/kde_settings.conf"
fi
# GDM's greeter reads dconf defaults from /etc/gdm3/greeter.dconf-defaults
# (Debian/Ubuntu/Mint). We can set the login logo, a banner and the icon theme
# there; it can't set a background image (that lives in the gnome-shell theme
# gresource — test-live.sh does that part on the live system).
if [ -d "$TARGET/etc/gdm3" ] || [ -e "$TARGET/usr/sbin/gdm3" ]; then
    log "theming GDM greeter (logo + banner + icons)"
    claim etc/gdm3/greeter.dconf-defaults
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
    [ -x "$TARGET/usr/bin/dbus-run-session" ] || return 0
    keys=""
    if [ -e "$TARGET/usr/bin/cinnamon" ]; then
        keys="org.cinnamon.desktop.background picture-uri 'file://$WALLPAPER'
org.cinnamon.desktop.background picture-options 'zoom'
org.cinnamon.desktop.interface icon-theme 'HannahMontana'"
    elif [ -e "$TARGET/usr/bin/mate-session" ]; then
        keys="org.mate.background picture-filename '$WALLPAPER'
org.mate.interface icon-theme 'HannahMontana'"
    elif [ -e "$TARGET/usr/bin/gnome-shell" ]; then
        keys="org.gnome.desktop.background picture-uri 'file://$WALLPAPER'
org.gnome.desktop.background picture-uri-dark 'file://$WALLPAPER'
org.gnome.desktop.interface icon-theme 'HannahMontana'"
    fi
    [ -n "$keys" ] || return 0
    # One "schema key value" line per setting on stdin. Each key's current
    # value is saved to $BACKUP/gsettings/<user> (same format) before the prank
    # value is set, so the restore kit can put the user's own wallpaper back.
    mkdir -p "$BACKUP/gsettings"
    printf '%s\n' "$keys" | chroot "$TARGET" su - "$user" -c "dbus-run-session -- sh -c 'while read -r s k v; do old=\$(gsettings get \"\$s\" \"\$k\" 2>/dev/null) && printf \"%s %s %s\\n\" \"\$s\" \"\$k\" \"\$old\"; gsettings set \"\$s\" \"\$k\" \"\$v\"; done'" \
        > "$BACKUP/gsettings/$user" 2>/dev/null \
        || warn "dconf wallpaper failed for $user (non-fatal)"
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
    elif [ -n "$PLY_ALT_LINK" ] && [ -e "$TARGET/usr/bin/update-alternatives" ]; then
        { chroot "$TARGET" update-alternatives --install "$PLY_ALT_LINK" default.plymouth "$HML_PLYMOUTH" 100 \
            && chroot "$TARGET" update-alternatives --set default.plymouth "$HML_PLYMOUTH" \
            && chroot "$TARGET" update-initramfs -u; } >/dev/null 2>&1 \
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
( cd "\$BACKUP/files" && find . \( -type f -o -type l \) | while read -r f; do
    rel=\${f#./}
    mkdir -p "/\$(dirname "\$rel")"
    { [ -L "\$f" ] || [ -L "/\$rel" ]; } && rm -f "/\$rel"
    cp -a "\$f" "/\$rel" && echo "  restored /\$rel"
done )

echo "[restore] removing prank files"
while read -r rel; do
    [ -n "\$rel" ] && rm -rf "/\$rel" && echo "  removed /\$rel"
done < "\$BACKUP/installed.list"

echo "[restore] removing now-empty directories the prank created"
# Deepest first (reverse sort puts children before parents); rmdir keeps any
# directory that has gained other files since.
sort -r "\$BACKUP/dirs.list" 2>/dev/null | while read -r rel; do
    [ -n "\$rel" ] && rmdir "/\$rel" 2>/dev/null && echo "  removed /\$rel/"
done

if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    echo "[restore] reverting plymouth theme to '$OLD_PLYMOUTH_THEME'"
    plymouth-set-default-theme -R "$OLD_PLYMOUTH_THEME" 2>/dev/null || \\
        update-initramfs -u 2>/dev/null || true
elif command -v update-alternatives >/dev/null 2>&1 && [ -f /var/lib/dpkg/alternatives/default.plymouth ]; then
    echo "[restore] reverting plymouth boot splash"
    update-alternatives --remove default.plymouth "$HML_PLYMOUTH" >/dev/null 2>&1 || true
    if [ "$OLD_PLY_ALT_MODE" = manual ] && [ -n "$OLD_PLY_ALT" ]; then
        update-alternatives --set default.plymouth "$OLD_PLY_ALT" >/dev/null 2>&1 || true
    fi
    update-initramfs -u 2>/dev/null || true
fi
if command -v update-grub >/dev/null 2>&1; then
    echo "[restore] rebuilding GRUB config"
    update-grub 2>/dev/null || true
fi

# Put each user's own wallpaper/icon settings back (saved as "schema key value"
# lines at prank time); users without a saved copy are reset to desktop defaults.
for home in /home/*; do
    [ -d "\$home" ] || continue
    user=\$(basename "\$home")
    saved="\$BACKUP/gsettings/\$user"
    if ! command -v dbus-run-session >/dev/null 2>&1 || ! command -v gsettings >/dev/null 2>&1; then
        continue
    elif [ -s "\$saved" ]; then
        echo "[restore] restoring wallpaper/icon settings for \$user"
        # \$saved has one "schema key value" line per setting. The escaping below
        # renders in the generated restore script as the inner shell seeing:
        #   dbus-run-session -- sh -c 'while read -r s k v; do
        #       gsettings set "\$s" "\$k" "\$v" 2>/dev/null; done; true'
        # i.e. \$s/\$k/\$v are expanded by that innermost shell, not here.
        su - "\$user" -c "dbus-run-session -- sh -c 'while read -r s k v; do gsettings set \"\\\$s\" \"\\\$k\" \"\\\$v\" 2>/dev/null; done; true'" \\
            < "\$saved" 2>/dev/null || true
    else
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
