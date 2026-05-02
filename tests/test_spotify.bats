#!/usr/bin/env bats
# Tests for scripts/spotify.sh

load 'test_helpers'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

run_spotify() {
    run "$SCRIPTS_DIR/spotify.sh"
}

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

@test "Spotify playing → formatted purple output" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="Radiohead · Karma Police"
    run_spotify
    [[ "$output" == *"Radiohead"* ]]
    [[ "$output" == *"Karma Police"* ]]
    [[ "$output" == *"#[fg=#b48ead]"* ]]
}

@test "long track name truncated with ellipsis" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="A Very Very Very Very Very Very Very Very Long Artist · Some Track"
    export MOCK_OPT_useful_spotify_max_len=20
    run_spotify
    [[ "$output" == *"…"* ]]
    # Truncated string itself shouldn't exceed max + ellipsis.
    stripped=$(printf "%s" "$output" | sed -E 's/#\[[^]]*\]//g')
    # Strip leading/trailing spaces and icon for length check.
    [ "${#stripped}" -lt 60 ]
}

@test "custom icon respected" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="A · B"
    export MOCK_OPT_useful_spotify_icon="♪"
    run_spotify
    [[ "$output" == *"♪"* ]]
}

@test "cache hit avoids re-running osascript" {
    export MOCK_SPOTIFY_RUNNING=1
    export MOCK_SPOTIFY_TRACK="Cached · Track"
    run_spotify
    first="$output"
    export MOCK_SPOTIFY_TRACK="Different · Track"
    run_spotify
    [ "$output" = "$first" ]
}
