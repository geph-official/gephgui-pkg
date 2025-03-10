#!/bin/bash
# Build a Debian package for gephgui-wry that also packages pac-real into /usr/local/bin/pac

set -e

# Script must be run from the root of the repository
if [ ! -f "VERSION" ]; then
  echo "Error: This script must be run from the root of the repository."
  exit 1
fi


# Read version from VERSION file
VERSION=$(cat VERSION)
PACKAGE_NAME="gephgui-wry"
ARCHITECTURE="amd64"
MAINTAINER="Geph Team <contact@geph.io>"
DEPENDS="libwebkit2gtk-4.1-0"

# Create temporary working directory
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Create Debian package structure
mkdir -p "$WORK_DIR/DEBIAN"
mkdir -p "$WORK_DIR/usr/local/bin"
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

# Build the gephgui-wry binary
echo "Building gephgui-wry..."
cd gephgui-wry
if [ ! -d "target" ]; then
  mkdir -p target
fi

# Update submodules
git submodule update --init --recursive

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

# Copy pac-real to the package directory as pac
echo "Copying pac-real to package..."
cp blobs/linux-x64/pac-real "$WORK_DIR/usr/local/bin/pac"
chmod +x "$WORK_DIR/usr/local/bin/pac"

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

# Create postinst script to set permissions
cat > "$WORK_DIR/DEBIAN/postinst" << EOF
#!/bin/bash
chmod +x /usr/local/bin/pac
chmod +x /usr/bin/gephgui-wry
EOF
chmod +x "$WORK_DIR/DEBIAN/postinst"

# Build the package
echo "Building Debian package..."
PACKAGE_FILE="${PACKAGE_NAME}_${VERSION}_${ARCHITECTURE}.deb"
dpkg-deb --build "$WORK_DIR" "$PACKAGE_FILE"

echo "Debian package built: $PACKAGE_FILE"