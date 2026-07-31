#!/bin/sh
# Presence gate for the "two menu-bar icons after an update" bug: a postinstall that (re)launches a GUI
# menu-bar app MUST also stop the prior instance. This behavior is dynamic -- there is no artifact to
# inspect like a PackageInfo -- so we lint the postinstall script the pkg actually ships.
#
# Presence, NOT order: a postinstall that both launches and stops is almost certainly stopping first
# (that is the entire point), and presence-checking avoids brittle shell order-of-operations parsing.
#
# "Relaunches a GUI menu-bar app":
#   - `open -a` of an app, OR
#   - a `launchctl asuser ... launchctl load` of a per-user agent (the systray's LaunchAgent).
#   The shared update-check agent loads via `launchctl bootstrap gui/` or `sudo -u ... launchctl load`
#   -- NEITHER matches -- and a root LaunchDaemon load (`launchctl load` with no asuser) is not a GUI
#   relaunch, so this does not fire on those.
# "Stops the prior instance": a call to mav_stop_gui_instance (postinstall-stop-gui.sh), a pkill, or a
#   `launchctl asuser ... unload`.
#
#   usage: assert_gui_relaunch_safe.sh <postinstall-file> [more...]
set -eu
[ "$#" -ge 1 ] || { echo "assert_gui_relaunch_safe: need at least one postinstall file" >&2; exit 2; }

status=0
for f in "$@"; do
  [ -f "$f" ] || { echo "assert_gui_relaunch_safe: no such file: $f" >&2; status=1; continue; }

  launches=0
  grep -Eq 'open[[:space:]]+-a' "$f" && launches=1
  # asuser ... launchctl load  (a per-user/GUI agent). `launchctl[[:space:]]+load` does NOT match
  # `launchctl unload`, so an asuser-unload line alone won't be read as a launch.
  grep -Eq 'asuser.*launchctl[[:space:]]+load' "$f" && launches=1

  if [ "$launches" -eq 0 ]; then
    echo "assert_gui_relaunch_safe: ok — ${f##*/} does not relaunch a GUI app (nothing to guard)"
    continue
  fi
  if grep -Eq 'mav_stop_gui_instance|pkill|launchctl[[:space:]]+unload' "$f"; then
    echo "assert_gui_relaunch_safe: ok — ${f##*/} stops the old instance before relaunching"
  else
    echo "assert_gui_relaunch_safe: ${f##*/} relaunches a GUI app but never stops the old instance -- an update will leave two menu-bar icons; call mav_stop_gui_instance (postinstall-stop-gui.sh) first" >&2
    status=1
  fi
done
exit "$status"
