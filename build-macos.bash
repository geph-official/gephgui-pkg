#!/bin/bash
#
# Build a self-contained macOS installer (Geph.pkg) for Geph.
#
# Everything it needs comes from this repo's git submodules (gephgui-wry and
# geph5) — it does NOT depend on any sibling checkout under ~/develop. Run it
# from anywhere; it locates itself and the repo root.
#
# The result, ./output/geph-macos-<version>.pkg, is a distribution package
# (like Mullvad's) that:
#   - installs /Applications/Geph.app (GUI + the bundled `geph` manager binary),
#   - registers the manager as a root LaunchDaemon (see macos/pkg-scripts/
#     postinstall), giving it persistent root across reboots and updates, and
#   - shows the install size on the installer's "Installation Type" screen
#     (Installer.app computes this automatically for distribution pkgs).

set -euo pipefail

cd "$(dirname "$0")"
REPO_ROOT="$PWD"
MACOS_DIR="$REPO_ROOT/macos"
OUTPUT="$REPO_ROOT/output"

# ---- config ---------------------------------------------------------------

BUNDLE_ID="io.geph.GephGui"
APP_NAME="Geph.app"

# Build a universal (fat) app: native on both Intel and Apple Silicon. Each
# binary is built once per arch and lipo'd together. Override for a faster
# single-arch debug build, e.g. ARCHS="x86_64-apple-darwin".
ARCHS="${ARCHS:-x86_64-apple-darwin aarch64-apple-darwin}"

# Per-arch minimum macOS version. arm64 can't go below 11.0 (Apple Silicon
# debuted on Big Sur); x86_64 keeps 10.15 so old Intel Macs are still served.
# Matches LSMinimumSystemVersion in template.app/Contents/Info.plist. Setting
# MACOSX_DEPLOYMENT_TARGET (per-arch, below) makes the toolchain weak-link
# newer-than-target symbols and stamp LC_BUILD_VERSION correctly; without it the
# binary inherits the build host's SDK as its floor and crashes on older systems.
min_os_for() { case "$1" in aarch64-apple-darwin) echo 11.0 ;; *) echo 10.15 ;; esac; }

# lipo N inputs into one universal output; plain copy when only one arch is built.
lipo_or_copy() { local out="$1"; shift; if [ "$#" -eq 1 ]; then cp "$1" "$out"; else lipo -create -output "$out" "$@"; fi; }

# Exported so the cargo builds below bake it in: gephgui-wry reads it via
# option_env!("VERSION") for the "About" display and the auto-updater's
# current-version check. Without the export it compiles to None -> the UI shows
# "(development version)" and updates misbehave.
export VERSION="${VERSION:-$(git -C "$REPO_ROOT" describe --always 2>/dev/null || echo 0.0.0)}"
ARTIFACT="$OUTPUT/geph-macos-${VERSION#v}.pkg"

# Optional signing/notarization (all no-ops if unset — a local unsigned pkg
# installs fine via `sudo installer -pkg output/geph-macos-<version>.pkg -target /`):
#   APP_SIGN_ID        "Developer ID Application: ..."   (codesign the app + manager)
#   INSTALLER_SIGN_ID  "Developer ID Installer: ..."     (sign the .pkg)
#   NOTARY_PROFILE     notarytool --keychain-profile name (notarize + staple)
APP_SIGN_ID="${APP_SIGN_ID:-}"
INSTALLER_SIGN_ID="${INSTALLER_SIGN_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

echo ">> building Geph $VERSION for $ARCHS"

# ---- 0. submodules + toolchain -------------------------------------------

# Initialize only submodules that are missing (uninitialized ones are prefixed
# with '-' in `submodule status`). Deliberately do NOT `update` populated ones:
# that would hard-reset them to the pinned commit and clobber local changes,
# and you may be developing geph5/gephgui-wry in-tree.
git -C "$REPO_ROOT" submodule status --recursive 2>/dev/null \
    | awk '/^-/ {print $2}' \
    | while read -r sm; do
        echo ">> initializing missing submodule: $sm"
        git -C "$REPO_ROOT" submodule update --init --recursive "$sm"
    done

for t in $ARCHS; do rustup target add "$t" >/dev/null 2>&1 || true; done

# ---- 1. frontend (embedded into gephgui-wry via rust-embed) ---------------

pushd "$REPO_ROOT/gephgui-wry/gephgui" >/dev/null
npm i -f
npm run build
popd >/dev/null

# ---- 2. clean workspace ---------------------------------------------------

BUILD_APP="$MACOS_DIR/build.app"
STAGE="$MACOS_DIR/pkgroot"        # what pkgbuild installs under /
CARGO_OUT="$MACOS_DIR/cargo-out"  # cargo install --root target (kept out of ~/.cargo/bin)
rm -rf "$BUILD_APP" "$STAGE" "$CARGO_OUT" "$MACOS_DIR/geph-component.pkg"
mkdir -p "$OUTPUT"

# ---- 3. assemble the app bundle ------------------------------------------

rsync -aW --delete "$MACOS_DIR/template.app/" "$BUILD_APP/"

mkdir -p "$CARGO_OUT"

# Each binary is built once per arch (into its own dir / --root) with that arch's
# deployment target, then lipo'd into a single universal binary.

# GUI (unprivileged front-end) -> Contents/MacOS/gephgui-wry, launched directly
# as CFBundleExecutable. Historically an `entrypoint` C shim exec'd the GUI from
# a bin/ subdir (to chdir + put helper tools on PATH), but the helpers are gone
# and the execv broke the tray icon: after exec, the process's identity no longer
# matches what LaunchServices registered, and NSStatusItem registration silently
# fails — app launched fine, no menu-bar icon. Launching the Rust binary directly
# fixes that (and is one less binary to build/sign).
# Privileged manager (geph5 crate, binary name `geph5`) -> Contents/Resources/geph.
# The LaunchDaemon plist points at the manager; its CLI subcommands
# (connect/status/…) are the same binary.
# Engine (geph5-client) -> Contents/Resources/geph5-client, a sibling of the
# manager. The manager resolves and spawns the engine as this sibling binary
# (see geph5-app supervisor::engine_bin_path); without it, connecting fails with
# "staging engine binary geph5-client ... No such file or directory".
gui_inputs=()
mgr_inputs=()
engine_inputs=()
for t in $ARCHS; do
    export MACOSX_DEPLOYMENT_TARGET="$(min_os_for "$t")"
    cargo install --force --locked --target "$t" \
        --path "$REPO_ROOT/gephgui-wry" --root "$CARGO_OUT/gui-$t"
    cargo install --force --locked --target "$t" \
        --path "$REPO_ROOT/geph5/binaries/geph5-app" --root "$CARGO_OUT/manager-$t"
    cargo install --force --locked --target "$t" \
        --path "$REPO_ROOT/geph5/binaries/geph5-client" --root "$CARGO_OUT/engine-$t"
    gui_inputs+=("$CARGO_OUT/gui-$t/bin/gephgui-wry")
    mgr_inputs+=("$CARGO_OUT/manager-$t/bin/geph5")
    engine_inputs+=("$CARGO_OUT/engine-$t/bin/geph5-client")
done
# The template ships no MacOS/ dir (all executables are built), so create it.
mkdir -p "$BUILD_APP/Contents/MacOS"
lipo_or_copy "$BUILD_APP/Contents/MacOS/gephgui-wry"      "${gui_inputs[@]}"
lipo_or_copy "$BUILD_APP/Contents/Resources/geph"         "${mgr_inputs[@]}"
lipo_or_copy "$BUILD_APP/Contents/Resources/geph5-client" "${engine_inputs[@]}"

# Uninstaller (counterpart of pkg-scripts/postinstall). Ships in the bundle so
# it matches what was installed. Copy BEFORE codesigning so it's covered by the
# signature.
install -m 755 "$MACOS_DIR/uninstall.sh" "$BUILD_APP/Contents/Resources/uninstall.sh"

# Note: `pkgutil --payload-files` on the result lists `._<name>` AppleDouble
# entries. Those are just pkgbuild serializing the sticky `com.apple.provenance`
# xattr that macOS 13+ stamps on every file (xattr -c / ditto --noextattr can't
# remove it). The Installer reapplies it as an attribute on install — no literal
# `._` side-files land in /Applications, so this is cosmetic and expected.

# ---- 4. optional codesign (nested binaries first, then the bundle) --------

if [ -n "$APP_SIGN_ID" ]; then
    echo ">> codesigning app with '$APP_SIGN_ID'"
    for f in Contents/Resources/geph Contents/Resources/geph5-client Contents/MacOS/gephgui-wry; do
        codesign --force --options runtime --timestamp -s "$APP_SIGN_ID" "$BUILD_APP/$f"
    done
    codesign --force --options runtime --timestamp -s "$APP_SIGN_ID" "$BUILD_APP"
fi

# ---- 5. stage payload + build component pkg -------------------------------

mkdir -p "$STAGE/Applications"
mv "$BUILD_APP" "$STAGE/Applications/$APP_NAME"

pkgbuild \
    --root "$STAGE" \
    --scripts "$MACOS_DIR/pkg-scripts" \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    --install-location "/" \
    --ownership recommended \
    "$MACOS_DIR/geph-component.pkg"

# ---- 6. distribution pkg (adds title + the install-size display) ----------

DIST_XML="$MACOS_DIR/distribution.xml"
cat > "$DIST_XML" <<XML_EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>Geph</title>
    <organization>io.geph</organization>
    <options customize="never" require-scripts="true" hostArchitectures="x86_64,arm64"/>
    <domains enable_localSystem="true" enable_anywhere="false" enable_currentUserHome="false"/>
    <welcome file="welcome.html"/>
    <conclusion file="conclusion.html"/>
    <!-- Match LSMinimumSystemVersion in the app's Info.plist. -->
    <volume-check>
        <allowed-os-versions>
            <os-version min="10.15"/>
        </allowed-os-versions>
    </volume-check>
    <choices-outline>
        <line choice="default">
            <line choice="$BUNDLE_ID"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="$BUNDLE_ID" visible="false">
        <pkg-ref id="$BUNDLE_ID"/>
    </choice>
    <pkg-ref id="$BUNDLE_ID" version="$VERSION" onConclusion="none">geph-component.pkg</pkg-ref>
</installer-gui-script>
XML_EOF

PRODUCTBUILD_ARGS=(
    --distribution "$DIST_XML"
    --package-path "$MACOS_DIR"
    --resources "$MACOS_DIR/resources"
)
[ -n "$INSTALLER_SIGN_ID" ] && PRODUCTBUILD_ARGS+=(--sign "$INSTALLER_SIGN_ID")

productbuild "${PRODUCTBUILD_ARGS[@]}" "$ARTIFACT"

# ---- 7. optional notarize + staple ---------------------------------------

if [ -n "$NOTARY_PROFILE" ]; then
    echo ">> notarizing"
    xcrun notarytool submit "$ARTIFACT" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$ARTIFACT"
fi

# ---- 8. cleanup intermediates --------------------------------------------

rm -rf "$STAGE" "$CARGO_OUT" "$MACOS_DIR/geph-component.pkg"

echo ">> done: $ARTIFACT"
