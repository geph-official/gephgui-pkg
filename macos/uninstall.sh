#!/bin/bash
#
# Completely removes Geph from this Mac: stops all Geph processes, restores
# networking, unregisters the privileged manager, removes system and per-user
# state, forgets the installer receipt, and removes the app itself.
#
# Run as root:
#
#   sudo /Applications/Geph.app/Contents/Resources/uninstall.sh
#
# This is shipped inside the app bundle so it stays in sync with what was
# installed. It is the counterpart of pkg-scripts/postinstall.

set -u

APP="/Applications/Geph.app"
MANAGER_BIN="$APP/Contents/Resources/geph"
LEGACY_PAC_BIN="$APP/Contents/MacOS/bin/pac-real"
MANAGER_LABEL="io.geph.manager"
LEGACY_LABEL="io.geph.daemon"
MANAGER_PLIST="/Library/LaunchDaemons/${MANAGER_LABEL}.plist"
LEGACY_PLIST="/Library/LaunchDaemons/${LEGACY_LABEL}.plist"
BUNDLE_ID="io.geph.GephGui"
PAC_URL="http://127.0.0.1:12223/proxy.pac"
FAILED=0

if [ "$(/usr/bin/id -u)" -ne 0 ]; then
    echo "must be run as root: sudo $0" >&2
    exit 1
fi

warn() {
    echo "[geph] warning: $*" >&2
    FAILED=1
}

remove_path() {
    local path="$1"
    if [ -e "$path" ] || [ -L "$path" ]; then
        /bin/rm -rf "$path" || warn "could not remove $path"
    fi
}

geph_pids_for_name() {
    local name="$1"
    local pid
    local command

    /usr/bin/pgrep -x "$name" 2>/dev/null | while IFS= read -r pid; do
        command="$(/bin/ps -p "$pid" -o command= 2>/dev/null || true)"
        case "$command" in
            "$APP/"*|*/Geph.app/Contents/*|"/Library/Application Support/geph/"*)
                echo "$pid"
                ;;
        esac
    done
}

geph_process_running() {
    [ -n "$(geph_pids_for_name "$1")" ]
}

terminate_geph_process() {
    local name="$1"
    local pid

    for pid in $(geph_pids_for_name "$name"); do
        /bin/kill -TERM "$pid" 2>/dev/null || true
    done
}

purge_user_home() {
    local user_home="$1"
    local username="${2:-}"
    local library="$user_home/Library"
    local path

    # Ignore service accounts and stale directory-service records. The explicit
    # guard also prevents a malformed home record from broadening deletion.
    case "$user_home" in
        ""|/|/Users|/var|/private/var) return ;;
    esac
    [ -d "$library" ] || return

    echo "[geph] removing user state from $user_home..."
    # Ask cfprefsd to remove the domains before deleting their backing files, or
    # a logged-in user's cached preferences can be written back after uninstall.
    if [ -n "$username" ]; then
        /usr/bin/sudo -H -u "$username" /usr/bin/defaults delete "$BUNDLE_ID" \
            >/dev/null 2>&1 || true
        /usr/bin/sudo -H -u "$username" /usr/bin/defaults delete gephgui-wry \
            >/dev/null 2>&1 || true
    fi
    for path in \
        "$library/WebKit/$BUNDLE_ID" \
        "$library/WebKit/gephgui-wry" \
        "$library/Caches/$BUNDLE_ID" \
        "$library/Caches/gephgui-wry" \
        "$library/Caches/geph5-dl" \
        "$library/HTTPStorages/$BUNDLE_ID" \
        "$library/HTTPStorages/gephgui-wry" \
        "$library/Saved Application State/$BUNDLE_ID.savedState" \
        "$library/Saved Application State/gephgui-wry.savedState" \
        "$library/Preferences/$BUNDLE_ID.plist" \
        "$library/Preferences/gephgui-wry.plist" \
        "$library/Cookies/$BUNDLE_ID.binarycookies" \
        "$library/Cookies/gephgui-wry.binarycookies" \
        "$library/Application Support/$BUNDLE_ID" \
        "$library/Application Support/gephgui-wry" \
        "$library/Containers/$BUNDLE_ID" \
        "$library/Application Scripts/$BUNDLE_ID" \
        "$library/Logs/Geph" \
        "$library/Logs/gephgui-wry" \
        "$library/LaunchAgents/$MANAGER_LABEL.plist" \
        "$library/LaunchAgents/$LEGACY_LABEL.plist"
    do
        remove_path "$path"
    done

    # geph5-client historically put credential-keyed SQLite caches directly in
    # Application Support. Remove the database and its WAL/SHM companions.
    for path in "$library/Application Support"/geph5-persist-*.db*; do
        if [ -e "$path" ] || [ -L "$path" ]; then
            remove_path "$path"
        fi
    done

    # CrashReporter records are app-owned state too. Keep the patterns narrow so
    # similarly named, unrelated reports are untouched.
    for path in \
        "$library/Application Support/CrashReporter"/gephgui-wry_*.plist \
        "$library/Preferences/ByHost"/"$BUNDLE_ID".*.plist \
        "$library/Preferences/ByHost"/gephgui-wry.*.plist \
        "$library/Logs/DiagnosticReports"/gephgui-wry-* \
        "$library/Logs/DiagnosticReports"/geph5-client-* \
        "$library/Logs/DiagnosticReports"/Geph-*
    do
        if [ -e "$path" ] || [ -L "$path" ]; then
            remove_path "$path"
        fi
    done
}

echo "[geph] stopping the GUI..."
terminate_geph_process gephgui-wry
terminate_geph_process entrypoint

echo "[geph] disconnecting and unregistering the manager..."
if [ -x "$MANAGER_BIN" ]; then
    # Disconnect first so routes, DNS, the kill switch, and child engines are
    # removed through the manager's normal teardown path.
    "$MANAGER_BIN" disconnect >/dev/null 2>&1 || true
    # Restore the saved pre-Geph proxy configuration. With no snapshot this only
    # clears a PAC setting whose URL is exactly Geph's loopback URL.
    "$MANAGER_BIN" __apply-proxy off "$PAC_URL" >/dev/null 2>&1 || \
        warn "could not restore the system proxy configuration"
    "$MANAGER_BIN" unregister-manager >/dev/null 2>&1 || true
fi

# Idempotent fallbacks cover partially installed and older releases.
/bin/launchctl bootout "system/$MANAGER_LABEL" 2>/dev/null || \
    /bin/launchctl bootout system "$MANAGER_PLIST" 2>/dev/null || true
/bin/launchctl bootout "system/$LEGACY_LABEL" 2>/dev/null || \
    /bin/launchctl bootout system "$LEGACY_PLIST" 2>/dev/null || true
for label in "$MANAGER_LABEL" "$LEGACY_LABEL"; do
    if /bin/launchctl print "system/$label" >/dev/null 2>&1; then
        warn "launchd job $label is still registered"
    fi
done

# Releases through 5.7.x used this helper and did not keep a proxy snapshot.
if [ -x "$LEGACY_PAC_BIN" ]; then
    "$LEGACY_PAC_BIN" off "$PAC_URL" >/dev/null 2>&1 || \
        warn "could not clear the legacy system proxy configuration"
fi

# Stop any orphaned engines or helpers. Give TERM a bounded grace period before
# using KILL so uninstall cannot leave executable mappings from a deleted app.
for name in gephgui-wry entrypoint geph geph5 geph4-client geph5-client; do
    terminate_geph_process "$name"
done
for attempt in 1 2 3 4 5; do
    any_running=0
    for name in gephgui-wry entrypoint geph geph5 geph4-client geph5-client; do
        if geph_process_running "$name"; then
            any_running=1
            break
        fi
    done
    [ "$any_running" -eq 0 ] && break
    /bin/sleep 1
done
for name in gephgui-wry entrypoint geph geph5 geph4-client geph5-client; do
    if geph_process_running "$name"; then
        for pid in $(geph_pids_for_name "$name"); do
            /bin/kill -KILL "$pid" 2>/dev/null || true
        done
        /bin/sleep 1
        geph_process_running "$name" && warn "$name is still running"
    fi
done

echo "[geph] removing launch daemons, manager state, and logs..."
remove_path "$MANAGER_PLIST"
remove_path "$LEGACY_PLIST"
remove_path "/Library/Application Support/geph"
remove_path "/var/run/geph"
remove_path "/var/log/geph-manager.log"
remove_path "/var/log/geph-daemon.log"
for path in \
    /Library/Logs/DiagnosticReports/gephgui-wry-* \
    /Library/Logs/DiagnosticReports/geph5-client-* \
    /Library/Logs/DiagnosticReports/Geph-*
do
    if [ -e "$path" ] || [ -L "$path" ]; then
        remove_path "$path"
    fi
done

echo "[geph] removing the _geph service user..."
if /usr/bin/dscl . -read /Users/_geph >/dev/null 2>&1; then
    /usr/bin/dscl . -delete /Users/_geph >/dev/null 2>&1 || \
        warn "could not remove the _geph service user"
    /usr/bin/dscacheutil -flushcache 2>/dev/null || true
fi

echo "[geph] removing per-user state..."
# Include root in case a historical command was run with sudo and then enumerate
# every local account, including accounts whose home is outside /Users.
purge_user_home "/var/root" root
if /usr/bin/dscl . -list /Users >/dev/null 2>&1; then
    while IFS= read -r username; do
        home_record="$(/usr/bin/dscl . -read "/Users/$username" NFSHomeDirectory 2>/dev/null || true)"
        user_home="${home_record#NFSHomeDirectory: }"
        if [ "$user_home" != "$home_record" ]; then
            purge_user_home "$user_home" "$username"
        fi
    done < <(/usr/bin/dscl . -list /Users 2>/dev/null)
else
    warn "could not enumerate local users; per-user state may remain"
fi

# WebKit and Foundation also keep app-specific cache/temp buckets under the
# opaque per-user /var/folders hierarchy.
if [ -d /private/var/folders ]; then
    /usr/bin/find /private/var/folders -type d \
        \( -name "$BUNDLE_ID" -o -name gephgui-wry -o -name geph5-dl \) \
        -prune -exec /bin/rm -rf {} + 2>/dev/null || \
        warn "could not remove one or more temporary Geph directories"
fi

echo "[geph] forgetting the installer receipt..."
/usr/sbin/pkgutil --forget "$BUNDLE_ID" >/dev/null 2>&1 || true

# Remove the app last: this script lives inside it. bash has already read the
# script, so deleting the bundle out from under the running shell is safe.
echo "[geph] removing $APP..."
remove_path "$APP"

if [ "$FAILED" -ne 0 ]; then
    echo "[geph] uninstall finished with warnings." >&2
    exit 1
fi

echo "[geph] completely removed Geph."
