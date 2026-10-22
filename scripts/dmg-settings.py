# dmgbuild settings for dist/Erst.dmg, read by scripts/build-dmg.sh.
# The window is the size of InstallerArt in ErstUI, and the icons sit where the art expects them:
# the echoes spread from the app icon, and the e's mouth opens toward Applications.

application = defines["app"]  # noqa: F821 (dmgbuild provides defines)
background = defines["background"]  # noqa: F821
icon = defines["volume_icon"]  # noqa: F821

format = "ULFO"
files = [application]
symlinks = {"Applications": "/Applications"}
hide_extension = ["Erst.app"]

# Finder counts its 32 point title bar in the window's height, so add it to the art's 400.
window_rect = ((240, 160), (660, 432))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True

icon_size = 128
text_size = 13
icon_locations = {
    "Erst.app": (172, 177),
    "Applications": (484, 283),
}
