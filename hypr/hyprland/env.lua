local home_dir = os.getenv("HOME")

-- Wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Applications
local xdg_data_dirs_old = os.getenv("XDG_DATA_DIRS") or ""
hl.env("XDG_DATA_DIRS", home_dir .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share:" .. xdg_data_dirs_old)

-- Qt theming. `kde` is what Settings > Desktop > System colours needs for Dolphin and other KDE
-- apps to follow the shell's colours (needs plasma-integration). qt5ct / qt6ct also work for
-- plain Qt apps; the shell's `system-theme.sh check` says which one you have.
-- Without plasma-integration the `kde` plugin is missing and Qt apps (the screen-share picker
-- too) fall back to an unstyled look, so qt6ct (which the shell also colours) is used then.
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
local has_kde_theme = is_file_exists("/usr/lib64/qt6/plugins/platformthemes/KDEPlasmaPlatformTheme6.so")
    or is_file_exists("/usr/lib/qt6/plugins/platformthemes/KDEPlasmaPlatformTheme6.so")
if has_kde_theme then
    hl.env("QT_QPA_PLATFORMTHEME", "kde")
    hl.env("XDG_MENU_PREFIX", "plasma-")
else
    hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
end

-- The shell runs $TERMINAL before its own list of terminals.
if terminalName and terminalName ~= "" and not os.getenv("TERMINAL") then
    hl.env("TERMINAL", terminalName)
end

-- File chooser for the avatar / banner picker: kdialog, zenity or yad. Unset = the shell picks.
-- hl.env("SEKAIPOP_CHOOSER", "kdialog")
