#!/bin/sh
# SOURCED by a product's postinstall (never executed): defines mav_stop_gui_instance, the
# stop-the-old-menu-bar-process step that MUST run before a postinstall (re)launches the app -- else
# an update leaves the OLD instance running beside the NEW one ("two menu-bar icons until I quit the
# old one"). launchd's own unload does not reliably kill a process that ignores SIGTERM, and `open -a`
# / a fresh agent load then starts the new instance beside the survivor.
#
# Match the bundle's Contents/MacOS/<exec> name, NOT the .app path, so an instance still running from a
# PRE-RENAME bundle is stopped too. TERM, then a guaranteed KILL; scoped to the console user (a
# per-user GUI process). Prefixed mav_ and contains no `exit`, so sourcing cannot disturb the caller
# (same discipline as updater/agent-load.in). Staged into the pkg's Scripts dir by package_pkg.sh, so
# it is present when the postinstall runs on the target -- a shared script on the build host is NOT.
mav_stop_gui_instance() {  # $1 = Contents/MacOS/<exec>   $2 = console uid
    _mav_exec="$1"; _mav_uid="$2"
    [ -n "$_mav_exec" ] || return 0
    case "$_mav_uid" in ''|*[!0-9]*) return 0;; esac   # no numeric console uid -> nothing to stop
    [ "$_mav_uid" -gt 0 ] || return 0
    pkill -TERM -U "$_mav_uid" -f "$_mav_exec" 2>/dev/null || true
    sleep 1
    pkill -KILL -U "$_mav_uid" -f "$_mav_exec" 2>/dev/null || true
}
