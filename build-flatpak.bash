#!/bin/bash
# Build the Flatpak bundle locally. Result: ./output/geph-linux-<version>.flatpak
#
# Prerequisites on the build machine (Debian/Ubuntu names): flatpak,
# flatpak-builder, musl-tools, and a rustup-managed Rust toolchain. The GUI
# itself (frontend + gephgui-wry) is built INSIDE the sandbox by the manifest,
# so no npm/webkit deps are needed on the host.

set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

VERSION="${VERSION:-$(git describe --always)}"
ARTIFACT="output/geph-linux-${VERSION#v}.flatpak"
mkdir -p output
# Drop stale Flatpak artifacts so output/ only ever holds the latest per OS.
rm -f output/geph-linux-*.flatpak

# Initialize only submodules that are missing (uninitialized ones are prefixed
# with '-' in `submodule status`); the manifest needs gephgui-wry, geph5, and
# flatpak/shared-modules. Deliberately do NOT `update` populated ones — you may
# be developing geph5/gephgui-wry in-tree.
git submodule status --recursive 2>/dev/null \
    | awk '/^-/ {print $2}' \
    | while read -r sm; do
        echo ">> initializing missing submodule: $sm"
        git submodule update --init --recursive "$sm"
    done

# flatpak-builder consumes this checkout via dir sources (including ../.git for
# `git describe`) and clones submodules over the file protocol.
git config --global protocol.file.allow always

flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# The privileged manager can't run inside the sandbox, so the Flatpak bundles a
# statically-linked (musl) host build of geph5 + geph5-client that the GUI
# stages out to the host. Build them into blobs/linux-x64 before the manifest's
# `host-manager-bin` module consumes them.
rustup target add x86_64-unknown-linux-musl
( cd geph5 && cargo build --release --target x86_64-unknown-linux-musl -p geph5-app -p geph5-client )
mkdir -p blobs/linux-x64
cp geph5/target/x86_64-unknown-linux-musl/release/geph5 blobs/linux-x64/geph5
cp geph5/target/x86_64-unknown-linux-musl/release/geph5-client blobs/linux-x64/geph5-client

flatpak-builder --force-clean --install-deps-from flathub --user \
    build-dir flatpak/io.geph.GephGui.yml --repo=repo
flatpak build-bundle repo "$ARTIFACT" io.geph.GephGui \
    --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo

echo ">> done: $ARTIFACT"
