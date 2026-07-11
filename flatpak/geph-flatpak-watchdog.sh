#!/bin/sh
# Geph Flatpak self-cleanup. Flatpak provides no privileged uninstall hook, so this
# watchdog (driven by geph-cleanup.timer) periodically checks whether the Geph
# Flatpak's app-data dir still exists. Once it's gone, the Flatpak has been
# uninstalled, so we tear the host manager -- and this watchdog itself -- back down.
#
# geph5 only knows how to remove *itself* (unregister-manager); the packaging-specific
# teardown (staged binaries, the watchdog units) lives here in the packaging layer.
#
# Usage: geph-flatpak-watchdog <flatpak-app-data-dir> [bindir]
set -eu

OWNER="$1"
BINDIR="${2:-/usr/local/bin}"

# Still installed? Nothing to do.
[ -e "$OWNER" ] && exit 0

# Remove the manager (geph5 cleans up its own systemd unit + service user).
"$BINDIR/geph5" unregister-manager || true

# Remove the staged binaries and the watchdog itself.
rm -f "$BINDIR/geph5" "$BINDIR/geph5-client" "$BINDIR/geph-flatpak-watchdog"
systemctl disable --now geph-cleanup.timer || true
rm -f /etc/systemd/system/geph-cleanup.timer /etc/systemd/system/geph-cleanup.service
systemctl daemon-reload || true
