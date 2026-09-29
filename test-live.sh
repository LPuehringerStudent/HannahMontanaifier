#!/bin/sh
# test-live.sh — try the Hannah Montana Linux prank on THIS running machine,
# with no USB and no mounting. It themes the live root filesystem, rebuilds
# GRUB + initramfs directly on the host, and switches the current desktop
# user's wallpaper/icons in their running session so you see it immediately.
#
# Everything is reversible:  sudo ./restore-live.sh
#
# Usage:
#   sudo ./test-live.sh          # asks once before touching anything
#   sudo ./test-live.sh -y       # skip the confirmation prompt
#
# Why a wrapper instead of `./hannahmontanaify.sh /`?  The main script is built
# for the offline flow (mount a target root, run against the mountpoint). Run
# straight against "/" it would bind-mount /dev /proc /sys /run onto themselves
# to chroot the "target" — pointless and risky when the target already is the
# running system. So we run it with HML_SKIP_CHROOT=1 and do the boot-config
# rebuild + live wallpaper switch here instead.

set -u

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MAIN="$SELF_DIR/hannahmontanaify.sh"
WALLPAPER=/usr/share/backgrounds/hannahmontanaifier/wallpaper.png

log()  { printf '[test-live] %s\n' "$*"; }
warn() { printf '[test-live] WARNING: %s\n' "$*" >&2; }
die()  { printf '[test-live] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "run me as root:  sudo ./test-live.sh"
[ -f "$MAIN" ]       || die "can't find hannahmontanaify.sh next to me ($MAIN)"

ASSUME_YES=0
[ "${1:-}" = "-y" ] || [ "${1:-}" = "--yes" ] && ASSUME_YES=1

# Who is the desktop user whose session we should re-theme live?
LIVE_USER="${SUDO_USER:-}"
if [ -z "$LIVE_USER" ] || [ "$LIVE_USER" = "root" ]; then
    LIVE_USER=$(who 2>/dev/null | awk 'NR==1{print $1}')
fi
[ -n "$LIVE_USER" ] || warn "couldn't detect a desktop user; wallpaper won't change live"

if [ "$ASSUME_YES" != "1" ]; then
    printf '%s\n' \
        "This themes the RUNNING system as Hannah Montana Linux 26:" \
        "  - rewrites /etc/os-release, hostname, GRUB + Plymouth" \
        "  - rebuilds grub.cfg and the initramfs" \
        "  - themes the GDM login screen (logo, banner, background)" \
        "  - changes ${LIVE_USER:-your} wallpaper and icons right now" \
        "It is fully reversible with:  sudo ./restore-live.sh" \
        ""
    printf 'Proceed? [y/N] '
    read -r ans < /dev/tty || ans=n
    case "$ans" in y|Y|yes|YES) ;; *) die "aborted — nothing changed" ;; esac
fi

# 1) Lay down all the theme files + identity changes (no chroot/self-binds).
log "applying theme to the live root filesystem"
HML_SKIP_CHROOT=1 sh "$MAIN" / || die "hannahmontanaify.sh failed"

# 2) Rebuild boot config directly on the host (we ARE the target).
if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    log "activating Plymouth boot splash (rebuilds initramfs)"
    plymouth-set-default-theme -R hannah-montana 2>/dev/null \
        || update-initramfs -u 2>/dev/null \
        || warn "initramfs rebuild failed (non-fatal)"
elif command -v update-initramfs >/dev/null 2>&1; then
    update-initramfs -u 2>/dev/null || warn "update-initramfs failed (non-fatal)"
fi
if command -v update-grub >/dev/null 2>&1; then
    log "rebuilding GRUB config"
    update-grub 2>/dev/null || warn "update-grub failed (non-fatal)"
fi

# 3) GDM greeter: apply the dconf defaults (logo/banner/icons) the main script
#    wrote, and swap a background image into the gnome-shell theme gresource —
#    the only way to give GDM's login screen a real background. Fully backed up.
gdm_gresource_background() {
    gres=/usr/share/gnome-shell/gnome-shell-theme.gresource
    bg=/usr/share/backgrounds/hannahmontanaifier/login.png
    [ -e "$bg" ] || bg=/usr/share/backgrounds/hannahmontanaifier/wallpaper.png
    [ -f "$gres" ] || { warn "no gnome-shell theme gresource; skipping GDM background"; return 0; }
    [ -e "$bg" ]   || { warn "no login background installed; skipping GDM background"; return 0; }
    command -v gresource >/dev/null 2>&1 || { warn "'gresource' missing; skipping GDM background"; return 0; }
    command -v glib-compile-resources >/dev/null 2>&1 || { warn "'glib-compile-resources' missing; skipping GDM background"; return 0; }

    backup=/var/backups/hannahmontanaifier
    mkdir -p "$backup"
    [ -f "$backup/gnome-shell-theme.gresource.orig" ] || cp -a "$gres" "$backup/gnome-shell-theme.gresource.orig"

    work=$(mktemp -d) || { warn "mktemp failed; skipping GDM background"; return 0; }
    prefix=/org/gnome/shell/theme
    reslist=$(gresource list "$gres" 2>/dev/null)
    [ -n "$reslist" ] || { warn "couldn't read gresource; skipping GDM background"; rm -rf "$work"; return 0; }

    manifest="$work/hml-theme.gresource.xml"
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<gresources>' \
        "  <gresource prefix=\"$prefix\">" > "$manifest"
    for res in $reslist; do
        case "$res" in
            "$prefix/"*) ;;
            *) warn "gresource has entries outside $prefix; skipping GDM background"; rm -rf "$work"; return 0 ;;
        esac
        name=${res#"$prefix/"}
        out="$work/$name"
        mkdir -p "$(dirname "$out")"
        gresource extract "$gres" "$res" > "$out" 2>/dev/null || continue
        printf '    <file>%s</file>\n' "$name" >> "$manifest"
    done

    cp "$bg" "$work/hml-login.png"
    printf '    <file>%s</file>\n' 'hml-login.png' >> "$manifest"
    css_added=0
    for css in "$work"/*.css; do
        [ -e "$css" ] || continue
        cat >> "$css" <<'CSS'

/* HannahMontanaifier: login-screen background */
#lockDialogGroup {
  background: #1a1a1a url('resource:///org/gnome/shell/theme/hml-login.png');
  background-size: cover;
  background-repeat: no-repeat;
  background-position: center;
}
CSS
        css_added=1
    done
    [ "$css_added" = "1" ] || warn "no top-level stylesheet in theme; GDM background may not show"
    printf '%s\n' '  </gresource>' '</gresources>' >> "$manifest"

    if glib-compile-resources --sourcedir="$work" --target="$work/out.gresource" "$manifest" 2>/dev/null \
        && [ -s "$work/out.gresource" ]; then
        cp "$work/out.gresource" "$gres"
        log "installed themed GDM login background (gnome-shell gresource)"
    else
        warn "gresource rebuild failed — original left in place; GDM background unchanged"
    fi
    rm -rf "$work"
}

theme_gdm_greeter() {
    [ -d /etc/gdm3 ] || [ -e /usr/sbin/gdm3 ] || return 0
    if command -v dconf >/dev/null 2>&1; then
        log "compiling GDM greeter dconf defaults (logo/banner/icons)"
        dconf update 2>/dev/null || warn "dconf update failed (non-fatal)"
    fi
    gdm_gresource_background
}

# 4) Switch wallpaper + icons in the live user's running session.
apply_live_wallpaper() {
    [ -n "$LIVE_USER" ] || return 0
    uid=$(id -u "$LIVE_USER" 2>/dev/null) || return 0
    [ -e "$WALLPAPER" ] || { warn "wallpaper not installed at $WALLPAPER"; return 0; }
    if   [ -e /usr/bin/cinnamon ];    then de=cinnamon
    elif [ -e /usr/bin/mate-session ]; then de=mate
    elif [ -e /usr/bin/gnome-shell ]; then de=gnome
    else warn "unknown desktop; set the wallpaper manually"; return 0
    fi
    log "setting $de wallpaper/icons for $LIVE_USER (live session)"
    _gs() { sudo -u "$LIVE_USER" \
        DISPLAY="${DISPLAY:-:0}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        gsettings "$@" 2>/dev/null || warn "gsettings $* failed (relog to see it)"; }
    case "$de" in
        cinnamon)
            _gs set org.cinnamon.desktop.background picture-uri "file://$WALLPAPER"
            _gs set org.cinnamon.desktop.background picture-options zoom
            _gs set org.cinnamon.desktop.interface icon-theme HannahMontana ;;
        mate)
            _gs set org.mate.background picture-filename "$WALLPAPER"
            _gs set org.mate.interface icon-theme HannahMontana ;;
        gnome)
            _gs set org.gnome.desktop.background picture-uri "file://$WALLPAPER"
            _gs set org.gnome.desktop.background picture-uri-dark "file://$WALLPAPER"
            _gs set org.gnome.desktop.interface icon-theme HannahMontana ;;
    esac
}
theme_gdm_greeter
apply_live_wallpaper

log "done — the best of both worlds."
log "Now: wallpaper/icons changed already; log out/in for the login screen +"
log "fastfetch, and reboot to see GRUB and the Plymouth splash."
log "Undo everything with:  sudo ./restore-live.sh"
