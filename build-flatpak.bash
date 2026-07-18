#!/bin/bash
# Build the Flatpak bundle locally. Result: ./output/geph-linux-<version>.flatpak
#
# Prerequisites on the build machine (Debian/Ubuntu names): flatpak,
# flatpak-builder, musl-tools, and a rustup-managed Rust toolchain. The GUI
# itself (frontend + gephgui-wry) is built INSIDE the sandbox by the manifest,
# so no npm/webkit deps are needed on the host.
#
# All host-side build work happens in machine-local dirs (see build-common.bash)
# so this checkout can be shared with the Windows/macOS build machines
# (Syncthing, NFS, ...) and the per-OS builds can run concurrently. The only
# thing written into the checkout besides output/ is blobs/linux-x64 (below).

set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
. ./build-common.bash

VERSION="${VERSION:-$(git describe --always)}"
ARTIFACT="output/geph-linux-${VERSION#v}.flatpak"
mkdir -p output
# Drop stale Flatpak artifacts so output/ only ever holds the latest per OS.
rm -f output/geph-linux-*.flatpak

# Scrub flatpak-builder state that older versions of this script left in the
# shared checkout (all gitignored build junk), so it stops syncing to the
# other machines. It now lives under $LOCAL_BUILD_ROOT/flatpak instead.
rm -rf build-dir repo .flatpak-builder

# Persistent cross-build cache for the in-sandbox gephgui-wry module (rustup
# toolchain, cargo registry + target/, npm cache). The manifest mounts this dir
# into that module's build via --filesystem; see flatpak/io.geph.GephGui.yml.
# Wipe it if you ever need a clean-room rebuild.
mkdir -p /var/tmp/geph-flatpak-cache

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
# stages out to the host. Build it from a machine-local staged copy of the
# geph5 submodule (never in-checkout — the Windows build compiles the same
# tree concurrently on another machine), then publish the binaries into
# blobs/linux-x64 for the manifest's `host-manager-bin` module. That dir is
# only ever written by this script, so it's safe in the shared checkout.
rustup target add x86_64-unknown-linux-musl
stage_geph5
( cd "$LOCAL_SRC/geph5" && cargo build --locked --release --target x86_64-unknown-linux-musl -p geph5-app -p geph5-client --features geph5-client/aws_lambda )
mkdir -p blobs/linux-x64
publish "$CARGO_TARGET_DIR/x86_64-unknown-linux-musl/release/geph5"        blobs/linux-x64/geph5
publish "$CARGO_TARGET_DIR/x86_64-unknown-linux-musl/release/geph5-client" blobs/linux-x64/geph5-client

# flatpak-builder's build dir, state dir (.flatpak-builder) and OSTree repo all
# live under the machine-local root. The manifest's dir sources are resolved
# relative to the manifest file, so they still read from this checkout.
FP="$LOCAL_BUILD_ROOT/flatpak"
mkdir -p "$FP"
flatpak-builder --force-clean --install-deps-from flathub --user \
    --state-dir="$FP/flatpak-builder" \
    "$FP/build-dir" flatpak/io.geph.GephGui.yml --repo="$FP/repo"
flatpak build-bundle "$FP/repo" "$FP/bundle.flatpak" io.geph.GephGui \
    --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo
publish "$FP/bundle.flatpak" "$ARTIFACT"
rm -f "$FP/bundle.flatpak"

echo ">> done: $ARTIFACT"
