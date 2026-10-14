#!/bin/bash
# KeepAwake Jamf Pro uninstall policy.
#
# Removes the default LaunchDaemon, per-user LaunchAgents, the copied
# Application Support binary, and /usr/local/bin/keepawake. Safe to run
# more than once.
#
# Jamf script parameter:
#   $4  Optional extra launchd label to remove, in addition to
#       com.keepawake.agent and com.keepawake.daemon.

set -euo pipefail

EXTRA_LABEL="${4:-}"

bootout() {
  local domain="$1"
  local label="$2"
  /bin/launchctl bootout "${domain}/${label}" >/dev/null 2>&1 || true
}

bootout system com.keepawake.daemon
rm -f /Library/LaunchDaemons/com.keepawake.daemon.plist
if [[ -n "$EXTRA_LABEL" ]]; then
  bootout system "$EXTRA_LABEL"
  rm -f "/Library/LaunchDaemons/${EXTRA_LABEL}.plist"
fi

for home in /Users/* /var/root; do
  if [[ ! -d "$home" ]]; then
    continue
  fi
  user="$(basename "$home")"
  uid="$(id -u "$user" 2>/dev/null || true)"
  if [[ -n "$uid" ]]; then
    bootout "gui/${uid}" com.keepawake.agent
    if [[ -n "$EXTRA_LABEL" ]]; then
      bootout "gui/${uid}" "$EXTRA_LABEL"
    fi
  fi
  rm -f "$home/Library/LaunchAgents/com.keepawake.agent.plist"
  if [[ -n "$EXTRA_LABEL" ]]; then
    rm -f "$home/Library/LaunchAgents/${EXTRA_LABEL}.plist"
  fi
  rm -rf "$home/Library/Application Support/KeepAwake"
done

rm -f /usr/local/bin/keepawake
rm -rf "/Library/Application Support/KeepAwake"
rm -rf /Library/Logs/KeepAwake
echo "KeepAwake launchd jobs and the default binary were removed."
