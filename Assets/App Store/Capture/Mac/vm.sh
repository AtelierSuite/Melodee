# The Parallels VM for capture-mac.sh. Sourced, not run.
#
# The VM needs no developer tools: the app and vmtool are built on the host and copied
# in. It needs no Screen Recording access either, which screencapture doesn't get
# through prlctl exec: the whole screen is captured from the host with prlctl capture,
# and crop cuts the window out.

vm_name=${VM:-macOS}
# The VM's own copy of everything, under its user's home; expanded there.
remote='$HOME/MelodeeScreenshots'
app_process=MelodeeScreenshots/Melodee.app/Contents/MacOS/Melodee

step() {
    print -P "%B==> $1%b"
}

# Runs a command in the VM as the logged-in user and prints what it printed. The
# channel now and then fails a call before it runs ("Invalid argument"), or hangs,
# so the call is tried again; the command's own failure is passed on.
vm() {
    local out try
    for try in 1 2 3 4 5; do
        out=$(timeout 60 prlctl exec $vm_name --current-user "$1; echo __status=\$?" 2>&1) || true
        if [[ $out == *__status=* ]]; then
            print -rn -- "${out%%__status=*}"
            return ${${out##*__status=}%%[^0-9]*}
        fi
        sleep 2
    done
    print -u2 "$vm_name isn't answering"
    return 1
}

# Copies a file into the VM a megabyte at a time, as large piped copies can jam the
# channel for everyone else using the VM, then checks it arrived whole. Each piece goes
# to a file of its own, so a piece sent again only writes the same bytes over itself.
#   send <file> <path under $remote>
send() {
    local pieces=$(mktemp -d $work_dir/pieces.XXXXXX) piece try attempt
    local destination="$remote/$2" checksum=$(shasum -a 256 "$1" | cut -d' ' -f1)
    split -b 1m "$1" "$pieces/"
    vm "mkdir -p \"$destination.pieces\""
    for try in 1 2 3 4 5; do
        for piece in $pieces/*(N); do
            for attempt in 1 2 3; do
                timeout 60 prlctl exec $vm_name --current-user "cat > \"$destination.pieces/${piece:t}\"" \
                    < $piece > /dev/null 2>&1 && break
                sleep 2
            done
        done
        [[ $(vm "cd \"$destination.pieces\" && cat * > \"$destination\" && shasum -a 256 \"$destination\"" \
            | cut -d' ' -f1) == $checksum ]] && break
        (( try < 5 )) || { print -u2 "$1 arrived damaged"; return 1; }
    done
    vm "rm -r \"$destination.pieces\""
    rm -r $pieces
}

app_pid="" cleaned=0
# On the way out, however it goes: the app this started, and everything sent. zsh skips
# an EXIT trap when set -e stops the script in a function, so ZERR cleans up too.
clean_up() {
    (( cleaned )) && return
    cleaned=1
    set +e
    [[ -n $app_pid ]] && vm "kill $app_pid" > /dev/null 2>&1
    if [[ -n ${KEEP_VM_COPY:-} ]]; then
        print -u2 "left $remote in $vm_name"
    else
        vm "rm -rf $remote" > /dev/null 2>&1 || print -u2 "couldn't remove $remote from $vm_name"
    fi
    rm -rf $work_dir
}

# Copies in the app, vmtool, and the sample library in each language.
#   prepare_vm <app> <vmtool> <seed dir> <language>...
prepare_vm() {
    local app=$1 tool=$2 seed_dir=$3 language
    shift 3
    tar -C ${app:h} -czf $work_dir/app.tgz ${app:t}
    vm "rm -rf $remote && mkdir -p $remote/Library"
    send $work_dir/app.tgz app.tgz
    send $tool vmtool
    vm "cd $remote && tar xzf app.tgz && rm app.tgz && chmod +x vmtool"
    for language in "$@"; do
        tar -C $seed_dir/$language -czf $work_dir/library-$language.tgz .
        send $work_dir/library-$language.tgz library-$language.tgz
        vm "mkdir -p $remote/Library/$language && cd $remote/Library/$language \
            && tar xzf $remote/library-$language.tgz && rm $remote/library-$language.tgz"
    done
    read display_width display_height <<< "$(vm "$remote/vmtool display")"
    if (( display_width < 1320 || display_height < 860 )); then
        print -u2 "$vm_name's display is $display_width × $display_height points; the window needs 1320 × 860"
        return 1
    fi
}

# Launches the app on the stage these arguments describe (see ScreenshotStage.swift), waits
# for it to settle, and saves its window. Opened through LaunchServices, so the app belongs
# to the logged-in session rather than to prlctl exec's, which ends with the call.
#   capture_window <out.png> <language> <stage argument>...
capture_window() {
    local out=$1 language=$2 window="" covered="" second windows scale locale=en_US
    shift 2
    [[ $language == ja ]] && locale=ja_JP
    vm "$remote/vmtool park-pointer; open -n -a $remote/Melodee.app --args \
        -ScreenshotLibrary \"$remote/Library/$language\" ${(j: :)${(qq)@}} \
        -AppleLanguages '($language)' -AppleLocale $locale \
        -ExternalFolderBookmarks '<>' -ApplePersistenceIgnoreState YES -NSQuitAlwaysKeepsWindows NO"

    # Window titles aren't to be had without Screen Recording access, so the window is
    # known by the size the stage gives it.
    for second in {1..60}; do
        sleep 1
        [[ -n $app_pid ]] || app_pid=$(vm "pgrep -n -f $app_process" || true)
        [[ -n $app_pid ]] || continue
        windows=$(vm "$remote/vmtool windows $app_pid" || true)
        window=$(print -r -- $windows | awk '$4 == 1280 && $5 == 800' | head -1)
        [[ -n $window ]] && break
    done
    [[ -n $window ]] || { print -u2 "no window for ${out:t}"; return 1; }
    # Long enough for the album art, the panel, and the progress bar.
    sleep 5
    windows=$(vm "$remote/vmtool windows $app_pid")

    for second in {1..120}; do
        covered=$(vm "$remote/vmtool covered $app_pid" || true)
        [[ -z $covered ]] && break
        (( second == 1 )) && print -u2 "waiting for this to move off the window: $covered"
        sleep 5
    done
    [[ -z $covered ]] || { print -u2 "the window for ${out:t} stayed covered"; return 1; }

    prlctl capture $vm_name --file $work_dir/screen.png > /dev/null
    scale=$(( $(sips -g pixelWidth $work_dir/screen.png | awk '/pixelWidth/ { print $2 }') / display_width ))
    # The window, then the body of any popover, such as the queue, which can reach past it.
    local shapes=() line
    read -r _ x y width height <<< "$window"
    shapes=($x $y $width $height $window_corner_radius)
    for line in ${(f)windows}; do
        [[ $line == $window ]] && continue
        read -r _ x y width height <<< "$line"
        shapes+=($(( x + popover_inset )) $(( y + popover_inset )) $(( width - 2 * popover_inset )) \
            $(( height - 2 * popover_inset )) $popover_corner_radius)
    done
    mkdir -p ${out:h}
    $work_dir/crop $work_dir/screen.png $scale $window_margin $out $shapes

    vm "kill $app_pid; while kill -0 $app_pid 2>/dev/null; do sleep 0.2; done"
    app_pid=""
}
