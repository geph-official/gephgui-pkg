#!/bin/bash
set -e

cd `dirname "$(readlink -f "$0")"`

export VERSION=$(git describe --always)

ISCC="./iscc/ISCC.exe"
mkdir iscc
unzip IS6.zip -d iscc
cargo install --locked --path ../gephgui-wry


cp $(which gephgui-wry) ../blobs/win-ia32/

sh -c "$ISCC setup.iss"