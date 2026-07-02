#!/bin/bash
#
# Build a self-contained macOS installer (Geph.pkg) for Geph.
#
# Everything it needs comes from this repo's git submodules (gephgui-wry and
# geph5) — it does NOT depend on any sibling checkout under ~/develop. Run it
# from anywhere; it locates itself and the repo root.
#
# The result, ./output/Geph.pkg, is a distribution package (like Mullvad's) that:
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

# Match the current app: an x86_64 build that runs under Rosetta on Apple
# Silicon. Override TARGET to build natively. CLANG_TARGET is for entrypoint.c.
TARGET="${TARGET:-x86_64-apple-darwin}"
CLANG_TARGET="${CLANG_TARGET:-x86_64-apple-darwin}"

# Keep in sync with LSMinimumSystemVersion in template.app/Contents/Info.plist.
# Without this the binary inherits the build host's SDK as its floor and crashes
# on launch on older systems; setting it makes the toolchain weak-link
# newer-than-target symbols and stamp LC_BUILD_VERSION correctly.
export MACOSX_DEPLOYMENT_TARGET=10.15

VERSION="${VERSION:-$(git -C "$REPO_ROOT" describe --always 2>/dev/null || echo 0.0.0)}"

# Optional signing/notarization (all no-ops if unset — a local unsigned pkg
# installs fine via `sudo installer -pkg output/Geph.pkg -target /`):
#   APP_SIGN_ID        "Developer ID Application: ..."   (codesign the app + manager)
#   INSTALLER_SIGN_ID  "Developer ID Installer: ..."     (sign the .pkg)
#   NOTARY_PROFILE     notarytool --keychain-profile name (notarize + staple)
APP_SIGN_ID="${APP_SIGN_ID:-}"
INSTALLER_SIGN_ID="${INSTALLER_SIGN_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

echo ">> building Geph $VERSION for $TARGET"

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

rustup target add "$TARGET" >/dev/null 2>&1 || true

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

# entrypoint shim (chdir into the bundle, exec ./bin/gephgui-wry)
clang -target "$CLANG_TARGET" -mmacosx-version-min="$MACOSX_DEPLOYMENT_TARGET" \
    -Os -Wall -Wextra -o "$BUILD_APP/Contents/MacOS/entrypoint" "$MACOS_DIR/entrypoint.c"

# GUI (unprivileged front-end) -> Contents/MacOS/bin
cargo install --force --locked --target "$TARGET" \
    --path "$REPO_ROOT/gephgui-wry" --root "$CARGO_OUT/gui"
cp "$CARGO_OUT/gui/bin/gephgui-wry" "$BUILD_APP/Contents/MacOS/bin"

# Privileged manager (geph5 crate, binary name `geph5`) -> Contents/Resources/geph.
# The LaunchDaemon plist points here; the CLI subcommands (connect/status/…)
# are the same binary.
cargo install --force --locked --target "$TARGET" \
    --path "$REPO_ROOT/geph5/binaries/geph5-app" --root "$CARGO_OUT/manager"
cp "$CARGO_OUT/manager/bin/geph5" "$BUILD_APP/Contents/Resources/geph"

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
    for f in Contents/Resources/geph Contents/MacOS/bin Contents/MacOS/entrypoint; do
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

productbuild "${PRODUCTBUILD_ARGS[@]}" "$OUTPUT/Geph.pkg"

# ---- 7. optional notarize + staple ---------------------------------------

if [ -n "$NOTARY_PROFILE" ]; then
    echo ">> notarizing"
    xcrun notarytool submit "$OUTPUT/Geph.pkg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$OUTPUT/Geph.pkg"
fi

# ---- 8. cleanup intermediates --------------------------------------------

rm -rf "$STAGE" "$CARGO_OUT" "$MACOS_DIR/geph-component.pkg"

echo ">> done: $OUTPUT/Geph.pkg"
