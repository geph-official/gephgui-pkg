#!/bin/bash

set -e
apt-get update
apt-get install -y build-essential pkg-config libssl-dev curl libwebkit2gtk-4.1-dev git wget file libfuse2

# Install Node.js 22.x
echo "Installing Node.js "
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 
apt-get install nodejs

# Create a temporary directory for building the AppImage
BUILD_DIR=./AppImageBuild
APP_DIR="$BUILD_DIR/GephGui.AppDir"
mkdir -p "$APP_DIR/usr/bin"
mkdir -p "$APP_DIR/usr/lib"
mkdir -p "$APP_DIR/usr/share/applications"
mkdir -p "$APP_DIR/usr/share/icons/hicolor/256x256/apps"

# Install Rust
echo "Installing Rust..."
curl https://sh.rustup.rs -sSf | sh -s -- -y 
# Source the Rust environment
source "$HOME/.cargo/env"

# Build the application
echo "Building Geph GUI..."
git config --global --add safe.directory /app/gephgui-wry
cd gephgui-wry
#git submodule update --init --recursive
(cd gephgui && npm ci && npm run build)


cargo build --release

cd ..

# Copy the built binary and necessary files
echo "Copying files..."
cp gephgui-wry/target/release/gephgui-wry "$APP_DIR/usr/bin/"
cp blobs/linux-x64/pac-real "$APP_DIR/usr/bin/pac"
cp blobs/linux-x64/pkexec-appimage "$APP_DIR/usr/bin/pkexec"
cp flatpak/icons/io.geph.GephGui.desktop "$APP_DIR/usr/share/applications/io.geph.GephGui.desktop"
cp flatpak/icons/256x256/apps/io.geph.GephGui.png "$APP_DIR/usr/share/icons/hicolor/256x256/apps/io.geph.GephGui.png"
cp flatpak/icons/256x256/apps/io.geph.GephGui.png "$APP_DIR/io.geph.GephGui.png"
cp flatpak/icons/io.geph.GephGui.desktop "$APP_DIR/io.geph.GephGui.desktop"

# Copy WebKit2GTK library
echo "Copying WebKit2GTK library..."
if [ -f "/lib/x86_64-linux-gnu/libwebkit2gtk-4.1.so.0" ]; then
  mkdir -p "$APP_DIR/lib/x86_64-linux-gnu/"
  cp "/lib/x86_64-linux-gnu/libwebkit2gtk-4.1.so.0" "$APP_DIR/lib/x86_64-linux-gnu/"
  # Copy dependencies if needed (you might need to add more as required)
  # Use ldd to identify dependencies
  echo "Copying dependencies for WebKit2GTK..."
  ldd /lib/x86_64-linux-gnu/libwebkit2gtk-4.1.so.0 | grep "=> /" | awk '{print $3}' | xargs -I '{}' cp -v '{}' "$APP_DIR/lib/x86_64-linux-gnu/" || true
else
  echo "Warning: libwebkit2gtk-4.1.so.0 not found in /lib/x86_64-linux-gnu/"
  # Try to find it elsewhere
  WEBKIT_LIB=$(find /usr -name "libwebkit2gtk-4.1.so.0" 2>/dev/null | head -n 1)
  if [ -n "$WEBKIT_LIB" ]; then
    echo "Found WebKit2GTK at $WEBKIT_LIB"
    WEBKIT_DIR=$(dirname "$WEBKIT_LIB")
    mkdir -p "$APP_DIR/$(dirname $WEBKIT_DIR)"
    cp "$WEBKIT_LIB" "$APP_DIR/$WEBKIT_DIR/"
    # Copy dependencies
    echo "Copying dependencies for WebKit2GTK..."
    ldd "$WEBKIT_LIB" | grep "=> /" | awk '{print $3}' | xargs -I '{}' cp -v '{}' "$APP_DIR/$WEBKIT_DIR/" || true
  else
    echo "Error: Could not find libwebkit2gtk-4.1.so.0 on the system."
    exit 1
  fi
fi

# Create a file to list files to exclude from the AppImage
cat <<EOF > "$BUILD_DIR/.appimageignore"
# Exclude temporary, cache, and unneeded files
**/__pycache__
**/*.pyc
**/*.pyo
**/.git
**/.gitignore
**/node_modules
**/*.map
**/*.tmp
**/*.log
EOF

# Create the AppRun file
cat <<EOF > "$APP_DIR/AppRun"
#!/bin/bash
HERE="\$(dirname "\$(readlink -f "\${0}")")"
export PATH="\$HERE/usr/bin/:":\$PATH
# Add library path for WebKit2GTK
export LD_LIBRARY_PATH="\$HERE/lib/x86_64-linux-gnu/:\$HERE/usr/lib/:\$LD_LIBRARY_PATH"
exec "\$HERE/usr/bin/gephgui-wry" "\$@"
EOF

chmod +x "$APP_DIR/AppRun"