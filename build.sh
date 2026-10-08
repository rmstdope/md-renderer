#!/bin/zsh
# Builds MD Viewer.app and (with --install) installs it into ~/Applications
# and registers its Finder right-click service.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/MD Viewer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 Sources/main.swift -o "$APP/Contents/MacOS/MDViewer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/marked.min.js "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Applications/MD Viewer.app"
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
  /System/Library/CoreServices/pbs -update
  echo "Installed to $DEST"
  echo "Right-click a .md file in Finder > Quick Actions (or Services) > Render Markdown"
fi
