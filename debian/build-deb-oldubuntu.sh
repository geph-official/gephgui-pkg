#!/bin/bash
# Build a Debian package for gephgui-wry using Docker with Ubuntu 22.04

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Get current user and group IDs
USER_ID=$(id -u)
GROUP_ID=$(id -g)
echo "Starting Ubuntu 22.04 Docker build environment..."

# Use Docker to build in Ubuntu 22.04
docker run --rm -i \
  -v "$REPO_ROOT:/app" \
  -w /app \
  --network=host \
  ubuntu:22.04 bash -e << EOF
    echo "Setting up build environment as root..."
    apt-get update
    apt-get install -y \
      build-essential \
      curl \
      git \
      pkg-config \
      libwebkit2gtk-4.1-dev \
      libgtk-3-dev \
      libayatana-appindicator3-dev \
      gnupg \
      sudo

    # Install Node.js from NodeSource
    echo "Installing Node.js from NodeSource..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
    
    # Install Rust system-wide
    echo "Installing Rust..."
    
    # Create a non-root user with the same IDs as the host user
    groupadd -g $GROUP_ID builduser
    useradd -u $USER_ID -g $GROUP_ID -m builduser
    
    # Add user to sudoers
    echo "builduser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/builduser
    
    # Switch to the build user for the actual build
    su - builduser -c "export PATH=/home/builduser/.cargo/bin:\$PATH && cd /app && git config --global --add safe.directory /app && curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path && bash /app/debian/build-deb.sh"
EOF

echo "Build complete!"