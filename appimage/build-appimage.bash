#!/bin/bash
sudo apt-get -y install libgtk-3-dev libappindicator3-dev libwebkit2gtk-4.0-dev python3-pip curl 
sudo pip3 install appimage-builder

mkdir -p AppDir/usr/local/bin
(cd ../blobs/linux-x64 && sh ./pull-geph4-client.sh)
cp ../blobs/linux-x64/geph4-client AppDir/usr/local/bin
cp ../blobs/linux-x64/pac AppDir/usr/local/bin
chmod +x AppDir/usr/local/bin/*

cd ../gephgui-wry
# git submodule update --init --recursive

CARGO_TARGET_DIR=target/appimage/ cargo build --release
cp target/appimage/release/gephgui-wry ../appimage/AppDir/usr/local/bin

