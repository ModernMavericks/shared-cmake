// Pure decision for what a post-relaunch updater launch should do, factored out of main.m.in so it can
// be unit-tested without a GUI (see tests/relaunch_decision.bats). No Foundation, no ObjC objects: plain
// C over C-string versions, safe to #include from the ARC ObjC host and from a `cc`-compiled test alike.
#ifndef MAVERICKS_RELAUNCH_DECISION_H
#define MAVERICKS_RELAUNCH_DECISION_H
#include <string.h>

typedef enum {
    MAV_RELAUNCH_NONE = 0,       // no relaunch marker: caller runs a normal update check
    MAV_RELAUNCH_BG_KEEP_EXIT,   // background + fresh marker: exit, KEEP the marker (post-install agent race)
    MAV_RELAUNCH_STALE_CHECK,    // stale marker: clear it, then run a normal update check
    MAV_RELAUNCH_SHOW_UPDATED,   // foreground + fresh + install landed: show the "updated" confirmation
    MAV_RELAUNCH_OFFER_RETRY     // foreground + fresh + install did NOT land: offer to retry the install
} mav_relaunch_action_t;

// marker_present / marker_fresh / background: 0-or-1 flags. pending_version = the display version we were
// installing (from the appcast item, persisted just before relaunch); may be NULL or empty. installed_version
// = this bundle's CURRENT CFBundleShortVersionString (may be NULL/empty if unavailable). A successful .pkg
// install replaced this bundle, so the
// two are equal; an intermittent Sparkle -60008 leaves the old version in place, so they differ -> OFFER_RETRY.
static inline mav_relaunch_action_t
mav_relaunch_decide(int marker_present, int marker_fresh, int background,
                    const char *pending_version, const char *installed_version) {
    if (!marker_present) return MAV_RELAUNCH_NONE;
    if (background) return marker_fresh ? MAV_RELAUNCH_BG_KEEP_EXIT : MAV_RELAUNCH_STALE_CHECK;
    if (!marker_fresh) return MAV_RELAUNCH_STALE_CHECK;
    // Foreground + fresh. No recorded target (e.g. a marker left by a pre-retry updater build) -> preserve
    // the legacy meaning: a fresh foreground marker meant "installed", so show the confirmation.
    if (!pending_version || pending_version[0] == '\0') return MAV_RELAUNCH_SHOW_UPDATED;
    if (installed_version && installed_version[0] != '\0'
        && strcmp(pending_version, installed_version) == 0) return MAV_RELAUNCH_SHOW_UPDATED;
    return MAV_RELAUNCH_OFFER_RETRY;
}
#endif
