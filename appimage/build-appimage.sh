#!/bin/bash

set -e

# Create a temporary directory for building the AppImage
BUILD_DIR=$(mktemp -d)
APP_DIR="$BUILD_DIR/GephGui.AppDir"
mkdir -p "$APP_DIR/usr/bin"
mkdir -p "$APP_DIR/usr/lib"
mkdir -p "$APP_DIR/usr/share/applications"
mkdir -p "$APP_DIR/usr/share/icons/hicolor/256x256/apps"

# Build the application
echo "Building Geph GUI..."
cd gephgui-wry
git submodule update --init --recursive
(cd gephgui && npm ci && npm run build)

# Run cargo build in Ubuntu 18.04 Docker container
docker run --rm --network=host \
  -v "$(pwd)":/app \
  -w /app \
  ubuntu:22.04 \
  bash -c "apt-get update \
    && apt-get install -y build-essential pkg-config libssl-dev curl libwebkit2gtk-4.1-dev \
    && curl https://sh.rustup.rs -sSf | sh -s -- -y \
    && . /root/.cargo/env \
    && cargo build --release"


# Copy the built binary and necessary files
echo "Copying files..."
cp gephgui-wry/target/release/gephgui-wry "$APP_DIR/usr/bin/"
cp blobs/linux-x64/pac-real "$APP_DIR/usr/bin/pac"
cp blobs/linux-x64/pkexec-appimage "$APP_DIR/usr/bin/pkexec"
cp flatpak/icons/io.geph.GephGui.desktop "$APP_DIR/usr/share/applications/io.geph.GephGui.desktop"
cp flatpak/icons/256x256/apps/io.geph.GephGui.png "$APP_DIR/usr/share/icons/hicolor/256x256/apps/io.geph.GephGui.png"
cp flatpak/icons/256x256/apps/io.geph.GephGui.png "$APP_DIR/io.geph.GephGui.png"
cp flatpak/icons/io.geph.GephGui.desktop "$APP_DIR/io.geph.GephGui.desktop"

# Create the AppRun file
cat <<EOF > "$APP_DIR/AppRun"
#!/bin/bash
export PATH="\$APPDIR/usr/bin/":\$PATH
exec gephgui-wry "\$@"
EOF

chmod +x "$APP_DIR/AppRun"

# Download the AppImage tool
wget -O appimagetool "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
chmod +x appimagetool

# Build the AppImage
echo "Building AppImage from $APP_DIR..."
ARCH=x86_64 ./appimagetool "$APP_DIR" GephGui-x86_64.AppImage

echo "AppImage created: GephGui-x86_64.AppImage"

# Clean up
rm -rf "$BUILD_DIR"
rm appimagetool
