#!/bin/bash

rsync -aW --delete template.app/ build.app/
cargo install --locked --target x86_64-apple-darwin --path ../gephgui-wry
cp $(which gephgui-wry) build.app/Contents/MacOS/bin
curl https://f001.backblazeb2.com/file/geph-dl/geph4-binaries/$(cat ../blobs/linux-x64/VERSION)/geph4-client-macos-universal > build.app/Contents/MacOS/bin/geph4-client
chmod +x build.app/Contents/MacOS/bin/geph4-client

mkdir dist
mv build.app dist/Geph.app
ditto -c -k --sequesterRsrc --keepParent ./dist/Geph.app geph-macos.zip