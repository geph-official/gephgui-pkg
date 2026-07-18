#!/bin/bash
# Build the Debian package inside an Ubuntu 22.04 Docker container, so the
# resulting .deb links against a predictably old glibc/webkit regardless of the
# build machine's own distro. The actual build is debian/build-deb-inner.sh,
# which runs inside the container. Result: ./output/geph-linux-<version>.deb
#
# The checkout is mounted read-mostly at /app; everything the build writes goes
# to /cache, a machine-local dir mounted from /var/tmp/geph-deb-cache (see
# build-common.bash, which the inner script points at it via
# GEPHGUI_PKG_BUILD_ROOT). That makes it safe to share this checkout with the
# Windows/macOS build machines (Syncthing, NFS, ...) and run the per-OS builds
# concurrently — and it doubles as a persistent cache (rustup, cargo registry,
# target/, npm) across deb builds. Wipe /var/tmp/geph-deb-cache for a
# clean-room rebuild.

set -e

cd "$(dirname "$(readlink -f "$0")")"
REPO_ROOT="$PWD"

export VERSION="${VERSION:-$(git describe --always)}"
mkdir -p output
# Drop stale deb artifacts so output/ only ever holds the latest per OS.
rm -f output/*.deb

# Machine-local build root + cache, mounted into the container. Created here
# (as the host user) so it isn't owned by root.
DEB_CACHE=/var/tmp/geph-deb-cache
mkdir -p "$DEB_CACHE"

# Get current user and group IDs so the artifacts land owned by the host user.
USER_ID=$(id -u)
GROUP_ID=$(id -g)
echo "Starting Ubuntu 22.04 Docker build environment..."

docker run --rm -i \
  -v "$REPO_ROOT:/app" \
  -v "$DEB_CACHE:/cache" \
  -w /app \
  --network=host \
  -e VERSION \
  ubuntu:22.04 bash -e << EOF
    echo "Setting up build environment as root..."
    apt-get update
    apt-get install -y \
      build-essential \
      curl \
      git \
      pkg-config \
      rsync \
      libwebkit2gtk-4.1-dev \
      libgtk-3-dev \
      libayatana-appindicator3-dev \
      libxdo-dev \
      gnupg \
      sudo

    # Install Node.js from NodeSource
    echo "Installing Node.js from NodeSource..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs

    # Create a non-root user with the same IDs as the host user
    groupadd -g $GROUP_ID builduser
    useradd -u $USER_ID -g $GROUP_ID -m builduser

    # Add user to sudoers
    echo "builduser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/builduser

    # Pass VERSION into the builduser's environment and run build
    su - builduser -c "
      # Everything the build writes (staged sources, cargo target, rustup/cargo
      # homes, npm cache) lives on the persistent machine-local /cache mount.
      export GEPHGUI_PKG_BUILD_ROOT=/cache
      export CARGO_HOME=/cache/cargo
      export RUSTUP_HOME=/cache/rustup
      export npm_config_cache=/cache/npm
      export PATH=/cache/cargo/bin:\$PATH

      # Also explicitly export VERSION for use inside build-deb-inner.sh
      export VERSION=\$(printenv VERSION)

      cd /app
      # The repo (and its submodules) belong to the host user; git inside the
      # container refuses to touch them without this.
      git config --global --add safe.directory '*'

      # Install Rust (rustup) into the cached CARGO_HOME/RUSTUP_HOME, unless a
      # previous run already left it there.
      if ! command -v cargo >/dev/null 2>&1; then
        curl --proto \"=https\" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
      fi

      # Now call the actual build script
      bash /app/debian/build-deb-inner.sh
    "
EOF

echo ">> done: output/geph-linux-${VERSION#v}.deb"
