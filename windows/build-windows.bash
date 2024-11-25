#!/bin/bash
set -e

cd `dirname "$(readlink -f "$0")"`

export VERSION=$(cat ../blobs/linux-x64/VERSION)

ISCC="./iscc/ISCC.exe"
mkdir iscc
unzip IS6.zip -d iscc
cargo install --locked --path ../gephgui-wry

# Retry indefinitely until the file is no longer 404
echo "Downloading geph4-client for Windows..."
while true; do
    # Perform the curl request and capture the HTTP status code
    HTTP_STATUS=$(curl -w "%{http_code}" -o ../blobs/win-ia32/geph4-client.exe -s https://f001.backblazeb2.com/file/geph-dl/geph4-binaries/$VERSION/geph4-client-windows-i386.exe)

    if [ "$HTTP_STATUS" -eq 200 ]; then
        echo "Download successful!"
        break
    else
        echo "File not available (HTTP $HTTP_STATUS). Retrying in 5 seconds..."
        rm -f ../blobs/win-ia32/geph4-client.exe  # Clean up any partial files
        sleep 5
    fi
done

cp $(which gephgui-wry) ../blobs/win-ia32/

sh -c "$ISCC setup.iss"