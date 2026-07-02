#!/bin/bash
#
# Build the Windows installer on a local Windows build machine (git-bash).
# Everything comes from this repo's submodules; the result is
# ./output/geph-windows-<version>.exe.

set -e

cd "$(dirname "$(readlink -f "$0")")"

export VERSION="${VERSION:-$(git describe --always)}"
ARTIFACT="output/geph-windows-${VERSION#v}.exe"

STAGE="blobs/win-ia32"
OUTPUT="output"
mkdir -p "$OUTPUT"

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
rm -rf windows/iscc
mkdir windows/iscc
unzip -o windows/IS6.zip -d windows/iscc

# --- Frontend (embedded into gephgui-wry via rust-embed) ----------------------
(cd gephgui-wry/gephgui && npm i -f && npm run build)

# --- GUI (gephgui-wry -> gephgui-wry.exe) ------------------------------------
cargo install --locked --force --target "$TARGET" --path gephgui-wry
cp "$(which gephgui-wry)" "$STAGE/"
sign "$STAGE/gephgui-wry.exe"

# --- Manager + engine (geph5-app -> geph5.exe, geph5-client -> geph5-client.exe)
# Built from the vendored ./geph5 submodule. The manager locates
# geph5-client.exe as a sibling in its own directory (see geph5-app
# `supervisor::engine_bin_path`), so both binaries must land in the same {app}
# directory the installer writes to.
(cd geph5 && cargo build --locked --release --target "$TARGET" -p geph5-app -p geph5-client)
GEPH5_BIN="geph5/target/$TARGET/release"
cp "$GEPH5_BIN/geph5.exe"        "$STAGE/"
cp "$GEPH5_BIN/geph5-client.exe" "$STAGE/"
sign "$STAGE/geph5.exe"
sign "$STAGE/geph5-client.exe"

# --- WinTUN driver DLL -------------------------------------------------------
# wintun.dll (x86, signed by the WireGuard project) is vendored directly in
# blobs/win-ia32/, so it is already part of setup.iss's [Files] glob — no fetch
# needed here. The manager loads it at runtime via wintun::load() from its own
# directory, hence it must sit next to geph5.exe in {app}.
# To refresh it: download https://www.wintun.net/builds/wintun-<ver>.zip and copy
# bin/x86/wintun.dll over blobs/win-ia32/wintun.dll.

# --- Compile the installer ---------------------------------------------------
(cd windows && sh -c "./iscc/ISCC.exe setup.iss")
cp windows/Output/geph-windows-setup.exe "$ARTIFACT"
sign "$ARTIFACT"

echo ">> done: $ARTIFACT"
