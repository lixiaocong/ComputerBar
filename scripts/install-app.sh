#!/bin/bash
# install-app.sh — Builds ComputerBar.app with the embedded widget extension, installs it, and launches it.
# Usage: ./scripts/install-app.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="ComputerBar"
OLD_APP_NAME="SSHBar"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_NAME.app"
OLD_INSTALL_PATH="/Applications/$OLD_APP_NAME.app"
DERIVED_DATA_DIR="$PROJECT_DIR/.xcodebuild"
XCODEPROJ="$PROJECT_DIR/${APP_NAME}.xcodeproj"
ICON_SCRIPT="$PROJECT_DIR/scripts/generate-icons.swift"
ICON_FILE="$PROJECT_DIR/Resources/AppIcon.icns"
APP_ENTITLEMENTS="$PROJECT_DIR/Resources/${APP_NAME}.entitlements"
WIDGET_ENTITLEMENTS="$PROJECT_DIR/Resources/${APP_NAME}Widget.entitlements"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
PLISTBUDDY="/usr/libexec/PlistBuddy"
BUILD_VERSION="$(date +%Y%m%d%H%M%S)"

unregister_bundle() {
    local bundle_path="$1"
    if [ -x "$LSREGISTER" ] && [ -n "$bundle_path" ]; then
        "$LSREGISTER" -u "$bundle_path" >/dev/null 2>&1 || true
    fi
}

remove_temporary_bundle() {
    local bundle_path="$1"
    unregister_bundle "$bundle_path"
    if [ -d "$bundle_path" ]; then
        rm -rf "$bundle_path"
    fi
}

remove_matching_bundles() {
    local pattern="$1"
    while IFS= read -r bundle_path; do
        remove_temporary_bundle "$bundle_path"
    done < <(compgen -G "$pattern" || true)
}

remove_installed_bundle() {
    local bundle_path="$1"
    unregister_bundle "$bundle_path"

    if [ ! -d "$bundle_path" ]; then
        return
    fi

    if command -v pluginkit >/dev/null 2>&1; then
        while IFS= read -r appex; do
            pluginkit -r "$appex" || true
        done < <(find "$bundle_path/Contents/PlugIns" -depth -name "*.appex" -print 2>/dev/null)
    fi

    rm -rf "$bundle_path"
}

refresh_widgetkit_services() {
    # Replacing a widget-bearing app can leave chronod/ControlCenter holding a
    # stale extension descriptor and make the widget disappear from the gallery.
    killall chronod >/dev/null 2>&1 || true
    killall ControlCenter >/dev/null 2>&1 || true
    killall NotificationCenter >/dev/null 2>&1 || true
}

cd "$PROJECT_DIR"

echo "==> Clearing stale ComputerBar build registrations"
remove_temporary_bundle "$APP_BUNDLE"
remove_temporary_bundle "$DERIVED_DATA_DIR/Build/Products/Release/$APP_NAME.app"
remove_temporary_bundle "$DERIVED_DATA_DIR/Build/Products/Debug/$APP_NAME.app"
remove_temporary_bundle "$PROJECT_DIR/build/DerivedData/Build/Products/Release/$APP_NAME.app"
remove_temporary_bundle "$PROJECT_DIR/build/DerivedData/Build/Products/Debug/$APP_NAME.app"
remove_temporary_bundle "$HOME/Downloads/code/computer-bar/build/$APP_NAME.app"
remove_matching_bundles "$HOME/Library/Developer/Xcode/DerivedData/$APP_NAME-*/Build/Products/Release/$APP_NAME.app"
remove_matching_bundles "$HOME/Library/Developer/Xcode/DerivedData/$APP_NAME-*/Build/Products/Debug/$APP_NAME.app"

echo "==> Clearing stale SSHBar registrations"
remove_temporary_bundle "$HOME/code/ssh-bar/build/$OLD_APP_NAME.app"
remove_temporary_bundle "$HOME/Downloads/code/ssh-bar/build/$OLD_APP_NAME.app"
remove_matching_bundles "$HOME/Library/Developer/Xcode/DerivedData/$OLD_APP_NAME-*/Build/Products/Release/$OLD_APP_NAME.app"
remove_matching_bundles "$HOME/Library/Developer/Xcode/DerivedData/$OLD_APP_NAME-*/Build/Products/Debug/$OLD_APP_NAME.app"

echo "==> Rendering app icon"
if [ -f "$ICON_SCRIPT" ]; then
    swift "$ICON_SCRIPT"
fi

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "ERROR: xcodegen is required to build the widget-enabled app."
    echo "Install it with: brew install xcodegen"
    exit 1
fi

echo "==> Generating Xcode project"
xcodegen generate

if [ ! -d "$XCODEPROJ" ]; then
    echo "ERROR: Xcode project was not generated at $XCODEPROJ"
    exit 1
fi

if [ ! -f "$APP_ENTITLEMENTS" ] || [ ! -f "$WIDGET_ENTITLEMENTS" ]; then
    echo "ERROR: Entitlements files are missing."
    exit 1
fi

echo "==> Building $APP_NAME (release)…"
rm -rf "$DERIVED_DATA_DIR"
xcodebuild \
    -project "$XCODEPROJ" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build

BUILT_APP="$DERIVED_DATA_DIR/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$BUILT_APP" ]; then
    echo "ERROR: Built app bundle not found at $BUILT_APP"
    exit 1
fi

echo "==> Creating app bundle at $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$BUILD_DIR"
cp -R "$BUILT_APP" "$APP_BUNDLE"

if [ -f "$ICON_FILE" ]; then
    echo "==> Copying app icon into bundle resources"
    mkdir -p "$APP_BUNDLE/Contents/Resources"
    cp "$ICON_FILE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo "==> Stamping bundle version $BUILD_VERSION"
if [ -x "$PLISTBUDDY" ]; then
    "$PLISTBUDDY" -c "Set :CFBundleVersion $BUILD_VERSION" "$APP_BUNDLE/Contents/Info.plist" || true
fi

if [ -f "$ICON_FILE" ] && [ -d "$APP_BUNDLE/Contents/PlugIns" ]; then
    echo "==> Copying app icon into widget extension resources"
    while IFS= read -r appex; do
        mkdir -p "$appex/Contents/Resources"
        cp "$ICON_FILE" "$appex/Contents/Resources/AppIcon.icns"
        if [ -x "$PLISTBUDDY" ]; then
            "$PLISTBUDDY" -c "Set :CFBundleVersion $BUILD_VERSION" "$appex/Contents/Info.plist" || true
        fi
    done < <(find "$APP_BUNDLE/Contents/PlugIns" -depth -name "*.appex" -print)
fi

resolve_sign_identity() {
    if [ -n "${CODESIGN_IDENTITY:-}" ]; then
        printf '%s\n' "$CODESIGN_IDENTITY"
        return
    fi

    # A development identity keeps a stable Team ID across rebuilds, so macOS
    # does not treat every local install as a different app for data access.
    local apple_development_identity
    apple_development_identity="$(
        security find-identity -v -p codesigning 2>/dev/null |
            awk '/"Apple Development:/ { print $2; exit }'
    )"

    if [ -n "$apple_development_identity" ]; then
        printf '%s\n' "$apple_development_identity"
    else
        printf '%s\n' "WidgetDev"
    fi
}

SIGN_IDENTITY="$(resolve_sign_identity)"

if [ -d "$APP_BUNDLE/Contents/PlugIns" ]; then
    while IFS= read -r appex; do
        codesign --force --sign "$SIGN_IDENTITY" --entitlements "$WIDGET_ENTITLEMENTS" "$appex"
    done < <(find "$APP_BUNDLE/Contents/PlugIns" -depth -name "*.appex" -print)
fi

echo "==> Signing app bundle with '$SIGN_IDENTITY'"
codesign --force --sign "$SIGN_IDENTITY" --entitlements "$APP_ENTITLEMENTS" "$APP_BUNDLE"

SIGNING_TEAM_ID="$(
    codesign -dvv "$APP_BUNDLE" 2>&1 |
        awk -F= '/^TeamIdentifier=/ { print $2; exit }'
)"
if [ -n "$SIGNING_TEAM_ID" ] && [ "$SIGNING_TEAM_ID" != "not set" ]; then
    echo "==> Signed with stable Team ID $SIGNING_TEAM_ID"
else
    echo "WARNING: '$SIGN_IDENTITY' has no Team ID; macOS may request App Data access again after rebuilding."
fi

touch "$APP_BUNDLE"

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "==> Stopping running $APP_NAME"
    pkill -x "$APP_NAME" || true
    sleep 1
fi

if pgrep -x "$OLD_APP_NAME" >/dev/null 2>&1; then
    echo "==> Stopping old $OLD_APP_NAME"
    pkill -x "$OLD_APP_NAME" || true
    sleep 1
fi

if [ -d "$OLD_INSTALL_PATH" ]; then
    echo "==> Removing old installed $OLD_APP_NAME"
    remove_installed_bundle "$OLD_INSTALL_PATH"
fi

if [ -d "$INSTALL_PATH" ]; then
    if command -v pluginkit >/dev/null 2>&1; then
        while IFS= read -r appex; do
            pluginkit -r "$appex" || true
        done < <(find "$INSTALL_PATH/Contents/PlugIns" -depth -name "*.appex" -print 2>/dev/null)
    fi

    echo "==> Replacing existing install"
    rm -rf "$INSTALL_PATH"
fi

echo "==> Installing app bundle to $INSTALL_PATH"
ditto "$APP_BUNDLE" "$INSTALL_PATH"

if [ -x "$LSREGISTER" ]; then
    echo "==> Removing temporary app bundles from LaunchServices"
    unregister_bundle "$APP_BUNDLE"
    unregister_bundle "$BUILT_APP"

    echo "==> Registering installed app with LaunchServices"
    "$LSREGISTER" -f -R -trusted "$INSTALL_PATH"
fi

if command -v pluginkit >/dev/null 2>&1; then
    echo "==> Registering widget extension with PlugInKit"
    while IFS= read -r appex; do
        pluginkit -a "$appex" || true
    done < <(find "$INSTALL_PATH/Contents/PlugIns" -depth -name "*.appex" -print)
fi

touch "$INSTALL_PATH"

echo "==> Refreshing WidgetKit services"
refresh_widgetkit_services

echo "==> Removing temporary build products"
rm -rf "$APP_BUNDLE"
rm -rf "$DERIVED_DATA_DIR"

echo "==> Launching $APP_NAME"
open "$INSTALL_PATH"

echo "==> Done"
echo "    Installed app: $INSTALL_PATH"
