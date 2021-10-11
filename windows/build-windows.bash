#!/bin/bash
cd `dirname "$(readlink -f "$0")"`

export VERSION=$(cat ../VERSION)

ISCC="'/c/Program Files (x86)/Inno Setup 6/ISCC.exe'"
cargo install --locked --path ../gephgui-wry

curl https://f001.backblazeb2.com/file/geph-dl/geph4-binaries/$VERSION/geph4-client-windows-i386.exe > ../blobs/win-ia32/geph4-client.exe
cp $(which gephgui-wry) ../blobs/win-ia32/
sh -c "$ISCC setup.iss"