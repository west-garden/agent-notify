#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/AgentNotify/Resources/IconSource/cow-head-master.png"
ASSET_ROOT="$ROOT/AgentNotify/Resources/Assets.xcassets"
APPICON_DIR="$ASSET_ROOT/AppIcon.appiconset"
MENUBAR_DIR="$ASSET_ROOT/MenuBarCow.imageset"

mkdir -p "$APPICON_DIR" "$MENUBAR_DIR"

cp "$SOURCE" "$APPICON_DIR/app-icon-1024.png"
sips -z 512 512 "$SOURCE" --out "$APPICON_DIR/app-icon-512.png" >/dev/null
sips -z 256 256 "$SOURCE" --out "$APPICON_DIR/app-icon-256.png" >/dev/null
sips -z 128 128 "$SOURCE" --out "$APPICON_DIR/app-icon-128.png" >/dev/null
sips -z 64 64 "$SOURCE" --out "$APPICON_DIR/app-icon-64.png" >/dev/null
sips -z 32 32 "$SOURCE" --out "$APPICON_DIR/app-icon-32.png" >/dev/null
sips -z 16 16 "$SOURCE" --out "$APPICON_DIR/app-icon-16.png" >/dev/null
sips -z 36 36 "$SOURCE" --out "$MENUBAR_DIR/menu-bar-cow@2x.png" >/dev/null
sips -z 18 18 "$SOURCE" --out "$MENUBAR_DIR/menu-bar-cow.png" >/dev/null
