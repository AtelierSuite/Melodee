# The screens captured for the Mac. Sourced, not run.
#
# Each scene launches the app on the sample library and stages it through the arguments
# that MelodeeMac/App/ScreenshotStage.swift describes.

sample() {
    python3 "$assets_dir/Capture/samples.py" "$language" "$@"
}

# scene <raw name> <stage argument>...
scene() {
    local name=$1
    shift
    capture_window "$out_dir/$name.png" "$language" "$@"
    print "captured ${out_dir:t2}/$name.png"
}

capture_scenes() {
    local language=$1 out_dir=$2
    local trinity=$(sample school 0) wildhunt=$(sample school 1)

    scene 01-library -ScreenshotViewMode grid \
        -ScreenshotFolder "$wildhunt/$(sample album philharmonic)" \
        -ScreenshotPlay "$(sample track philharmonic 3).mp3" -ScreenshotSelect "$(sample track philharmonic 3).mp3"
    scene 02-now-playing -ScreenshotViewMode list \
        -ScreenshotFolder "$trinity/$(sample album tea-party)" \
        -ScreenshotPlay "$(sample track tea-party 2).mp3" -ScreenshotPanel queue
    scene 03-tag-editor -ScreenshotViewMode list \
        -ScreenshotFolder "$trinity/$(sample album sweets-club)" \
        -ScreenshotPlay "$(sample track sweets-club 1).mp3" -ScreenshotSelect "$(sample track sweets-club 2).mp3" \
        -ScreenshotPanel tags
}
