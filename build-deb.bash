#!/bin/bash
# Build the Debian package inside an Ubuntu 22.04 Docker container, so the
# resulting .deb links against a predictably old glibc/webkit regardless of the
# build machine's own distro. The actual build is debian/build-deb-inner.sh,
# which runs inside the container. Result: ./output/geph-linux-<version>.deb

set -e

cd "$(dirname "$(readlink -f "$0")")"
REPO_ROOT="$PWD"

export VERSION="${VERSION:-$(git describe --always)}"
mkdir -p output

# Get current user and group IDs so the artifacts land owned by the host user.
USER_ID=$(id -u)
GROUP_ID=$(id -g)
echo "Starting Ubuntu 22.04 Docker build environment..."

docker run --rm -i \
  -v "$REPO_ROOT:/app" \
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
      libwebkit2gtk-4.1-dev \
      libgtk-3-dev \
      libayatana-appindicator3-dev \
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
      # Make Rust available in the path
      export PATH=/home/builduser/.cargo/bin:\$PATH

      # Also explicitly export VERSION for use inside build-deb-inner.sh
      export VERSION=\$(printenv VERSION)

      cd /app
      # The repo (and its submodules) belong to the host user; git inside the
      # container refuses to touch them without this.
      git config --global --add safe.directory '*'

      # Install Rust (rustup)
      curl --proto \"=https\" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path

      # Now call the actual build script
      bash /app/debian/build-deb-inner.sh
    "
EOF

echo ">> done: output/geph-linux-${VERSION#v}.deb"
