#!/bin/bash
set -e

cd `dirname "$(readlink -f "$0")"`

export VERSION=$(cat ../blobs/linux-x64/VERSION)

ISCC="./iscc/ISCC.exe"
mkdir iscc
unzip IS6.zip -d iscc
cargo install --locked --path ../gephgui-wry

curl https://f001.backblazeb2.com/file/geph-dl/geph4-binaries/$VERSION/geph4-client-windows-i386.exe > ../blobs/win-ia32/geph4-client.exe
cp $(which gephgui-wry) ../blobs/win-ia32/

sh -c "$ISCC setup.iss"
