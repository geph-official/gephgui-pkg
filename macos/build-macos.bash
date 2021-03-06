#!/bin/bash

rsync -aW --delete template.app/ build.app/
cargo install --locked --path ../gephgui-wry
cp $(which gephgui-wry) build.app/Contents/MacOS/bin
curl https://f001.backblazeb2.com/file/geph-dl/geph4-binaries/$(cat ../VERSION)/geph4-client-macos-amd64 > build.app/Contents/MacOS/bin/geph4-client
chmod +x build.app/Contents/MacOS/bin/geph4-client