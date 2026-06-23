#!/bin/bash

set -e

# Minimum macOS version we support. Without this, the binary inherits the build
# host's SDK (the macOS 14 CI runner) as its floor and crashes on launch on
# anything older. Setting it makes clang/rustc/ld weak-link newer-than-target
# symbols and stamp LC_BUILD_VERSION correctly, so dyld accepts the app on
# older systems. Keep this in sync with LSMinimumSystemVersion in the Info.plist.
export MACOSX_DEPLOYMENT_TARGET=10.15

rsync -aW --delete template.app/ build.app/
clang -target x86_64-apple-darwin -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET -Os -Wall -Wextra -o build.app/Contents/MacOS/entrypoint entrypoint.c
cargo install --force --locked --target x86_64-apple-darwin --path ../gephgui-wry
cp $(which gephgui-wry) build.app/Contents/MacOS/bin

mkdir dist
mv build.app dist/Geph.app
ditto -c -k --sequesterRsrc --keepParent ./dist/Geph.app geph-macos.zip
