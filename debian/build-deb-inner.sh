#!/bin/bash
# Build a Debian package containing the Geph GUI (gephgui-wry) plus the privileged
# manager (geph5) and engine (geph5-client), and register the manager as a systemd
# service on install. Runs INSIDE the Ubuntu 22.04 container that the top-level
# build-deb.bash sets up — run that instead of this directly.
# Result: ./output/geph-linux-<version>.deb

set -e

cd "$(dirname "$(readlink -f "$0")")"

# Get version using git describe
PACKAGE_NAME="gephgui-wry"
ARCHITECTURE="amd64"
MAINTAINER="Geph Team <contact@geph.io>"
DEPENDS="libwebkit2gtk-4.1-0, nftables, iproute2, policykit-1"
VERSION="${VERSION:-$(git describe --always)}"
VERSION=${VERSION#v}

OUTPUT="output"
mkdir -p "$OUTPUT"

# Create temporary working directory
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Create Debian package structure
mkdir -p "$WORK_DIR/DEBIAN"
mkdir -p "$WORK_DIR/usr/bin"
mkdir -p "$WORK_DIR/usr/share/applications"
mkdir -p "$WORK_DIR/usr/share/icons/hicolor/256x256/apps"

# Create control file
cat > "$WORK_DIR/DEBIAN/control" << EOF
Package: $PACKAGE_NAME
Version: $VERSION
Section: net
Priority: optional
Architecture: $ARCHITECTURE
Maintainer: $MAINTAINER
Depends: $DEPENDS
Description: Geph GUI using WRY
 Geph is a privacy-focused VPN with advanced censorship circumvention features.
 This package contains the GUI client built with WRY.
EOF

# Update submodules
git submodule update --init --recursive

# Build the gephgui-wry binary
echo "Building gephgui-wry..."
cd gephgui-wry

# Build the frontend
cd gephgui
npm install -f
npm run build
cd ..

# Build the Rust backend
cargo build --release

# Copy the built binary to the package directory
cp target/release/gephgui-wry "$WORK_DIR/usr/bin/"
cd ..

# Build the privileged manager (geph5) and engine (geph5-client) from the geph5
# submodule and install both side-by-side (geph5 resolves geph5-client as a sibling
# of its own executable).
echo "Building geph5 manager + engine..."
( cd geph5 && cargo build --release -p geph5-app -p geph5-client )
cp geph5/target/release/geph5 "$WORK_DIR/usr/bin/"
cp geph5/target/release/geph5-client "$WORK_DIR/usr/bin/"

# Create desktop file
cat > "$WORK_DIR/usr/share/applications/geph.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Geph
Comment=Privacy and censorship circumvention tool
Exec=/usr/bin/gephgui-wry
Icon=geph
Terminal=false
Categories=Network;
EOF

# Copy icon (if available)
if [ -f "flatpak/icons/256x256/io.geph.GephGui.png" ]; then
  cp flatpak/icons/256x256/io.geph.GephGui.png "$WORK_DIR/usr/share/icons/hicolor/256x256/apps/geph.png"
fi

# postinst: register + start the privileged manager as a systemd service. Don't fail
# the install if systemd isn't running (e.g. building inside a container); the GUI
# offers to set it up via pkexec on first launch as a fallback.
cat > "$WORK_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e
chmod +x /usr/bin/gephgui-wry /usr/bin/geph5 /usr/bin/geph5-client
if [ -d /run/systemd/system ]; then
  /usr/bin/geph5 register-manager || echo "geph5 register-manager failed; the GUI will retry on launch"
fi
EOF
chmod +x "$WORK_DIR/DEBIAN/postinst"

# prerm: tear the manager back down on removal, while the binary still exists.
cat > "$WORK_DIR/DEBIAN/prerm" << 'EOF'
#!/bin/bash
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
  /usr/bin/geph5 unregister-manager || true
fi
EOF
chmod +x "$WORK_DIR/DEBIAN/prerm"

# Build the package
echo "Building Debian package..."
PACKAGE_FILE="$OUTPUT/geph-linux-${VERSION}.deb"
dpkg-deb --build "$WORK_DIR" "$PACKAGE_FILE"

echo "Debian package built: $PACKAGE_FILE"
