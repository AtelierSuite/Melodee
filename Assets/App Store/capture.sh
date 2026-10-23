#!/bin/zsh
# Captures fresh App Store screenshots from dedicated simulators into Raw/<device>/<lang>/.
#
#   ./capture.sh                      every device and language
#   ./capture.sh --devices iPhone     only the iPhone
#   ./capture.sh --languages en       only English
#   ./capture.sh --skip-build         reuse the last build of the app
#
# Each simulator is created on first run and its Documents filled with the sample library
# in Seed/, so every run shows the same music. Run ./compose.sh afterwards to lay the
# captures out. Needs ffmpeg and Pillow.
set -euo pipefail

assets_dir=${0:A:h}
repo_dir=${assets_dir:h:h}
driver_dir=${TMPDIR:-/tmp}/melodee-capture-driver
source "$assets_dir/Capture/simulator.sh"
source "$assets_dir/Capture/scenes.sh"

devices=(iPhone iPad)
languages=(en ja)
skip_build=false
while (( $# > 0 )); do
    case $1 in
        --devices) devices=(${(s:,:)2}); shift 2 ;;
        --languages) languages=(${(s:,:)2}); shift 2 ;;
        --skip-build) skip_build=true; shift ;;
        *) print -u2 "unknown option: $1"; exit 64 ;;
    esac
done

build_dir=${TMPDIR:-/tmp}/melodee-capture-build
app_path=$build_dir/Build/Products/Release-iphonesimulator/Melodee.app
if ! $skip_build || [[ ! -d $app_path ]]; then
    step "Building Melodee"
    xcodebuild -project "$repo_dir/Melodee.xcodeproj" -scheme Melodee -configuration Release \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath "$build_dir" \
        build > "$build_dir.log" 2>&1 || { print -u2 "build failed, see $build_dir.log"; exit 1; }
fi
step "Building the capture driver"
build_driver

for device in $devices; do
    udid=$(capture_simulator "$device")
    for language in $languages; do
        step "$device ($language)"
        boot_in_language "$udid" "$language"
        install_app "$udid" "$app_path"
        seed_library "$udid" "$language"
        capture_scenes "$udid" "$device" "$language" "$assets_dir/Raw/$device/$language"
    done
    xcrun simctl shutdown "$udid" 2>/dev/null || true
done

step "Done. Run ./compose.sh to lay out the screenshots."
