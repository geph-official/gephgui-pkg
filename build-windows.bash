#!/bin/bash
#
# Build the Windows installer on a local Windows build machine (git-bash).
# Everything comes from this repo's submodules; the result is
# ./output/geph-windows-<version>.exe.
#
# All build work happens in a machine-local staging area (see build-common.bash)
# so this checkout can be shared with the macOS/Linux build machines (Syncthing,
# NFS, ...) and the per-OS builds can run concurrently.

set -e

cd "$(dirname "$(readlink -f "$0")")"
. ./build-common.bash

export VERSION="${VERSION:-$(git describe --always)}"
ARTIFACT="output/geph-windows-${VERSION#v}.exe"

OUTPUT="output"
mkdir -p "$OUTPUT"
# Drop stale Windows artifacts so output/ only ever holds the latest exe per OS.
rm -f "$OUTPUT"/geph-windows-*.exe

# Scrub build junk that older versions of this script left in the shared
# checkout (all gitignored), so it stops syncing to the other machines.
rm -rf windows/iscc windows/Output
rm -f blobs/win-ia32/gephgui-wry.exe blobs/win-ia32/geph5.exe blobs/win-ia32/geph5-client.exe

# Stage the sources plus the installer inputs locally: the built exes, the
# unpacked Inno Setup compiler and its Output/ all stay out of the shared
# checkout. blobs/win-ia32 seeds the stage with the vendored wintun.dll and
# WebView2 bootstrapper; setup.iss's [Files] glob picks up the whole dir
# (..\blobs\win-ia32 relative to the staged windows/ copy, same layout as the
# repo).
stage_sources
WIN="$LOCAL_BUILD_ROOT/win"
copy_tree windows "$WIN/windows" iscc Output
copy_tree blobs/win-ia32 "$WIN/blobs/win-ia32"
STAGE="$WIN/blobs/win-ia32"

# We ship a 32-bit installer (one i686 build runs on all Windows, and the
# vendored wintun.dll is x86). Target i686 explicitly rather than relying on the
# host toolchain's default — that keeps the build correct on an x86_64 dev box.
TARGET="i686-pc-windows-msvc"
rustup target add "$TARGET"

# --- Code-signing hook -------------------------------------------------------
# No Authenticode certificate is wired up yet (out of scope for now). `sign` is a
# no-op today; drop a `signtool sign ...` invocation in here later to sign each
# exe and the final installer without restructuring this script.
sign() { :; }

# --- Inno Setup compiler -----------------------------------------------------
rm -rf "$WIN/windows/iscc"
mkdir -p "$WIN/windows/iscc"
unzip -o "$WIN/windows/IS6.zip" -d "$WIN/windows/iscc"

# --- Frontend (embedded into gephgui-wry via rust-embed) ----------------------
build_frontend

# --- GUI (gephgui-wry -> gephgui-wry.exe) ------------------------------------
cargo install --locked --force --target "$TARGET" --path "$LOCAL_SRC/gephgui-wry"
cp "$(which gephgui-wry)" "$STAGE/"
sign "$STAGE/gephgui-wry.exe"

# --- Manager + engine (geph5-app -> geph5.exe, geph5-client -> geph5-client.exe)
# Built from the staged copy of the vendored ./geph5 submodule. The manager
# locates geph5-client.exe as a sibling in its own directory (see geph5-app
# `supervisor::engine_bin_path`), so both binaries must land in the same {app}
# directory the installer writes to.
(cd "$LOCAL_SRC/geph5" && cargo build --locked --release --target "$TARGET" -p geph5-app -p geph5-client --features geph5-client/aws_lambda)
GEPH5_BIN="$CARGO_TARGET_DIR/$TARGET/release"
cp "$GEPH5_BIN/geph5.exe"        "$STAGE/"
cp "$GEPH5_BIN/geph5-client.exe" "$STAGE/"
sign "$STAGE/geph5.exe"
sign "$STAGE/geph5-client.exe"

# --- WinTUN driver DLL -------------------------------------------------------
# wintun.dll (x86, signed by the WireGuard project) is vendored directly in
# blobs/win-ia32/ (staged into $STAGE above), so it is already part of
# setup.iss's [Files] glob — no fetch needed here. The manager loads it at
# runtime via wintun::load() from its own directory, hence it must sit next to
# geph5.exe in {app}.
# To refresh it: download https://www.wintun.net/builds/wintun-<ver>.zip and copy
# bin/x86/wintun.dll over blobs/win-ia32/wintun.dll.

# --- Compile the installer ---------------------------------------------------
(cd "$WIN/windows" && sh -c "./iscc/ISCC.exe setup.iss")
sign "$WIN/windows/Output/geph-windows-setup.exe"
publish "$WIN/windows/Output/geph-windows-setup.exe" "$ARTIFACT"

echo ">> done: $ARTIFACT"
