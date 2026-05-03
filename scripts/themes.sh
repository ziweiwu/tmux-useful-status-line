#!/usr/bin/env bash
# shellcheck disable=SC2034
# default_color_* are read by color_* getters in helpers.sh after this file
# is sourced. Shellcheck can't follow that across the source boundary.
#
# Theme presets — pure data. Sourced by helpers.sh after defaults are set.
#
# Each theme exports the five `default_color_*` tones. All dim values keep
# WCAG AA contrast against the canonical background for that variant
# (light themes use darker dim, dark themes use lighter dim).
#
# Adding a theme: pick a name, add a case branch, set the five tones.
# That's it — color_ok() / color_warn() / etc. read these as fallbacks.

case "$(useful_resolve_theme)" in
    nord|"")
        ;;  # Nord — defaults already match.
    catppuccin|catppuccin-mocha)
        default_color_ok="#a6e3a1"
        default_color_warn="#f9e2af"
        default_color_crit="#f38ba8"
        default_color_accent="#cba6f7"
        default_color_dim="#9399b2"
        ;;
    catppuccin-macchiato)
        default_color_ok="#a6da95"
        default_color_warn="#eed49f"
        default_color_crit="#ed8796"
        default_color_accent="#c6a0f6"
        default_color_dim="#939ab7"
        ;;
    catppuccin-frappe)
        default_color_ok="#a6d189"
        default_color_warn="#e5c890"
        default_color_crit="#e78284"
        default_color_accent="#ca9ee6"
        default_color_dim="#949cbb"
        ;;
    catppuccin-latte)
        default_color_ok="#40a02b"
        default_color_warn="#df8e1d"
        default_color_crit="#d20f39"
        default_color_accent="#8839ef"
        default_color_dim="#6c6f85"
        ;;
    gruvbox|gruvbox-dark)
        default_color_ok="#b8bb26"
        default_color_warn="#fabd2f"
        default_color_crit="#fb4934"
        default_color_accent="#d3869b"
        default_color_dim="#a89984"
        ;;
    gruvbox-light)
        default_color_ok="#79740e"
        default_color_warn="#b57614"
        default_color_crit="#9d0006"
        default_color_accent="#8f3f71"
        default_color_dim="#7c6f64"
        ;;
    everforest|everforest-dark)
        default_color_ok="#a7c080"
        default_color_warn="#dbbc7f"
        default_color_crit="#e67e80"
        default_color_accent="#d699b6"
        default_color_dim="#9da9a0"
        ;;
    vitesse|vitesse-dark)
        default_color_ok="#4d9375"
        default_color_warn="#d4976c"
        default_color_crit="#cb7676"
        default_color_accent="#a8b1ff"
        default_color_dim="#8a8d96"
        ;;
    rose-pine|rosepine)
        default_color_ok="#9ccfd8"
        default_color_warn="#f6c177"
        default_color_crit="#eb6f92"
        default_color_accent="#c4a7e7"
        default_color_dim="#908caa"
        ;;
    rose-pine-dawn)
        default_color_ok="#286983"
        default_color_warn="#ea9d34"
        default_color_crit="#b4637a"
        default_color_accent="#907aa9"
        default_color_dim="#797593"
        ;;
    tokyo-night|tokyonight)
        default_color_ok="#9ece6a"
        default_color_warn="#e0af68"
        default_color_crit="#f7768e"
        default_color_accent="#bb9af7"
        default_color_dim="#737aa2"
        ;;
    dracula)
        default_color_ok="#50fa7b"
        default_color_warn="#f1fa8c"
        default_color_crit="#ff5555"
        default_color_accent="#bd93f9"
        default_color_dim="#7280a4"
        ;;
    solarized-dark)
        default_color_ok="#859900"
        default_color_warn="#b58900"
        default_color_crit="#dc322f"
        default_color_accent="#d33682"
        default_color_dim="#839496"
        ;;
    solarized-light)
        default_color_ok="#859900"
        default_color_warn="#b58900"
        default_color_crit="#dc322f"
        default_color_accent="#d33682"
        default_color_dim="#586e75"
        ;;
    onedark|one-dark)
        default_color_ok="#98c379"
        default_color_warn="#e5c07b"
        default_color_crit="#e06c75"
        default_color_accent="#c678dd"
        default_color_dim="#7a8290"
        ;;
esac
