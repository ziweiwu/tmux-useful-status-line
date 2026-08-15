#!/usr/bin/env bats
# Contrast is a claim scripts/themes.sh makes in prose. This file is what makes
# it a claim the build can check.

load 'test_helpers'

setup() {
    setup_test_env
    # shellcheck source=../scripts/helpers.sh
    source "$SCRIPTS_DIR/helpers.sh"
}

teardown() {
    teardown_test_env
}

# WCAG 2.2 relative luminance and contrast ratio, straight from the spec.
# awk rather than bash: the formula needs floating point and a 2.4 exponent.
contrast_ratio() {
    awk -v fg="$1" -v bg="$2" '
        function hexval(s,   i, c, v, n) {
            n = 0
            for (i = 1; i <= length(s); i++) {
                c = tolower(substr(s, i, 1))
                v = index("0123456789abcdef", c) - 1
                n = n * 16 + v
            }
            return n
        }
        function chan(x) {
            x = x / 255
            return (x <= 0.03928) ? x / 12.92 : ((x + 0.055) / 1.055) ^ 2.4
        }
        function lum(h,   r, g, b) {
            sub(/^#/, "", h)
            r = hexval(substr(h, 1, 2))
            g = hexval(substr(h, 3, 2))
            b = hexval(substr(h, 5, 2))
            return 0.2126 * chan(r) + 0.7152 * chan(g) + 0.0722 * chan(b)
        }
        BEGIN {
            a = lum(fg); b = lum(bg)
            if (a < b) { t = a; a = b; b = t }
            printf "%.2f", (a + 0.05) / (b + 0.05)
        }'
}

# Read the five tones a theme resolves to, in a fresh shell so themes.sh
# re-runs against the mocked options.
tones_for() {
    bash -c '
        export MOCK_OPT_useful_theme="$2" MOCK_OPT_useful_contrast="$3"
        source "$1/helpers.sh"
        printf "%s %s %s %s %s" \
            "$(color_ok)" "$(color_warn)" "$(color_crit)" "$(color_accent)" "$(color_dim)"
    ' _ "$SCRIPTS_DIR" "$1" "${2:-}"
}

@test "contrast_ratio matches the WCAG worked examples" {
    # Black on white is the spec's maximum, 21:1. A mid grey on white is the
    # canonical 4.54:1 boundary case. If this drifts, every assertion below is
    # measuring the wrong thing.
    [ "$(contrast_ratio '#000000' '#ffffff')" = "21.00" ]
    [ "$(contrast_ratio '#ffffff' '#ffffff')" = "1.00" ]
    [ "$(contrast_ratio '#767676' '#ffffff')" = "4.54" ]
}

@test "every theme clears WCAG AA on every tone under @useful-contrast aa" {
    failures=""
    while IFS='=' read -r theme bg; do
        [ -n "$theme" ] || continue
        read -r ok warn crit accent dim <<<"$(tones_for "$theme" aa)"
        for pair in "ok:$ok" "warn:$warn" "crit:$crit" "accent:$accent" "dim:$dim"; do
            name="${pair%%:*}"; hex="${pair#*:}"
            ratio=$(contrast_ratio "$hex" "$bg")
            # bash has no float compare; scale to hundredths and use integers.
            scaled=$(printf "%s" "$ratio" | tr -d '.')
            [ "$scaled" -ge 450 ] || failures="$failures $theme/$name($hex on $bg = $ratio)"
        done
    done <<<"$USEFUL_THEME_BACKGROUNDS"
    [ -z "$failures" ] || { echo "below AA 4.5:1:$failures" >&2; return 1; }
}

@test "without the aa flag the palettes stay byte-identical to upstream" {
    # Fidelity to the named palette is deliberate, not an oversight — the
    # corrections are opt-in. Pin a few well-known tones so a future "helpful"
    # edit to themes.sh has to be a conscious one.
    read -r _ _ crit _ _ <<<"$(tones_for nord)"
    [ "$crit" = "#bf616a" ]                     # Nord aurora red
    read -r _ _ crit _ _ <<<"$(tones_for dracula)"
    [ "$crit" = "#ff5555" ]
    read -r ok _ _ _ _ <<<"$(tones_for solarized-light)"
    [ "$ok" = "#859900" ]
}

@test "an explicit @useful-color-* still outranks the aa corrections" {
    run bash -c '
        export MOCK_OPT_useful_theme=nord MOCK_OPT_useful_contrast=aa
        export MOCK_OPT_useful_color_crit="#123456"
        source "$1/helpers.sh"; color_crit
    ' _ "$SCRIPTS_DIR"
    [ "$output" = "#123456" ]
}

@test "every theme in the case statement has a background registered" {
    # Otherwise the AA test above silently skips it. Checked per case BRANCH,
    # not per name: a branch like `gruvbox|gruvbox-dark)` is one palette under
    # two spellings, and one registered background covers both.
    missing=""
    while IFS= read -r branch; do
        [ -n "$branch" ] || continue
        found=""
        for name in ${branch//|/ }; do
            case "$USEFUL_THEME_BACKGROUNDS" in
                *"$name="*) found=1 ;;
            esac
        done
        [ -n "$found" ] || missing="$missing $branch"
    done < <(sed -n '/^case "\$useful_theme_name" in/,/^esac/p' "$SCRIPTS_DIR/themes.sh" \
             | sed -nE 's/^    ([a-z0-9|"-]+)\)[[:space:]]*$/\1/p' | tr -d '"')
    [ -z "$missing" ] || { echo "case branches with no registered background:$missing" >&2; return 1; }
}
