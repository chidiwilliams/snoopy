#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
output_dir="$repo_dir/outputs"
app_dir="$output_dir/Snoopy.app"
default_identity="Developer ID Application: Chidi Williams (G2V69FA555)"
signing_identity="${SNOOPY_SIGNING_IDENTITY:-$default_identity}"
stage_root="$(mktemp -d)"
stage_app="$stage_root/Snoopy.app"
trap 'rm -rf "$stage_root"' EXIT

cd "$repo_dir"
swift build -c release

mkdir -p "$stage_app/Contents/MacOS" "$stage_app/Contents/Resources"
cp ".build/release/NotificationClaude" "$stage_app/Contents/MacOS/NotificationClaude"
cp "Resources/Info.plist" "$stage_app/Contents/Info.plist"
xattr -cr "$stage_app"

if security find-identity -v -p codesigning | grep -Fq "$signing_identity"; then
  codesign --force --options runtime --timestamp=none --sign "$signing_identity" "$stage_app"
else
  echo "warning: '$signing_identity' is unavailable; using an ad-hoc signature (privacy permissions may reset after rebuilds)" >&2
  codesign --force --sign - "$stage_app"
fi

rm -rf "$app_dir"
ditto --noextattr --noqtn "$stage_app" "$app_dir"
codesign --verify --deep --strict "$app_dir"

echo "$app_dir"
