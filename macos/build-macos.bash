#!/bin/bash

rsync -aW --delete template.app/ build.app/
cargo install --force --locked --target x86_64-apple-darwin --path ../gephgui-wry
cp $(which gephgui-wry) build.app/Contents/MacOS/bin

mkdir dist
mv build.app dist/Geph.app
ditto -c -k --sequesterRsrc --keepParent ./dist/Geph.app geph-macos.zip