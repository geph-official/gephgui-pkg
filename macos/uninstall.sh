#!/bin/bash
#
# Completely removes Geph from this Mac: stops and unregisters the root manager,
# deletes its state and the _geph service user, forgets the installer receipt,
# and removes the app itself.
#
# Run as root:
#
#   sudo /Applications/Geph.app/Contents/Resources/uninstall.sh
#
# This is shipped inside the app bundle so it stays in sync with what was
# installed. It is the counterpart of pkg-scripts/postinstall.

set -u

LABEL="io.geph.manager"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
BUNDLE_ID="io.geph.GephGui"

if [ "$(id -u)" -ne 0 ]; then
    echo "must be run as root: sudo $0" >&2
    exit 1
fi

echo "[geph] stopping and unregistering the manager..."
launchctl bootout "system/${LABEL}" 2>/dev/null || launchctl bootout system "$PLIST" 2>/dev/null || true
rm -f "$PLIST"

echo "[geph] removing the _geph service user..."
dscl . -delete /Users/_geph 2>/dev/null || true

echo "[geph] removing manager state and logs..."
rm -rf "/Library/Application Support/geph"
rm -rf "/var/run/geph"
rm -f "/var/log/geph-manager.log"

echo "[geph] forgetting the installer receipt..."
pkgutil --forget "$BUNDLE_ID" 2>/dev/null || true

# Remove the app last: this script lives inside it. bash has already read this
# far, so deleting the bundle out from under us is safe.
echo "[geph] removing /Applications/Geph.app..."
rm -rf "/Applications/Geph.app"

echo "[geph] done."
