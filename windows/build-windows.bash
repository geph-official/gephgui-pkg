#!/bin/bash
set -e

cd `dirname "$(readlink -f "$0")"`

export VERSION=$(git describe --always)

STAGE="../blobs/win-ia32"

# We ship a 32-bit installer (one i686 build runs on all Windows, and the
# vendored wintun.dll is x86). Target i686 explicitly rather than relying on the
# host toolchain's default — that keeps the build correct on an x86_64 dev box,
# and is a no-op on the i686 CI runner.
TARGET="i686-pc-windows-msvc"
rustup target add "$TARGET"

# --- Code-signing hook -------------------------------------------------------
# No Authenticode certificate is wired up yet (out of scope for now). `sign` is a
# no-op today; drop a `signtool sign ...` invocation in here later to sign each
# exe and the final installer without restructuring this script.
sign() { :; }

# --- Inno Setup compiler -----------------------------------------------------
ISCC="./iscc/ISCC.exe"
rm -rf iscc
mkdir iscc
unzip -o IS6.zip -d iscc

# --- GUI (gephgui-wry -> gephgui-wry.exe) ------------------------------------
# NOTE: the embedded frontend (gephgui/dist) must already be built via npm before
# this runs — the CI does that in a separate step.
cargo install --locked --force --target "$TARGET" --path ../gephgui-wry
cp "$(which gephgui-wry)" "$STAGE/"
sign "$STAGE/gephgui-wry.exe"

# --- Manager + engine (geph5-app -> geph5.exe, geph5-client -> geph5-client.exe)
# Built from the vendored ../geph5 submodule (currently the new-new-vpn branch).
# The manager locates geph5-client.exe as a sibling in its own directory (see
# geph5-app `supervisor::engine_bin_path`), so both binaries must land in the
# same {app} directory the installer writes to.
(cd ../geph5 && cargo build --locked --release --target "$TARGET" -p geph5-app -p geph5-client)
GEPH5_BIN="../geph5/target/$TARGET/release"
cp "$GEPH5_BIN/geph5.exe"        "$STAGE/"
cp "$GEPH5_BIN/geph5-client.exe" "$STAGE/"
sign "$STAGE/geph5.exe"
sign "$STAGE/geph5-client.exe"

# --- WinTUN driver DLL -------------------------------------------------------
# wintun.dll (x86, signed by the WireGuard project) is vendored directly in
# blobs/win-ia32/, so it is already part of the [Files] glob below — no fetch
# needed here. The manager loads it at runtime via wintun::load() from its own
# directory, hence it must sit next to geph5.exe in {app}.
# To refresh it: download https://www.wintun.net/builds/wintun-<ver>.zip and copy
# bin/x86/wintun.dll over blobs/win-ia32/wintun.dll.

# --- Compile the installer ---------------------------------------------------
sh -c "$ISCC setup.iss"
sign "Output/geph-windows-setup.exe"
