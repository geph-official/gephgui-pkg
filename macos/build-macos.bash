#!/bin/bash

rsync -aW --delete template.app/ build.app/
cargo install cargo-bundle
cargo bundle
cp ../target/debug/bundle/osx/Geph.app build.app/Contents/MacOS/bin

mkdir dist
mv build.app dist/Geph.app
ditto -c -k --sequesterRsrc --keepParent ./dist/Geph.app geph-macos.zip
