export VERSION=`cat VERSION`

# Retry indefinitely until the file is no longer 404
while true; do
    echo "Attempting to download geph4-client version $VERSION..."
    
    # Perform the curl request and capture the HTTP status code
    HTTP_STATUS=$(curl -w "%{http_code}" -o geph4-client -s https://f001.backblazeb2.com/file/geph-dl/geph4-binaries/$VERSION/geph4-client-linux-amd64)

    if [ "$HTTP_STATUS" -eq 200 ]; then
        echo "Download successful!"
        chmod +x geph4-client  # Ensure the downloaded file is executable
        break
    else
        echo "File not available (HTTP $HTTP_STATUS). Retrying in 5 seconds..."
        rm -f geph4-client  # Clean up partial files
        sleep 5
    fi
done