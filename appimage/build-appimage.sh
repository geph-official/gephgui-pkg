#!/bin/bash

set -e

# Create output directory
mkdir -p $(pwd)/output

# Run the inner script inside an Ubuntu 22.04 Docker container
# This container will handle the entire build process
docker run --rm \
  --privileged \
  --network=host \
  -v "$(pwd)":/app \
  -v "$(pwd)/output:/output" \
  -w /app \
  debian:12 \
  bash -c "chmod +x /app/appimage/build-appimage-inner.sh && /app/appimage/build-appimage-inner.sh"


# Download the AppImage tool
wget -O appimagetool "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
chmod +x appimagetool


# Build the AppImage with optimized compression
BUILD_DIR=./AppImageBuild
APP_DIR="$BUILD_DIR/GephGui.AppDir"
echo "Building AppImage from $APP_DIR with optimized compression..."
ARCH=x86_64 ./appimagetool "$APP_DIR" GephGui-x86_64.AppImage

echo "AppImage created: GephGui-x86_64.AppImage"

# Check the size of the produced AppImage
du -h GephGui-x86_64.AppImage

rm -rfv BUILD_DIR