#!/bin/bash

# Must Install create-dmg first
# brew install create-dmg

echo "Starting DMG creation process..."

# Create release directory if it doesn't exist
RELEASE_DIR="./release"
echo "Creating release directory..."
mkdir -p "$RELEASE_DIR"

# Create a temporary directory for DMG contents
DMG_TEMP_DIR="$RELEASE_DIR/dmg_temp"
echo "Creating temporary directory..."
mkdir -p "$DMG_TEMP_DIR"

# Verify app exists
if [ ! -d "./dist/AppSwitcher/AppSwitcher.app" ]; then
    echo "Error: AppSwitcher.app not found in dist directory!"
    echo "Current directory: $(pwd)"
    echo "Contents of dist directory:"
    ls -la ./dist/
    exit 1
fi

# Copy the app to the temporary directory
echo "Copying application files..."
cp -R "./dist/AppSwitcher/AppSwitcher.app" "$DMG_TEMP_DIR/"

# Verify copy was successful
if [ ! -d "$DMG_TEMP_DIR/AppSwitcher.app" ]; then
    echo "Error: Failed to copy AppSwitcher.app to temporary directory!"
    echo "Contents of temporary directory:"
    ls -la "$DMG_TEMP_DIR"
    exit 1
fi

# Clean up any existing temporary files
echo "Cleaning up any existing temporary files..."
rm -f "$RELEASE_DIR/AppSwitcher.temp.dmg"
rm -f "$RELEASE_DIR/AppSwitcher.dmg"

# Create a read/write DMG
echo "Creating initial DMG..."
echo "Running: hdiutil create -fs HFS+ -srcfolder \"$DMG_TEMP_DIR\" -volname \"AppSwitcher\" -format UDRW \"$RELEASE_DIR/AppSwitcher.temp.dmg\""
HDIUTIL_CREATE_OUTPUT=$(hdiutil create -fs HFS+ -srcfolder "$DMG_TEMP_DIR" -volname "AppSwitcher" -format UDRW "$RELEASE_DIR/AppSwitcher.temp.dmg" 2>&1)
echo "hdiutil create output:"
echo "$HDIUTIL_CREATE_OUTPUT"

# Verify temp DMG was created
if [ ! -f "$RELEASE_DIR/AppSwitcher.temp.dmg" ]; then
    echo "Error: Failed to create temporary DMG!"
    echo "Contents of release directory:"
    ls -la "$RELEASE_DIR"
    exit 1
fi

# Mount the DMG
echo "Mounting DMG..."
echo "Running: hdiutil attach -readwrite -noverify \"$RELEASE_DIR/AppSwitcher.temp.dmg\""
MOUNT_INFO=$(hdiutil attach -readwrite -noverify "$RELEASE_DIR/AppSwitcher.temp.dmg" 2>&1)
echo "hdiutil attach output:"
echo "$MOUNT_INFO"

if [ $? -ne 0 ]; then
    echo "Error: Failed to mount temporary DMG!"
    exit 1
fi

MOUNT_POINT=$(echo "$MOUNT_INFO" | grep 'Apple_HFS' | awk '{print $3}')
if [ -z "$MOUNT_POINT" ]; then
    echo "Error: Could not determine mount point!"
    exit 1
fi

# Create Applications link
echo "Creating Applications link..."
ln -s "/Applications" "$MOUNT_POINT/Applications"

# Set window properties
echo "Setting window properties..."
osascript <<EOT
    tell application "Finder"
        tell disk "AppSwitcher"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {200, 120, 800, 520}
            set theViewOptions to the icon view options of container window
            set arrangement of theViewOptions to not arranged
            set icon size of theViewOptions to 100
            set position of item "AppSwitcher.app" of container window to {100, 200}
            set position of item "Applications" of container window to {400, 200}
            update without registering applications
            delay 1
            close
        end tell
    end tell
EOT

# Ensure the DMG is properly unmounted before conversion
echo "Unmounting DMG before conversion..."
echo "Running: hdiutil detach \"$MOUNT_POINT\" -force"
DETACH_OUTPUT=$(hdiutil detach "$MOUNT_POINT" -force 2>&1)
echo "hdiutil detach output:"
echo "$DETACH_OUTPUT"

# Wait a moment to ensure the unmount is complete
sleep 2

# Convert to compressed format with retry mechanism
echo "Converting to compressed format..."
MAX_RETRIES=3
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "Running: hdiutil convert \"$RELEASE_DIR/AppSwitcher.temp.dmg\" -format UDZO -o \"$RELEASE_DIR/AppSwitcher.dmg\""
    CONVERT_OUTPUT=$(hdiutil convert "$RELEASE_DIR/AppSwitcher.temp.dmg" -format UDZO -o "$RELEASE_DIR/AppSwitcher.dmg" 2>&1)
    echo "hdiutil convert output:"
    echo "$CONVERT_OUTPUT"
    
    if [ $? -eq 0 ]; then
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Conversion attempt $RETRY_COUNT failed, retrying..."
    sleep 2
done

# Verify the final DMG was created
if [ ! -f "$RELEASE_DIR/AppSwitcher.dmg" ]; then
    echo "Error: Failed to create final DMG file after $MAX_RETRIES attempts!"
    echo "Contents of release directory:"
    ls -la "$RELEASE_DIR"
    echo "Disk space information:"
    df -h
    echo "List of mounted volumes:"
    hdiutil info
    exit 1
fi

# Clean up
echo "Cleaning up temporary files..."
rm -rf "$DMG_TEMP_DIR"
rm "$RELEASE_DIR/AppSwitcher.temp.dmg"

echo "DMG creation complete! File is located at: $RELEASE_DIR/AppSwitcher.dmg"
echo "File size: $(du -h "$RELEASE_DIR/AppSwitcher.dmg" | cut -f1)"
