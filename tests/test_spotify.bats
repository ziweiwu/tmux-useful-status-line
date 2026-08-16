#!/usr/bin/env bats
# Tests for scripts/spotify.sh — including the track-change-triggered slide.

load 'test_helpers'

setup() {
    setup_test_env
    export TMUX_USEFUL_NO_WATCHDOG=1
}

teardown() {
    teardown_test_env
}

run_spotify() {
    run "$SCRIPTS_DIR/spotify.sh"
}

# ------------------------------------------------------------ basic play states

@test "Spotify not running → empty output (osascript not invoked)" {
    export MOCK_SPOTIFY_RUNNING=0
    export MOCK_SPOTIFY_TRACK="Should Not Appear"
    run_spotify
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "Spotify running but no track → empty output" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK=""
    run_spotify
    [ "$output" = "" ]
}

@test "short track shows full name without ellipsis" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="Short · Song"
    export MOCK_OPT_useful_spotify_max_len=30
    run_spotify
    [[ "$output" == *"Short · Song"* ]]
    [[ "$output" != *"…"* ]]
}

@test "playing track is rendered in accent color" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="Radiohead · Karma Police"
    run_spotify
    [[ "$output" == *"#[fg=#b48ead]"* ]]
}

@test "custom icon respected" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="A · B"
    export MOCK_OPT_useful_spotify_icon="♪"
    run_spotify
    [[ "$output" == *"♪"* ]]
}

# --------------------------------------------- track lookup is cached for 5s

@test "track cache hit avoids re-running osascript" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="Cached · Track"
    run_spotify
    first="$output"
    export MOCK_SPOTIFY_TRACK="Different · Track"
    run_spotify
    [ "$output" = "$first" ]
}

# -------------------------------------------------- sliding-window phases
# Track is 50 chars, MAX_LEN=15 → overflow=35.
# DWELL=2, SLIDE_DURATION=8 → end-dwell starts at t=10, settles at t=12.

LONG_TRACK="Lorem ipsum dolor sit amet consectetur adipiscing"

@test "long track at t=0 (dwell-start) shows truncated start with trailing ellipsis" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="$LONG_TRACK"
    export MOCK_OPT_useful_spotify_max_len=15
    export TMUX_USEFUL_NOW=1000
    printf "1000|%s" "$LONG_TRACK" >"$TMUX_USEFUL_CACHE_DIR/spotify-state"
    run_spotify
    [[ "$output" == *"Lorem ipsum do…"* ]]
    [[ "$output" != *"…Lorem"* ]]
}

@test "long track at t=DWELL+SLIDE+DWELL (end-dwell) shows trailing tail with leading ellipsis" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="$LONG_TRACK"
    export MOCK_OPT_useful_spotify_max_len=15
    export TMUX_USEFUL_NOW=1011
    printf "1000|%s" "$LONG_TRACK" >"$TMUX_USEFUL_CACHE_DIR/spotify-state"
    run_spotify
    [[ "$output" == *"adipiscing"* ]]
    [[ "$output" == *"…"* ]]
}

@test "long track mid-slide shows interior window with both ellipses" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="$LONG_TRACK"
    export MOCK_OPT_useful_spotify_max_len=15
    # t=6: 4s into slide (out of 8s) → offset ≈ overflow/2 ≈ 17
    export TMUX_USEFUL_NOW=1006
    printf "1000|%s" "$LONG_TRACK" >"$TMUX_USEFUL_CACHE_DIR/spotify-state"
    run_spotify
    [[ "$output" == *"…"*"…"* ]]
    [[ "$output" != *"Lorem ipsum"* ]]
    [[ "$output" != *"adipiscing"* ]]
}

@test "long track after slide settles back to truncated start" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="$LONG_TRACK"
    export MOCK_OPT_useful_spotify_max_len=15
    export TMUX_USEFUL_NOW=1100
    printf "1000|%s" "$LONG_TRACK" >"$TMUX_USEFUL_CACHE_DIR/spotify-state"
    run_spotify
    [[ "$output" == *"Lorem ipsum do…"* ]]
}

# ----------------------------------------------------- track-change behavior

@test "new track resets cycle clock" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="$LONG_TRACK"
    export MOCK_OPT_useful_spotify_max_len=15
    export TMUX_USEFUL_NOW=2000
    # Pre-existing state for a different (long-since-settled) track.
    printf "100|OLD · TRACK" >"$TMUX_USEFUL_CACHE_DIR/spotify-state"
    run_spotify
    # New track: t=0 of cycle → dwell-start truncated view.
    [[ "$output" == *"Lorem ipsum do…"* ]]
    # State file should now contain the new track + cycle_start=NOW.
    grep -q "^2000|${LONG_TRACK}$" "$TMUX_USEFUL_CACHE_DIR/spotify-state"
}

@test "scroll disabled keeps truncated start regardless of elapsed time" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="$LONG_TRACK"
    export MOCK_OPT_useful_spotify_max_len=15
    export MOCK_OPT_useful_spotify_scroll=off
    export TMUX_USEFUL_NOW=1006
    printf "1000|%s" "$LONG_TRACK" >"$TMUX_USEFUL_CACHE_DIR/spotify-state"
    run_spotify
    [[ "$output" == *"Lorem ipsum do…"* ]]
}

@test "pause then resume same track does not retrigger slide" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="$LONG_TRACK"
    export MOCK_OPT_useful_spotify_max_len=15
    # Initial play at t=1000.
    export TMUX_USEFUL_NOW=1000
    run_spotify
    state_after_play=$(cat "$TMUX_USEFUL_CACHE_DIR/spotify-state")

    # Pause: osascript returns empty. Track cache must be invalidated so
    # spotify.sh actually re-asks osascript and sees the empty state.
    rm -f "$TMUX_USEFUL_CACHE_DIR/spotify-track"
    export MOCK_SPOTIFY_TRACK=""
    export TMUX_USEFUL_NOW=1100
    run_spotify
    [ "$output" = "" ]
    # Critical: state file is preserved across pause.
    [ -f "$TMUX_USEFUL_CACHE_DIR/spotify-state" ]
    [ "$(cat "$TMUX_USEFUL_CACHE_DIR/spotify-state")" = "$state_after_play" ]

    # Resume same track much later. Should NOT reset cycle.
    rm -f "$TMUX_USEFUL_CACHE_DIR/spotify-track"
    export MOCK_SPOTIFY_TRACK="$LONG_TRACK"
    export TMUX_USEFUL_NOW=1200
    run_spotify
    # State's cycle_start should still be 1000 (not 1200).
    grep -q "^1000|${LONG_TRACK}$" "$TMUX_USEFUL_CACHE_DIR/spotify-state"
    # Display should be settled, not in slide phase.
    [[ "$output" == *"Lorem ipsum do…"* ]]
}

@test "REDUCED_MOTION env var disables scroll" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="$LONG_TRACK"
    export MOCK_OPT_useful_spotify_max_len=15
    export TMUX_USEFUL_NOW=1006
    export REDUCED_MOTION=1
    printf "1000|%s" "$LONG_TRACK" >"$TMUX_USEFUL_CACHE_DIR/spotify-state"
    run_spotify
    # Should be settled-truncated regardless of elapsed time in slide window.
    [[ "$output" == *"Lorem ipsum do…"* ]]
}

@test "TMUX_USEFUL_REDUCED_MOTION disables scroll" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="$LONG_TRACK"
    export MOCK_OPT_useful_spotify_max_len=15
    export TMUX_USEFUL_NOW=1006
    export TMUX_USEFUL_REDUCED_MOTION=1
    printf "1000|%s" "$LONG_TRACK" >"$TMUX_USEFUL_CACHE_DIR/spotify-state"
    run_spotify
    [[ "$output" == *"Lorem ipsum do…"* ]]
}

@test "malicious separator does not inject AppleScript" {
    export MOCK_SPOTIFY_RUNNING=1
    # The osascript stub drains stdin and emits MOCK_SPOTIFY_TRACK; if injection
    # were possible, the separator would change script behavior. We assert that
    # the track output uses the literal separator value as data, not as code.
    export MOCK_SPOTIFY_TRACK='Artist · Track'
    export MOCK_OPT_useful_spotify_separator='" & (do shell script "touch /tmp/pwned-by-test") & "'
    rm -f /tmp/pwned-by-test
    run_spotify
    [ ! -f /tmp/pwned-by-test ]
    [[ "$output" == *"Artist · Track"* ]]
}

@test "segment disabled → empty even when playing" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="Test · Track"
    export MOCK_OPT_useful_spotify_enabled=off
    run_spotify
    [ "$output" = "" ]
}

@test "no slide spawned for tracks that fit (length ≤ max)" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="A · B"
    export MOCK_OPT_useful_spotify_max_len=30
    run_spotify
    # Output should be the full track, no ellipsis anywhere.
    [[ "$output" != *"…"* ]]
}

# ------------------------------------------------- state file round-trip

PIPE_TRACK="Portishead · Glory Box | Live at Roseland Ballroom"

@test "a track title containing a pipe still advances the slide" {
    # `read -r a b` gives the LAST variable the whole remainder, delimiters
    # included. With the track written first, "Glory Box | Live" split across
    # both fields, prev_track never matched, and the change branch fired on
    # EVERY refresh -- pinning the slide to frame 0 for the life of the track.
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="$PIPE_TRACK"
    export MOCK_OPT_useful_spotify_max_len=15
    export TMUX_USEFUL_NOW=1000
    run_spotify
    head_frame="$output"

    export TMUX_USEFUL_NOW=1006
    rm -f "$TMUX_USEFUL_CACHE_DIR/spotify-track"
    run_spotify
    [ "$output" != "$head_frame" ]
    [[ "$output" == *"…"* ]]
}

@test "a pipe in the title does not reset the cycle clock every tick" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="$PIPE_TRACK"
    export MOCK_OPT_useful_spotify_max_len=15
    export TMUX_USEFUL_NOW=1000
    run_spotify
    first=$(cat "$TMUX_USEFUL_CACHE_DIR/spotify-state")

    export TMUX_USEFUL_NOW=1007
    rm -f "$TMUX_USEFUL_CACHE_DIR/spotify-track"
    run_spotify
    [ "$(cat "$TMUX_USEFUL_CACHE_DIR/spotify-state")" = "$first" ]
    [[ "$first" == "1000|"* ]]
}

@test "a corrupt state file falls back to the current cycle" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="$LONG_TRACK"
    export MOCK_OPT_useful_spotify_max_len=15
    export TMUX_USEFUL_NOW=1000
    printf "not-a-timestamp|whatever" >"$TMUX_USEFUL_CACHE_DIR/spotify-state"
    run_spotify
    [ "$status" -eq 0 ]
    [[ "$(cat "$TMUX_USEFUL_CACHE_DIR/spotify-state")" == "1000|"* ]]
}

# ------------------------------------------------------- watchdog PID guard

@test "a stale watchdog PID is not signalled" {
    # The old guard was `case $comm in *bash*|*sh*|*sleep*)`, which matches
    # zsh, fish, dash, ssh and sshd. Nothing ever removed the PID file, so once
    # the OS recycled that PID we would SIGTERM an unrelated process.
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="$LONG_TRACK"
    export MOCK_OPT_useful_spotify_max_len=15
    unset TMUX_USEFUL_NO_WATCHDOG

    # A live bystander whose name the old guard would have matched.
    sleep 30 &
    victim=$!
    echo "$victim" >"$TMUX_USEFUL_CACHE_DIR/spotify-watchdog.pid"
    touch_ago "$TMUX_USEFUL_CACHE_DIR/spotify-watchdog.pid" 600

    run_spotify
    kill -0 "$victim" 2>/dev/null || { echo "bystander was killed" >&2; kill "$victim" 2>/dev/null; return 1; }
    kill "$victim" 2>/dev/null
    wait "$victim" 2>/dev/null || true
}

@test "a fresh watchdog PID is still reaped on a track change" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="$LONG_TRACK"
    export MOCK_OPT_useful_spotify_max_len=15
    unset TMUX_USEFUL_NO_WATCHDOG

    sleep 30 &
    old=$!
    echo "$old" >"$TMUX_USEFUL_CACHE_DIR/spotify-watchdog.pid"

    run_spotify
    sleep 1
    if kill -0 "$old" 2>/dev/null; then
        kill "$old" 2>/dev/null
        echo "stale watchdog was not reaped" >&2
        return 1
    fi
}
