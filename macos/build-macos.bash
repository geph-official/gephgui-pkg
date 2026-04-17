#!/bin/bash

set -e

rsync -aW --delete template.app/ build.app/
clang -target x86_64-apple-darwin -Os -Wall -Wextra -o build.app/Contents/MacOS/entrypoint entrypoint.c
cargo install --force --locked --target x86_64-apple-darwin --path ../gephgui-wry
cp $(which gephgui-wry) build.app/Contents/MacOS/bin

mkdir dist
mv build.app dist/Geph.app
ditto -c -k --sequesterRsrc --keepParent ./dist/Geph.app geph-macos.zip
