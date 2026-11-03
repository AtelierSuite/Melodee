#!/bin/zsh
# Captures fresh Mac App Store screenshots in a Parallels macOS VM into Raw/Mac/<lang>/.
#
#   ./capture-mac.sh                      every language
#   ./capture-mac.sh --languages en       only English
#   ./capture-mac.sh --skip-build         reuse the last build of the app
#   VM=<name> ./capture-mac.sh            a VM other than "macOS"
#   KEEP_VM_COPY=1 ./capture-mac.sh       leaves the app and library in the VM, to look into a run
#
# The VM needs a logged-in user and a Retina display of at least 1320 × 860 points, to
# fit the 1280 × 800 window below its menu bar. The app is a Debug build, signed to run
# locally only and without the sandbox, so it can read the library copied in, which stages each screen from its launch arguments; the sample library
# in Seed/ goes in beside it, so the Mac's own Documents folder is never read. Run
# ./compose.sh Mac afterwards to lay the captures out. Needs ffmpeg and Pillow.
set -euo pipefail

assets_dir=${0:A:h}
repo_dir=${assets_dir:h:h}
work_dir=$(mktemp -d ${TMPDIR:-/tmp}/melodee-capture-mac.XXXXXX)
source "$assets_dir/Capture/Mac/vm.sh"
source "$assets_dir/Capture/Mac/scenes.sh"
trap clean_up EXIT
trap 'clean_up; exit 1' ZERR

# A window's corners on macOS 27, in points, and a popover's, which sits this far in from
# its own window's frame, all measured against a capture of them.
window_corner_radius=16
popover_inset=13
popover_corner_radius=18
# The transparent margin each capture keeps around the window, for popovers that reach
# past it. Compose/Device.swift places the window knowing it.
window_margin=160

languages=(en ja)
skip_build=false
while (( $# > 0 )); do
    case $1 in
        --languages) languages=(${(s:,:)2}); shift 2 ;;
        --skip-build) skip_build=true; shift ;;
        *) print -u2 "unknown option: $1"; exit 64 ;;
    esac
done

build_dir=${TMPDIR:-/tmp}/melodee-capture-mac-build
app_path=$build_dir/Build/Products/Debug/Melodee.app
if ! $skip_build || [[ ! -d $app_path ]]; then
    step "Building Melodee for Mac"
    xcodebuild -project "$repo_dir/Melodee.xcodeproj" -scheme "Melodee for Mac" -configuration Debug \
        -destination 'platform=macOS' -derivedDataPath "$build_dir" \
        CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS= ENABLE_APP_SANDBOX=NO \
        build > "$build_dir.log" 2>&1 || { print -u2 "build failed, see $build_dir.log"; exit 1; }
fi
swiftc -O "$assets_dir/Capture/Mac/vmtool.swift" -o $work_dir/vmtool
swiftc -O "$assets_dir/Capture/Mac/crop.swift" -o $work_dir/crop

step "Seeding the sample library"
for language in $languages; do
    mkdir -p $work_dir/seed/$language
    python3 "$assets_dir/Seed/seed.py" --language $language --documents $work_dir/seed/$language
    # The same file times as on the iPhone.
    find $work_dir/seed/$language -exec touch -t 202610230915 {} +
done

step "Copying into $vm_name"
prepare_vm $app_path $work_dir/vmtool $work_dir/seed $languages

for language in $languages; do
    step "Mac ($language)"
    capture_scenes $language "$assets_dir/Raw/Mac/$language"
done

step "Done. Run ./compose.sh Mac to lay out the screenshots."
