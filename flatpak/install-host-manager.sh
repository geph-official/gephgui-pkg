#!/bin/sh
# Privileged installer for the Geph host manager, run via pkexec from the Flatpak
# GUI's startup bootstrap (gephgui-wry/src/bootstrap.rs).
#
# This lives in the packaging layer (gephgui-pkg) on purpose: geph5 stays unaware
# of how downstreams package it, and the GUI only orchestrates (detect -> dialog ->
# elevate -> run this script). All host-install *policy* is here.
#
# Usage: install-host-manager.sh <staging-dir> <flatpak-app-data-dir>
#   <staging-dir>           dir holding geph5, geph5-client and the cleanup assets,
#                           staged out of the Flatpak into a host-visible location
#   <flatpak-app-data-dir>  path whose disappearance means "the Flatpak was
#                           uninstalled" (drives the self-cleanup watchdog)
set -eu

STAGING="$1"
OWNER="$2"
BINDIR="/usr/local/bin"

# 1. Install the manager + engine binaries side-by-side. geph5 resolves geph5-client as a
#    sibling of its own executable, so they must share a directory.
install -D -m 0755 "$STAGING/geph5"        "$BINDIR/geph5"
install -D -m 0755 "$STAGING/geph5-client" "$BINDIR/geph5-client"

# 2. Register (or refresh) the systemd service. register-manager bakes the absolute
#    ExecStart path from the running binary, so it must run from the final install
#    location; it also daemon-reloads, enables and *restarts* the unit, so an
#    upgrade (new binary at the same path) is picked up automatically.
"$BINDIR/geph5" register-manager

# 3. Install the packaging-owned self-cleanup watchdog (Flatpak-only). It removes
#    the host manager once the Flatpak's app-data dir disappears (uninstall). geph5
#    knows nothing about any of this.
install -D -m 0755 "$STAGING/geph-flatpak-watchdog.sh" "$BINDIR/geph-flatpak-watchdog"
sed -e "s|@BINDIR@|$BINDIR|g" -e "s|@OWNER@|$OWNER|g" \
    "$STAGING/geph-cleanup.service" > /etc/systemd/system/geph-cleanup.service
install -m 0644 "$STAGING/geph-cleanup.timer" /etc/systemd/system/geph-cleanup.timer
systemctl daemon-reload
systemctl enable --now geph-cleanup.timer
