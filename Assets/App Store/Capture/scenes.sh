# The screens captured for each device. Sourced, not run.
#
# Every scene relaunches the app at the root of On My iPhone and walks to its screen
# through the Driver, as steps that Driver/DriverTests/DriverTests.swift describes.

sample() {
    python3 "$assets_dir/Capture/samples.py" "$language" "$@"
}

text() {
    python3 "$assets_dir/Capture/strings.py" "$language" "$device" "$1"
}

# scene <raw name> <light|dark> <step>...
scene() {
    local name=$1 steps
    xcrun simctl ui "$udid" appearance "$2"
    shift 2
    steps=${(j:|:)@}
    run_steps "$udid" "$out_dir" "$steps|shot:$name"
    print "captured ${out_dir:t2}/$name.png"
}

capture_scenes() {
    local udid=$1 device=$2 language=$3 out_dir=$4
    local trinity=$(sample school 0) wildhunt=$(sample school 1)
    local play="=$(text Shared.PlayAll)"

    scene 01-library light launch \
        "tap:$wildhunt" "tap:$(sample album philharmonic)" "tap:$(sample track philharmonic 3)" \
        wait:2 back back wait:2
    scene 02-album light launch \
        "tap:$trinity" "tap:$(sample album tea-party)" "tap:$(sample track tea-party 2)" wait:3
    scene 03-now-playing dark launch \
        "tap:$wildhunt" "tap:$(sample album philharmonic)" "tap:$play" wait:2 bar wait:4
    scene 04-tag-editor light launch \
        "tap:$trinity" "tap:$(sample album sweets-club)" "press:$(sample track sweets-club 2)" \
        "tap:$(text Shared.EditTag.Single)" wait:3
    scene 05-playlist dark launch \
        "tap:$(sample playlist 1)" "tap:$play" wait:3
    scene 06-context-menu light launch \
        "tap:$wildhunt" "tap:$(sample album occult)" "tap:$(sample track occult 4)" wait:2 \
        "press:$(sample track occult 1)" wait:2
}
