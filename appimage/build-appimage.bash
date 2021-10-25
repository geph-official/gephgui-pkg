#!/bin/bash
rm -rfv AppDir
sudo apt-get update
sudo apt-get -y install libgtk-3-dev libappindicator3-dev libwebkit2gtk-4.0-dev python3-pip curl patchelf strace libpango1.0-dev libgdk-pixbuf2.0-dev
sudo pip3 install appimage-builder
sudo wget https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage -O /usr/local/bin/appimagetool
sudo wget https://github.com/AppImage/pkg2appimage/releases/download/continuous/pkg2appimage-1807-x86_64.AppImage -O /usr/local/bin/pkg2appimage
sudo chmod +x /usr/local/bin/appimagetool
sudo chmod +x /usr/local/bin/pkg2appimage


mkdir -p AppDir/usr/local/bin
(cd ../blobs/linux-x64 && sh ./pull-geph4-client.sh)
#cp ../blobs/linux-x64/geph4-client AppDir/usr/local/bin
#cp ../blobs/linux-x64/pac AppDir/usr/local/bin
#chmod +x AppDir/usr/local/bin/*

cd ../gephgui-wry
# git submodule update --init --recursive

rm -rfv target/appimage
CARGO_TARGET_DIR=target/appimage/ cargo build --locked --release
cp target/appimage/release/gephgui-wry ../appimage/

cd ../appimage
#appimage-builder --skip-test
pkg2appimage appimage.yml