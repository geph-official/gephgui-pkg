#!/bin/bash
rm -rfv AppDir
sudo apt-get update
sudo apt-get -y install libgtk-3-dev libappindicator3-dev libwebkit2gtk-4.0-dev python3-pip curl patchelf strace libpango1.0-dev libgdk-pixbuf2.0-dev

# Install appimagetool AppImage
sudo wget https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage -O /opt/appimagetool

# workaround AppImage issues with Docker
cd /opt/; sudo chmod +x appimagetool; sed -i 's|AI\x02|\x00\x00\x00|' appimagetool; sudo ./appimagetool --appimage-extract
sudo mv /opt/squashfs-root /opt/appimagetool.AppDir
sudo ln -s /opt/appimagetool.AppDir/AppRun /usr/local/bin/appimagetool

sudo wget https://github.com/AppImage/pkg2appimage/releases/download/continuous/pkg2appimage-1807-x86_64.AppImage -O /opt/pkg2appimage
cd /opt/; sudo chmod +x pkg2appimage; sed -i 's|AI\x02|\x00\x00\x00|' pkg2appimage; sudo ./pkg2appimage --appimage-extract
sudo mv /opt/squashfs-root /opt/pkg2appimage.AppDir
sudo ln -s /opt/pkg2appimage.AppDir/AppRun /usr/local/bin/pkg2appimage


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