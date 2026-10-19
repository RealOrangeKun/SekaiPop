#!/usr/bin/env bash
# check-deps.sh: read-only dependency check for the SekaiPop Quickshell rice.
# Run it BEFORE installing the rice. It installs nothing and changes nothing.
#
#   ./check-deps.sh            full report
#   ./check-deps.sh --core     only Tier 1 (what the shell cannot live without)
#   ./check-deps.sh --no-color
#
# Tiers:  1 = core (the shell breaks without it)
#         2 = feature (a specific feature is dead without it)
#         3 = optional
# Exit code: 0 = all Tier 1 present, 1 = something in Tier 1 is missing.
#
# Package names are for Fedora. Hyprland, quickshell, matugen and the hypr* tools come from the
# lionheartp/Hyprland COPR (sudo dnf copr enable lionheartp/Hyprland).

set -u

ONLY_CORE=0
COLOR=1
for a in "$@"; do
    case "$a" in
        --core) ONLY_CORE=1 ;;
        --no-color) COLOR=0 ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "unknown option: $a" >&2; exit 2 ;;
    esac
done
[ -t 1 ] || COLOR=0

if [ "$COLOR" = 1 ]; then
    R=$'\e[38;5;203m'; G=$'\e[38;5;114m'; Y=$'\e[38;5;221m'; D=$'\e[2m'; B=$'\e[1m'; C=$'\e[38;5;80m'; PK=$'\e[38;5;211m'; Z=$'\e[0m'
else
    R=; G=; Y=; D=; B=; C=; PK=; Z=
fi
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) UTF=1 ;; *) UTF=0 ;; esac
[ "${TERM:-}" = linux ] && UTF=0
if [ "$UTF" = 1 ]; then G_HR='─'; G_NOTE='♪'; G_OK='✔'; G_BAD='✘'; else G_HR='-'; G_NOTE='*'; G_OK='+'; G_BAD='x'; fi
UI_W=$(tput cols 2>/dev/null || echo 72); case "$UI_W" in ''|*[!0-9]*) UI_W=72 ;; esac
[ "$UI_W" -gt 76 ] && UI_W=76; [ "$UI_W" -lt 56 ] && UI_W=56
rep() { local i s=""; for ((i = 0; i < $2; i++)); do s+=$1; done; printf '%s' "$s"; }

n_ok=0; n_t1=0; n_t2=0; n_t3=0
declare -A MISS   # key "<tier>:<repo>" -> names joined with |

section() { local n=$((UI_W - ${#1} - 5)); [ "$n" -lt 3 ] && n=3
    printf '\n%s%s%s %s%s%s %s%s%s\n' "$C" "$G_HR$G_HR" "$Z" "$B" "$1" "$Z" "$D" "$(rep "$G_HR" "$n")" "$Z"; }

# record <tier> <label> <found 0/1> <pkg> <repo: dnf|manual> [note]
record() {
    local tier=$1 label=$2 found=$3 pkg=$4 repo=$5 note=${6:-}
    if [ "$found" = 1 ]; then
        n_ok=$((n_ok + 1))
        [ "$ONLY_CORE" = 1 ] && return
        printf '  %s[ ok ]%s %s\n' "$G" "$Z" "$label"
        return
    fi
    case "$tier" in
        1) n_t1=$((n_t1 + 1)); printf '  %s[MISS]%s %s' "$R" "$Z" "$label" ;;
        2) n_t2=$((n_t2 + 1)); [ "$ONLY_CORE" = 1 ] && return
           printf '  %s[warn]%s %s' "$Y" "$Z" "$label" ;;
        3) n_t3=$((n_t3 + 1)); [ "$ONLY_CORE" = 1 ] && return
           printf '  %s[ opt]%s %s' "$D" "$Z" "$label" ;;
    esac
    [ -n "$note" ] && printf '  %s(%s)%s' "$D" "$note" "$Z"
    printf '\n'
    add_pkg "$tier" "$pkg" "$repo"
}

# add_pkg <tier> <pkg> <repo>   (a package listed in a lower tier is not repeated in a higher one)
add_pkg() {
    local tier=$1 pkg=$2 repo=$3 t k
    [ -z "$pkg" ] && return
    case "$repo" in dnf) ;; *) repo=manual ;; esac
    for t in 1 2 3; do
        k="$t:$repo"
        case "|${MISS[$k]:-}|" in *"|$pkg|"*) return ;; esac
    done
    MISS["$tier:$repo"]+="${MISS[$tier:$repo]:+|}$pkg"
}

have() { command -v "$1" >/dev/null 2>&1; }

# cmd <tier> <command> <pkg> [repo] [note]
cmd() { have "$2"; record "$1" "$2" $((! $? )) "$3" "${4:-dnf}" "${5:-}"; }

# any <tier> <label> <pkg> <repo> <cmd1> <cmd2> ...   (one of the commands is enough)
any() {
    local tier=$1 label=$2 pkg=$3 repo=$4 c; shift 4
    for c in "$@"; do have "$c" && { record "$tier" "$label ($c)" 1 "$pkg" "$repo"; return; }; done
    record "$tier" "$label (none of: $*)" 0 "$pkg" "$repo"
}

# font <tier> <name to look for> <pkg or hint> <repo> [note]
font() { fc-list 2>/dev/null | grep -qi -- "$2"; record "$1" "font: $2" $((! $? )) "$3" "$4" "${5:-}"; }

# Directories where Qt looks for QML modules
QML_DIRS=()
for d in "${QML_IMPORT_PATH:-}" "${QML2_IMPORT_PATH:-}"; do
    IFS=: read -ra parts <<<"$d"; for p in "${parts[@]}"; do [ -n "$p" ] && QML_DIRS+=("$p"); done
done
for q in qmake6 qmake-qt6; do
    if have "$q"; then d=$("$q" -query QT_INSTALL_QML 2>/dev/null) && [ -n "$d" ] && QML_DIRS+=("$d"); fi
done
QML_DIRS+=(/usr/lib/qt6/qml /usr/lib64/qt6/qml /usr/lib/x86_64-linux-gnu/qt6/qml /usr/lib/aarch64-linux-gnu/qt6/qml /usr/local/lib/qt6/qml)

# qml <tier> <module/path> <pkg> [repo] [note]
qml() {
    local d found=0
    for d in "${QML_DIRS[@]}"; do [ -d "$d/$2" ] && { found=1; break; }; done
    record "$1" "QML module $2" "$found" "$3" "${4:-dnf}" "${5:-}"
}

# Directories where Qt looks for plugins
QT_PLUG_DIRS=()
for q in qmake6 qmake-qt6; do
    if have "$q"; then d=$("$q" -query QT_INSTALL_PLUGINS 2>/dev/null) && [ -n "$d" ] && QT_PLUG_DIRS+=("$d"); fi
done
QT_PLUG_DIRS+=(/usr/lib/qt6/plugins /usr/lib64/qt6/plugins /usr/lib/x86_64-linux-gnu/qt6/plugins /usr/lib/aarch64-linux-gnu/qt6/plugins)
# qtplugin <tier> <glob under the plugin dir> <pkg> <label> [note]
qtplugin() {
    local tier=$1 glob=$2 pkg=$3 label=$4 note=${5:-} d f found=0
    for d in "${QT_PLUG_DIRS[@]}"; do
        for f in $d/$glob; do [ -e "$f" ] && { found=1; break 2; }; done
    done
    record "$tier" "$label" "$found" "$pkg" dnf "$note"
}

printf '\n  %s%s %sSekaiPop dependency check%s   %s(read-only, nothing is installed)%s\n' "$PK" "$G_NOTE" "$B" "$Z" "$D" "$Z"

# --------------------------------------------------------------------------
section "System"
# --------------------------------------------------------------------------
if [ "$(id -u)" = 0 ]; then
    printf '  %s[warn]%s running as root; run this as your normal user\n' "$Y" "$Z"
fi
if [ -r /etc/os-release ]; then . /etc/os-release; printf '  %sdistro: %s%s\n' "$D" "${PRETTY_NAME:-unknown}" "$Z"; fi
if ! have dnf; then
    printf '  %s[note]%s no dnf found: package names below are Fedora names, translate them for your distro\n' "$Y" "$Z"
fi
cmd 1 systemctl systemd dnf "service checks and the power menu use it"
cmd 1 sh dash dnf
cmd 1 bash bash dnf

# --------------------------------------------------------------------------
section "Compositor"
# --------------------------------------------------------------------------
cmd 1 Hyprland hyprland dnf
cmd 1 hyprctl hyprland dnf
if have hyprctl && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    v=$(hyprctl version 2>/dev/null | grep -oiE 'v?[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)
    printf '  %sHyprland running, version: %s%s\n' "$D" "${v:-unknown}" "$Z"
fi
if [ -f "$HOME/.config/hypr/hyprland.lua" ]; then
    printf '  %sconfig mode: Lua (hyprland.lua)%s\n' "$D" "$Z"
    if grep -q 'sekaipop_overrides' "$HOME/.config/hypr/hyprland.lua" 2>/dev/null \
       || grep -rqs 'sekaipop_overrides' "$HOME/.config/hypr" 2>/dev/null; then
        record 3 'hyprland.lua loads sekaipop_overrides' 1 "" manual
    else
        record 3 'hyprland.lua loads sekaipop_overrides' 0 "" manual 'add: pcall(require, "sekaipop_overrides") or Settings changes are lost on reload'
    fi
elif [ -f "$HOME/.config/hypr/hyprland.conf" ]; then
    printf '  %sconfig mode: hyprlang (hyprland.conf); the rice supports both%s\n' "$D" "$Z"
fi

# --------------------------------------------------------------------------
section "Quickshell and Qt 6"
# --------------------------------------------------------------------------
cmd 1 qs quickshell dnf "also: quickshell"
cmd 1 quickshell quickshell dnf
if have qs || have quickshell; then
    for m in Quickshell/Hyprland Quickshell/Wayland Quickshell/Io Quickshell/Widgets \
             Quickshell/Services/Pam Quickshell/Services/Polkit Quickshell/Services/Notifications \
             Quickshell/Services/UPower Quickshell/Services/Pipewire Quickshell/Services/Mpris \
             Quickshell/Services/SystemTray; do
        qml 1 "$m" quickshell dnf "your Quickshell build lacks this module"
    done
else
    printf '  %s(Quickshell module checks skipped until quickshell is installed)%s\n' "$D" "$Z"
fi
qml 1 QtMultimedia qt6-qtmultimedia dnf "video wallpaper"
qml 1 QtQuick/Effects qt6-qtdeclarative dnf "MultiEffect, Qt 6.5+"
qml 1 QtQuick/Shapes qt6-qtdeclarative dnf
qml 1 Qt/labs/folderlistmodel qt6-qtdeclarative dnf
QT_CHECKED=0
for q in qmake6 qmake-qt6 qtpaths6; do
    if have "$q"; then
        qv=$("$q" -query QT_VERSION 2>/dev/null || "$q" --qt-version 2>/dev/null)
        if [ -n "$qv" ]; then
            if [ "$(printf '%s\n6.7.0\n' "$qv" | sort -V | head -n1)" = "6.7.0" ]; then
                record 1 "Qt $qv (needs 6.7 or newer)" 1 qt6-qtbase dnf
            else
                record 1 "Qt $qv (needs 6.7 or newer)" 0 qt6-qtbase dnf "too old for variable font axes"
            fi
            QT_CHECKED=1; break
        fi
    fi
done
[ "$QT_CHECKED" = 0 ] && printf '  %s(Qt version not checked: no qmake6/qtpaths6 found; Qt 6.7 or newer is needed)%s\n' "$D" "$Z"
qtplugin 1 "imageformats/libqsvg.so" qt6-qtsvg "Qt SVG plugin" "app icons from icon themes are SVG"
qtplugin 2 "imageformats/libqwebp.so" qt6-qtimageformats "Qt image formats (webp)" "the rice accepts webp wallpapers"
qtplugin 2 "platforms/*wayland*" qt6-qtwayland "Qt Wayland platform plugin"
any 2 "qsb shader compiler (to rebuild shaders/*.qsb for your Qt)" qt6-qtshadertools dnf qsb qsb-qt6 /usr/lib64/qt6/bin/qsb

# --------------------------------------------------------------------------
section "Fonts (not bundled with the rice)"
# --------------------------------------------------------------------------
if have fc-list; then
    font 1 "Google Sans Flex" "Google Sans Flex (clone github.com/end-4/google-sans-flex into ~/.local/share/fonts, then fc-cache -f)" manual \
        "not in the repos"
    font 1 "Material Symbols Rounded" "Material Symbols Rounded (MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf from github.com/google/material-design-icons/tree/master/variablefont into ~/.local/share/fonts, then fc-cache -f)" manual
    font 3 "Nerd Font" "JetBrainsMono Nerd Font (github.com/ryanoasis/nerd-fonts/releases into ~/.local/share/fonts)" manual "fish prompt icons"
    font 2 "emoji" google-noto-color-emoji-fonts dnf "emoji picker"
    if fc-list 2>/dev/null | grep -qiE 'Noto Sans|DejaVu Sans|Liberation Sans'; then
        record 2 "a general-purpose UI font (Noto Sans / DejaVu / Liberation)" 1 google-noto-sans-fonts dnf
    else
        record 2 "a general-purpose UI font (Noto Sans / DejaVu / Liberation)" 0 google-noto-sans-fonts dnf "browsers and apps show boxes without one"
    fi
    if [ -n "$(fc-list :lang=ja 2>/dev/null | head -n1)" ]; then record 2 "a CJK font (Japanese)" 1 noto-fonts-cjk dnf
    else record 2 "a CJK font (Japanese)" 0 noto-fonts-cjk dnf "welcome-logo kana, Japanese lyrics"; fi
else
    cmd 1 fc-list fontconfig dnf
fi

# --------------------------------------------------------------------------
section "Audio, network, bluetooth, power"
# --------------------------------------------------------------------------
cmd 1 wpctl wireplumber dnf "volume"
cmd 1 pactl pulseaudio-utils dnf "mixer; the pipewire-pulse server answers it"
cmd 2 parec pulseaudio-utils dnf "visualizer audio tap (or pw-record)"
cmd 2 paplay pulseaudio-utils dnf "timer alarm fallback"
cmd 1 nmcli NetworkManager dnf "Wi-Fi / Ethernet panel"
cmd 1 bluetoothctl bluez dnf "Bluetooth panel"
any 2 "Wi-Fi settings app (Quick Panel > Wi-Fi > Advanced)" plasma-nm dnf kcmshell6 nm-connection-editor gnome-control-center
any 2 "Bluetooth settings app (Quick Panel > Bluetooth > Advanced)" blueman dnf blueman-manager blueberry kcmshell6 gnome-control-center
cmd 1 upower upower dnf "battery"
cmd 1 notify-send libnotify dnf "screenshots, errors, timers"
cmd 1 xdg-open xdg-utils dnf
cmd 2 xdg-user-dir xdg-user-dirs dnf
cmd 2 systemd-inhibit systemd dnf "Keep Awake"
any 2 "power profiles daemon (power profile button)" tuned-ppd dnf tuned-ppd powerprofilesctl
cmd 2 brightnessctl brightnessctl dnf "laptop brightness"
cmd 2 ddcutil ddcutil dnf "external monitor brightness"
cmd 2 hyprsunset hyprsunset dnf "Night Light and gamma"

# Services (warn only: other init systems exist)
if have systemctl; then
    svc() { # tier unit pkg scope(system|user)
        local s=system a=; [ "${4:-}" = user ] && { s=user; a=--user; }
        if systemctl $a is-active --quiet "$2" 2>/dev/null || systemctl $a is-enabled --quiet "$2" 2>/dev/null; then
            record "$1" "$s service $2 active/enabled" 1 "$3" dnf
        else
            record "$1" "$s service $2 active/enabled" 0 "$3" dnf "enable it: systemctl ${a:+$a }enable --now $2"
        fi
    }
    svc 2 NetworkManager.service NetworkManager system
    svc 2 bluetooth.service bluez system
    svc 2 upower.service upower system
    if rpm -q tuned-ppd >/dev/null 2>&1; then svc 2 tuned-ppd.service tuned-ppd system; else svc 2 power-profiles-daemon.service power-profiles-daemon system; fi
    svc 2 pipewire.service pipewire user
    svc 2 wireplumber.service wireplumber user
    svc 2 pipewire-pulse.service pipewire-pulseaudio user
fi

# --------------------------------------------------------------------------
section "Clipboard, screenshots, typing, pickers"
# --------------------------------------------------------------------------
cmd 1 wl-copy wl-clipboard dnf
cmd 1 wl-paste wl-clipboard dnf
cmd 2 cliphist cliphist dnf "clipboard history"
cmd 2 grim grim dnf "screenshots, region selector"
cmd 2 slurp slurp dnf
any 2 "ImageMagick" ImageMagick dnf magick convert
cmd 3 tesseract tesseract dnf "region OCR"
if have tesseract; then
    tesseract --list-langs 2>/dev/null | grep -qx eng && record 3 "tesseract language data (eng)" 1 tesseract-langpack-eng dnf \
        || record 3 "tesseract language data (eng)" 0 tesseract-langpack-eng dnf
fi
cmd 3 swappy swappy dnf "annotate on right-drag"
cmd 3 wf-recorder wf-recorder dnf "screen recording"
cmd 2 hyprpicker hyprpicker dnf "eyedropper"
cmd 2 wtype wtype dnf "on-screen keyboard, emoji paste"
cmd 1 curl curl dnf "weather, lyrics"
cmd 1 jq jq dnf
any 2 "file chooser for avatar/banner/custom image" zenity dnf zenity kdialog yad
any 3 "terminal (kitty, foot, alacritty...)" kitty dnf kitty foot alacritty wezterm gnome-terminal

# --------------------------------------------------------------------------
section "Theming"
# --------------------------------------------------------------------------
cmd 2 matugen matugen dnf "wallpaper colours; needs matugen 2.x or newer"
if have matugen; then printf '  %s%s%s\n' "$D" "$(matugen --version 2>&1 | head -n1)" "$Z"; fi
cmd 2 gsettings glib2 dnf
cmd 2 gdbus glib2 dnf
cmd 3 dconf dconf dnf
if [ "${QT_QPA_PLATFORMTHEME:-}" = kde ]; then
    record 3 "Qt app colours (QT_QPA_PLATFORMTHEME=kde, qt6ct not needed)" 1 "" dnf
else
    any 3 "qt5ct / qt6ct (Qt app colours; then set QT_QPA_PLATFORMTHEME=qt6ct)" qt6ct dnf qt6ct qt5ct
fi
cmd 3 xrdb xrdb dnf "XWayland cursor"
[ -d /usr/share/themes/adw-gtk3 ] || [ -d "$HOME/.themes/adw-gtk3" ] \
    && record 3 "adw-gtk3 GTK theme" 1 adw-gtk3-theme dnf || record 3 "adw-gtk3 GTK theme" 0 adw-gtk3-theme dnf
if [ -n "${QT_QPA_PLATFORMTHEME:-}" ]; then
    printf '  %sQT_QPA_PLATFORMTHEME=%s%s\n' "$D" "$QT_QPA_PLATFORMTHEME" "$Z"
else
    printf '  %s[note]%s QT_QPA_PLATFORMTHEME is not set in this shell; set it in Hyprland (env) for Qt apps to follow the colours\n' "$Y" "$Z"
fi

# --------------------------------------------------------------------------
section "Audio visualizer, equalizer, media"
# --------------------------------------------------------------------------
cmd 2 python3 python3 dnf "note analyzer. NOTE: end-4's installer keeps Python in a private venv, this rice uses the SYSTEM python3"
if have python3; then
    python3 -c 'import numpy' 2>/dev/null && record 2 "python module numpy (system python3)" 1 python3-numpy dnf \
        || record 2 "python module numpy (system python3)" 0 python3-numpy dnf "without it the visualizer falls back to cava"
    python3 -c 'import aubio' 2>/dev/null && record 3 "python module aubio (system python3)" 1 aubio-python3 dnf \
        || record 3 "python module aubio (system python3)" 0 aubio-python3 dnf "optional better analyzer engine"
fi
cmd 2 cava cava dnf "visualizer fallback / PC waves"
any 2 "audio capture for the analyzer" pulseaudio-utils dnf parec pw-record
cmd 2 ffmpeg ffmpeg-free dnf "thumbnails, song recognition"
cmd 3 easyeffects easyeffects dnf "the 10-band equalizer"
any 3 "song recognition (songrec)" "songrec (flatpak install flathub com.github.marinm.songrec)" manual songrec com.github.marinm.songrec
cmd 3 mpvpaper mpvpaper dnf "video wallpaper via mpv (built-in player is the fallback)"

# --------------------------------------------------------------------------
section "Updates badge, displays, extras"
# --------------------------------------------------------------------------
cmd 3 dnf dnf5 dnf "update count"
cmd 3 flatpak flatpak dnf "Flatpak update count"
cmd 3 nwg-displays "nwg-displays (pipx install nwg-displays)" manual "extra in Settings > Hyprland > Displays"
cmd 3 hyprpm hyprland dnf "only for the scroll-overview plugin"
cmd 3 warp-cli "cloudflare-warp (Cloudflare repo: pkg.cloudflareclient.com)" manual "WARP toggle"
cmd 3 git git dnf
cmd 3 node nodejs dnf "Discord voice companion"
cmd 3 pnpm pnpm dnf "Discord voice companion"
any 3 "Discord client (Vesktop / Equibop / Discord)" "vesktop (flatpak install flathub dev.vencord.Vesktop)" manual vesktop equibop discord dev.vencord.Vesktop

# --------------------------------------------------------------------------
section "Bare-system layer (what a minimal Hyprland / no-desktop install often lacks)"
# --------------------------------------------------------------------------
# libexec_has <name>: executable in /usr/lib or /usr/libexec (portals live there, not in PATH)
libexec_has() { local d; for d in /usr/lib /usr/libexec /usr/lib64; do [ -x "$d/$1" ] && return 0; done; return 1; }

if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || [ -S "${XDG_RUNTIME_DIR:-/nonexistent}/bus" ]; then
    record 1 "D-Bus session bus" 1 dbus dnf
else
    record 1 "D-Bus session bus" 0 dbus dnf "start Hyprland from a real login (TTY or display manager), not su/ssh"
fi
if have loginctl && [ -n "${XDG_SESSION_ID:-}" ] && loginctl show-session "$XDG_SESSION_ID" >/dev/null 2>&1; then
    record 2 "systemd-logind session (power menu, suspend, lock)" 1 systemd dnf
else
    record 2 "systemd-logind session (power menu, suspend, lock)" 0 systemd dnf "log in through a TTY or display manager that opens a logind session"
fi
if libexec_has polkit-1/polkitd || have pkaction; then
    record 1 "polkit daemon (the shell is the agent, polkitd must exist)" 1 polkit dnf
else
    record 1 "polkit daemon (the shell is the agent, polkitd must exist)" 0 polkit dnf
fi
egl=0
for f in /usr/lib/libEGL.so* /usr/lib64/libEGL.so* /usr/lib/*-linux-gnu/libEGL.so*; do
    [ -e "$f" ] && { egl=1; break; }
done
if [ "$egl" = 0 ] && have ldconfig; then ldconfig -p 2>/dev/null | grep -q 'libEGL\.so' && egl=1; fi
if [ "$egl" = 0 ] && [ -x /sbin/ldconfig ]; then /sbin/ldconfig -p 2>/dev/null | grep -q 'libEGL\.so' && egl=1; fi
if [ "$egl" = 1 ]; then
    record 1 "OpenGL/EGL stack (Qt Quick renders with it)" 1 mesa-dri-drivers dnf
else
    record 1 "OpenGL/EGL stack (Qt Quick renders with it)" 0 mesa-dri-drivers dnf "also a GPU driver: mesa-vulkan-drivers / akmod-nvidia"
fi
have Xwayland && record 2 "Xwayland (X11 apps, cursor sync for them)" 1 xorg-x11-server-Xwayland dnf \
    || record 2 "Xwayland (X11 apps, cursor sync for them)" 0 xorg-x11-server-Xwayland dnf "normally pulled in by hyprland"
libexec_has xdg-desktop-portal && record 2 "xdg-desktop-portal" 1 xdg-desktop-portal dnf \
    || record 2 "xdg-desktop-portal" 0 xdg-desktop-portal dnf "screen sharing and file dialogs in apps (the rice itself doesn't call it)"
libexec_has xdg-desktop-portal-hyprland && record 2 "xdg-desktop-portal-hyprland" 1 xdg-desktop-portal-hyprland dnf \
    || record 2 "xdg-desktop-portal-hyprland" 0 xdg-desktop-portal-hyprland dnf "screen sharing"
libexec_has xdg-desktop-portal-gtk && record 3 "xdg-desktop-portal-gtk" 1 xdg-desktop-portal-gtk dnf \
    || record 3 "xdg-desktop-portal-gtk" 0 xdg-desktop-portal-gtk dnf "file dialogs in GTK/Electron apps"
any 2 "file manager (the dock's Files stack opens folders with xdg-open)" Thunar dnf thunar nautilus dolphin nemo pcmanfm pcmanfm-qt caja
if have xdg-mime && [ -n "$(xdg-mime query default inode/directory 2>/dev/null)" ]; then
    record 2 "default app for folders (xdg-mime inode/directory)" 1 "" dnf
else
    record 2 "default app for folders (xdg-mime inode/directory)" 0 "" dnf "xdg-mime default <your-file-manager>.desktop inode/directory"
fi
ic=0
for d in /usr/share/icons/* "$HOME"/.local/share/icons/* "$HOME"/.icons/*; do
    [ -f "$d/index.theme" ] || continue
    case "$(basename "$d")" in hicolor|default|locolor) continue ;; esac
    ic=$((ic + 1))
done
[ "$ic" -gt 0 ] && record 2 "an icon theme ($ic found; app icons in the dock, bar, overview)" 1 adwaita-icon-theme dnf \
    || record 2 "an icon theme (app icons in the dock, bar, overview)" 0 adwaita-icon-theme dnf "or papirus-icon-theme"
if have xdg-user-dir && [ -d "$(xdg-user-dir PICTURES 2>/dev/null)" ]; then
    record 2 "XDG user folders exist (~/Pictures, ~/Videos ...)" 1 xdg-user-dirs dnf
else
    record 2 "XDG user folders exist (~/Pictures, ~/Videos ...)" 0 xdg-user-dirs dnf "run: xdg-user-dirs-update"
fi
if [ -n "${WAYLAND_DISPLAY:-}" ] && have systemctl && systemctl --user show-environment >/dev/null 2>&1; then
    if systemctl --user show-environment 2>/dev/null | grep -q '^WAYLAND_DISPLAY='; then
        record 2 "session environment reaches user services (portals, screen sharing)" 1 "" manual
    else
        record 2 "session environment reaches user services (portals, screen sharing)" 0 "" manual \
            "autostart in Hyprland: dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP (install-deps.sh writes it)"
    fi
fi
any 3 "secret service for apps (Discord, browsers, VS Code, saved passwords)" gnome-keyring dnf gnome-keyring-daemon keepassxc
if [ -d "$HOME/.config/hypr" ]; then
    if grep -rqsE '(qs|quickshell)[[:space:]]+-c[[:space:]]+sekaipop' "$HOME/.config/hypr" 2>/dev/null; then
        record 2 "Hyprland autostarts the shell (qs -c sekaipop)" 1 "" manual
    else
        record 2 "Hyprland autostarts the shell (qs -c sekaipop)" 0 "" manual \
            'add to hyprland.lua: hl.on("hyprland.start", function() hl.exec_cmd("qs -c sekaipop") end)   (hyprlang: exec-once = qs -c sekaipop)'
    fi
fi

# --------------------------------------------------------------------------
section "Hardware access (info)"
# --------------------------------------------------------------------------
grp=$(id -nG 2>/dev/null)
for g in video i2c; do
    case " $grp " in
        *" $g "*) printf '  %s[ ok ]%s in group %s\n' "$G" "$Z" "$g" ;;
        *) printf '  %s[note]%s not in group %s%s\n' "$Y" "$Z" "$g" \
             "$([ $g = i2c ] && echo ' (ddcutil needs it: groupadd i2c, usermod -aG i2c $USER, load i2c-dev)' || echo ' (brightnessctl may need it)')" ;;
    esac
done

# --------------------------------------------------------------------------
section "Things that must NOT be running (the shell replaces them)"
# --------------------------------------------------------------------------
conflict=0
for p in mako dunst swaync fnott hyprpolkitagent polkit-gnome-authentication-agent-1 \
         polkit-kde-authentication-agent-1 lxqt-policykit-agent xfce-polkit; do
    if pgrep -x "$p" >/dev/null 2>&1; then
        printf '  %s[MISS]%s %s is running: stop it, the shell is its own notification server / polkit agent\n' "$R" "$Z" "$p"
        conflict=1; n_t1=$((n_t1 + 1))
    fi
done
[ "$conflict" = 0 ] && printf '  %s[ ok ]%s no conflicting notification daemon or polkit agent running\n' "$G" "$Z"
printf '  %s[note]%s if you log in from a display manager, pick plain Hyprland, not the uwsm one (end-4 says the same)%s\n' "$Y" "$Z" ""

# --------------------------------------------------------------------------
section "Rice folder (only if already copied)"
# --------------------------------------------------------------------------
RICE="${SEKAIPOP_DIR:-$HOME/.config/quickshell/sekaipop}"
if [ -f "$RICE/shell.qml" ]; then
    printf '  %sfound %s (version %s)%s\n' "$D" "$RICE" "$(cat "$RICE/VERSION" 2>/dev/null || echo '?')" "$Z"
    miss=0
    for f in shaders/sekai_blocks.frag.qsb shaders/welcome_warp.frag.qsb assets/images/default-wallpaper.png scripts/theming/matugen-template.json; do
        [ -f "$RICE/$f" ] || { printf '  %s[MISS]%s %s\n' "$R" "$Z" "$f"; miss=1; n_t1=$((n_t1 + 1)); }
    done
    [ "$miss" = 0 ] && printf '  %s[ ok ]%s shaders, assets and templates are in place\n' "$G" "$Z"
else
    printf '  %snot installed at %s yet (set SEKAIPOP_DIR to check another path)%s\n' "$D" "$RICE" "$Z"
fi

# --------------------------------------------------------------------------
section "Summary"
# --------------------------------------------------------------------------
printf '  ok: %s%d%s   core missing: %s%d%s   features missing: %s%d%s   optional missing: %s%d%s\n' \
    "$G" "$n_ok" "$Z" "$R" "$n_t1" "$Z" "$Y" "$n_t2" "$Z" "$D" "$n_t3" "$Z"
if [ "$n_t1" -eq 0 ]; then printf '  %s%s %sCore is complete: the shell can start.%s\n' "$G" "$G_OK" "$B" "$Z"
else printf '  %s%s %s%d core item(s) missing: install them first.%s\n' "$R" "$G_BAD" "$B" "$n_t1" "$Z"; fi

show_tier() { # <tier> <title>
    local t=$1 title=$2 dnf="${MISS[$1:dnf]:-}" man="${MISS[$1:manual]:-}" m
    [ -z "$dnf$man" ] && return
    dnf=${dnf//|/ }
    printf '\n  %s%s%s\n' "$B" "$title" "$Z"
    [ -n "$dnf" ] && printf '    sudo dnf install %s\n' "$dnf"
    if [ -n "$man" ]; then
        printf '    install by hand:\n'
        while IFS= read -r m; do printf '      - %s\n' "$m"; done <<<"${man//|/$'\n'}"
    fi
}
show_tier 1 "Install first (core):"
if [ "$ONLY_CORE" = 0 ]; then
    show_tier 2 "Then, for the features you want:"
    show_tier 3 "Optional extras:"
fi
printf '\n'
[ "$n_t1" -eq 0 ]
