# Simulator lifecycle for capture.sh. Sourced, not run.

bundle_id=com.tsubuzaki.Melodee

step() {
    print -P "%B==> $1%b"
}

# The simulator for a device, created on first use. Prints its UDID.
capture_simulator() {
    local device=$1 name device_type udid runtime
    case $device in
        iPhone)
            name="Melodee Capture iPhone"
            device_type=com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro ;;
        iPad)
            name="Melodee Capture iPad"
            device_type=com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5-12GB ;;
        *) print -u2 "no simulator for $device"; return 1 ;;
    esac
    udid=$(xcrun simctl list devices -j | python3 -c "
import json, sys
for runtime in json.load(sys.stdin)['devices'].values():
    for device in runtime:
        if device['name'] == sys.argv[1] and device['isAvailable']:
            print(device['udid']); break
" "$name" | head -1)
    if [[ -z $udid ]]; then
        # The newest iOS runtime that can run this device; a fresh runtime can lag behind the device list.
        runtime=$(xcrun simctl list runtimes -j | python3 -c "
import json, sys
runtimes = [runtime for runtime in json.load(sys.stdin)['runtimes']
            if runtime['platform'] == 'iOS' and runtime['isAvailable']
            and any(kind['identifier'] == sys.argv[1] for kind in runtime.get('supportedDeviceTypes', []))]
print(runtimes[-1]['identifier'] if runtimes else '')
" "$device_type")
        [[ -n $runtime ]] || { print -u2 "no runtime supports $device_type"; return 1; }
        udid=$(xcrun simctl create "$name" "$device_type" "$runtime")
    fi
    print $udid
}

# Language and region are system-wide, so the simulator is restarted in them. The
# preferences are edited while it is shut down, as a write through simctl spawn
# does not survive the restart.
boot_in_language() {
    local udid=$1 language=$2 locale global_preferences
    case $language in
        ja) locale=ja_JP ;;
        *) locale=en_US ;;
    esac
    global_preferences=~/Library/Developer/CoreSimulator/Devices/$udid/data/Library/Preferences/.GlobalPreferences.plist
    # The first boot is what creates the preferences.
    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b > /dev/null
    xcrun simctl shutdown "$udid"
    plutil -replace AppleLanguages -json "[\"$language\"]" "$global_preferences"
    plutil -replace AppleLocale -string "$locale" "$global_preferences"
    xcrun simctl boot "$udid"
    xcrun simctl bootstatus "$udid" -b > /dev/null
    xcrun simctl status_bar "$udid" override --time "9:41" \
        --dataNetwork wifi --wifiMode active --wifiBars 3 \
        --cellularMode active --cellularBars 4 \
        --batteryState discharging --batteryLevel 100
}

# A fresh install each time, so nothing is left playing or queued from the last run.
install_app() {
    local udid=$1 app_path=$2
    xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true
    xcrun simctl uninstall "$udid" "$bundle_id" 2>/dev/null || true
    xcrun simctl install "$udid" "$app_path"
}

# Replaces the app's Documents with the sample library from Seed/, in one language.
seed_library() {
    local udid=$1 language=$2 documents
    documents="$(xcrun simctl get_app_container "$udid" "$bundle_id" data)/Documents"
    rm -rf "$documents"
    mkdir -p "$documents"
    python3 "$assets_dir/Seed/seed.py" --language "$language" --documents "$documents"
    # Match the file times to the 9:41 status bar.
    find "$documents" -exec touch -t 202610230915 {} +
}

build_driver() {
    local log=${TMPDIR:-/tmp}/melodee-capture-driver-build.log
    xcodebuild build-for-testing -project "$assets_dir/Capture/Driver/CaptureDriver.xcodeproj" \
        -scheme DriverTests -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$driver_dir" > "$log" 2>&1 \
        || { print -u2 "driver build failed, see $log"; return 1; }
}

# Runs the steps of one scene through the Driver's UI test. A UI test on a freshly
# booted simulator now and then misses a tap, so a failed run is given one more go.
run_steps() {
    run_steps_once "$@" || run_steps_once "$@"
}

run_steps_once() {
    local udid=$1 out_dir=$2 steps=$3 log=${TMPDIR:-/tmp}/melodee-capture-driver.log
    TEST_RUNNER_CAPTURE_BUNDLE_ID=$bundle_id TEST_RUNNER_CAPTURE_OUT_DIR=$out_dir \
    TEST_RUNNER_CAPTURE_STEPS=$steps \
        xcodebuild test-without-building -xctestrun "$(print -l "$driver_dir"/Build/Products/*.xctestrun | head -1)" \
        -destination "id=$udid" -only-testing:DriverTests/DriverTests/testScene > "$log" 2>&1 \
        || { grep -E "error: -\[" "$log" | head -3 >&2; print -u2 "see $log"; return 1; }
}
