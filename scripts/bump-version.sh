#!/bin/bash
# Usage: scripts/bump-version.sh 0.2.0   (sets CFBundleShortVersionString, increments CFBundleVersion)
set -euo pipefail
cd "$(dirname "$0")/.."
NEW="${1:?version required, e.g. 0.2.0}"
PLIST=Sources/MeetAI/Resources/Info.plist
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD + 1))" "$PLIST"
echo "version $NEW (build $((BUILD + 1)))"
