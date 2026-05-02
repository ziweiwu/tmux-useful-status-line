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
    printf "%s|1000" "$LONG_TRACK" >"$TMUX_USEFUL_CACHE_DIR/tmux-useful-spotify-state"
    run_spotify
    [[ "$output" == *"Lorem ipsum do…"* ]]
    [[ "$output" != *"…Lorem"* ]]
}

@test "long track at t=DWELL+SLIDE+DWELL (end-dwell) shows trailing tail with leading ellipsis" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="$LONG_TRACK"
    export MOCK_OPT_useful_spotify_max_len=15
    export TMUX_USEFUL_NOW=1011
    printf "%s|1000" "$LONG_TRACK" >"$TMUX_USEFUL_CACHE_DIR/tmux-useful-spotify-state"
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
    printf "%s|1000" "$LONG_TRACK" >"$TMUX_USEFUL_CACHE_DIR/tmux-useful-spotify-state"
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
    printf "%s|1000" "$LONG_TRACK" >"$TMUX_USEFUL_CACHE_DIR/tmux-useful-spotify-state"
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
    printf "OLD · TRACK|100" >"$TMUX_USEFUL_CACHE_DIR/tmux-useful-spotify-state"
    run_spotify
    # New track: t=0 of cycle → dwell-start truncated view.
    [[ "$output" == *"Lorem ipsum do…"* ]]
    # State file should now contain the new track + cycle_start=NOW.
    grep -q "^${LONG_TRACK}|2000$" "$TMUX_USEFUL_CACHE_DIR/tmux-useful-spotify-state"
}

@test "scroll disabled keeps truncated start regardless of elapsed time" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="$LONG_TRACK"
    export MOCK_OPT_useful_spotify_max_len=15
    export MOCK_OPT_useful_spotify_scroll=off
    export TMUX_USEFUL_NOW=1006
    printf "%s|1000" "$LONG_TRACK" >"$TMUX_USEFUL_CACHE_DIR/tmux-useful-spotify-state"
    run_spotify
    [[ "$output" == *"Lorem ipsum do…"* ]]
}

@test "no slide spawned for tracks that fit (length ≤ max)" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="A · B"
    export MOCK_OPT_useful_spotify_max_len=30
    run_spotify
    # Output should be the full track, no ellipsis anywhere.
    [[ "$output" != *"…"* ]]
}
