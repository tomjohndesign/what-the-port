# dmgbuild settings for the website download: the app beside an Applications
# shortcut on a background that says to drag one onto the other.
# Run through ../make-dmg.sh. The background is the "32 · DMG A2" artboard in
# the WhatThePort Paper file: 660 × 400, exported at 1x and 2x with its
# preview icons hidden.
import os.path

app = defines["app"]  # noqa: F821 (dmgbuild provides defines)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}

# The window matches the background. Icon centres line up with the art.
background = "dmg/background.png"  # make-dmg.sh runs from WhatThePort/; @2x is picked up too
window_rect = ((200, 120), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 12
icon_locations = {
    os.path.basename(app): (170, 164),
    "Applications": (490, 164),
}
