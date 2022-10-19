#!/bin/bash

rsync -aW --delete template.app/ build.app/
cargo install --locked --path ../gephgui-wry
cp $(which gephgui-wry) build.app/Contents/MacOS/bin
curl https://f001.backblazeb2.com/file/geph-dl/geph4-binaries/$(cat ../blobs/linux-x64/VERSION)/geph4-client-macos-amd64 > build.app/Contents/MacOS/bin/geph4-client
chmod +x build.app/Contents/MacOS/bin/geph4-client

mkdir dist
mv build.app dist/Geph.app
./create-dmg --volname Geph --app-drop-link 400 0 geph-macos.dmg ./dist/