#!/bin/sh
# restore-live.sh — undo a ./test-live.sh run on THIS machine.
#
# The prank installs a full restore kit at
# /usr/local/sbin/hannahmontanaifier-restore (puts original files back, removes
# installed assets, reverts GRUB + Plymouth, resets dconf). This wrapper first
# reverts the current user's *running* session immediately (the installed
# restore only writes the on-disk dconf, which a live GNOME/Cinnamon session
# won't pick up until relog), then runs that restore kit.
#
# Usage:
#   sudo ./restore-live.sh

set -u

WALLPAPER=/usr/share/backgrounds/hannahmontanaifier/wallpaper.png
RESTORE_KIT=/usr/local/sbin/hannahmontanaifier-restore

log()  { printf '[restore-live] %s\n' "$*"; }
warn() { printf '[restore-live] WARNING: %s\n' "$*" >&2; }
die()  { printf '[restore-live] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "run me as root:  sudo ./restore-live.sh"

LIVE_USER="${SUDO_USER:-}"
if [ -z "$LIVE_USER" ] || [ "$LIVE_USER" = "root" ]; then
    LIVE_USER=$(who 2>/dev/null | awk 'NR==1{print $1}')
fi

# 1) Revert the live session's wallpaper/icons right now.
reset_live_wallpaper() {
    [ -n "$LIVE_USER" ] || return 0
    uid=$(id -u "$LIVE_USER" 2>/dev/null) || return 0
    if   [ -e /usr/bin/cinnamon ];    then de=cinnamon
    elif [ -e /usr/bin/mate-session ]; then de=mate
    elif [ -e /usr/bin/gnome-shell ]; then de=gnome
    else return 0
    fi
    log "resetting $de wallpaper/icons for $LIVE_USER (live session)"
    _gr() { sudo -u "$LIVE_USER" \
        DISPLAY="${DISPLAY:-:0}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        gsettings reset "$@" 2>/dev/null || true; }
    case "$de" in
        cinnamon)
            _gr org.cinnamon.desktop.background picture-uri
            _gr org.cinnamon.desktop.interface icon-theme ;;
        mate)
            _gr org.mate.background picture-filename
            _gr org.mate.interface icon-theme ;;
        gnome)
            _gr org.gnome.desktop.background picture-uri
            _gr org.gnome.desktop.background picture-uri-dark
            _gr org.gnome.desktop.interface icon-theme ;;
    esac
}
reset_live_wallpaper

# 2) Put the original gnome-shell theme gresource back BEFORE the restore kit
#    runs — the kit deletes /var/backups/hannahmontanaifier at the end, which is
#    where test-live.sh stashed the original.
GRESOURCE=/usr/share/gnome-shell/gnome-shell-theme.gresource
GRESOURCE_ORIG=/var/backups/hannahmontanaifier/gnome-shell-theme.gresource.orig
if [ -f "$GRESOURCE_ORIG" ]; then
    log "restoring original gnome-shell theme gresource (GDM background)"
    cp -a "$GRESOURCE_ORIG" "$GRESOURCE" || warn "couldn't restore gresource"
fi

# 3) Run the installed restore kit (files, assets, GRUB, Plymouth, on-disk dconf).
[ -x "$RESTORE_KIT" ] || die "no restore kit at $RESTORE_KIT — was the prank ever applied here?"
log "running $RESTORE_KIT"
"$RESTORE_KIT" || die "restore kit reported an error"

# 4) Recompile the greeter dconf db so GDM drops the logo/banner immediately.
if command -v dconf >/dev/null 2>&1; then
    log "recompiling GDM greeter dconf defaults"
    dconf update 2>/dev/null || warn "dconf update failed (non-fatal)"
fi

log "restored. Log out/in (or reboot) to clear the login screen + boot splash."
