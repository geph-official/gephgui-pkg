#!/bin/bash

rsync -aW --delete template.app/ build.app/
cargo install --locked --target x86_64-apple-darwin --path ../gephgui-wry
cp $(which gephgui-wry) build.app/Contents/MacOS/bin

# Retry indefinitely until the file is no longer 404
echo "Downloading geph4-client for macOS..."
while true; do
    # Perform the curl request and capture the HTTP status
    echo "Downloading https://f001.backblazeb2.com/file/geph-dl/geph4-binaries/$(cat ../blobs/linux-x64/VERSION)/geph4-client-macos-universal)"
    HTTP_STATUS=$(curl -w "%{http_code}" -o build.app/Contents/MacOS/bin/geph4-client -s https://f001.backblazeb2.com/file/geph-dl/geph4-binaries/$(cat ../blobs/linux-x64/VERSION)/geph4-client-macos-universal)

    if [ "$HTTP_STATUS" -eq 200 ]; then
        echo "Download successful!"
        chmod +x build.app/Contents/MacOS/bin/geph4-client
        break
    else
        echo "File not available (HTTP $HTTP_STATUS). Retrying in 5 seconds..."
        rm -f build.app/Contents/MacOS/bin/geph4-client  # Clean up any partial files
        sleep 5
    fi
done

mkdir dist
mv build.app dist/Geph.app
ditto -c -k --sequesterRsrc --keepParent ./dist/Geph.app geph-macos.zip