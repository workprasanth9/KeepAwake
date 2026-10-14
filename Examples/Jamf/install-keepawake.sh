#!/bin/bash
# KeepAwake Jamf Pro install policy.
#
# Installs a LaunchDaemon or a per-user LaunchAgent. The keepawake binary
# must already be on disk. The usual order is: install the signed package
# from Scripts/build-pkg.sh, then run this script in the same policy or in
# a following policy.
#
# Jamf script parameters:
#   $4  Mode. One of:
#         indefinite
#         duration:8h
#         until:18:00
#         schedule:Mon-Fri 08:00-18:00
#         app:zoom.us
#         process:backupd
#       Default: schedule:Mon-Fri 08:00-18:00
#   $5  Target: daemon (default) or agent
#   $6  Assertion profile: default, or a plus-separated list of
#       display, idle, system, disk, user
#       Example: display+idle
#   $7  Reason string recorded with the assertion. Optional.
#   $8  Path to the keepawake binary. Default: /usr/local/bin/keepawake
#
# Exit codes match keepawake: 1 usage, 2 managed policy, 3 assertion, 4 launchd.

set -euo pipefail

MODE="${4:-schedule:Mon-Fri 08:00-18:00}"
TARGET="${5:-daemon}"
PROFILE="${6:-default}"
REASON="${7:-}"
BINARY="${8:-/usr/local/bin/keepawake}"

if [[ ! -x "$BINARY" ]]; then
  for candidate in \
    "/Library/Application Support/KeepAwake/keepawake" \
    "/opt/keepawake/keepawake"
  do
    if [[ -x "$candidate" ]]; then
      BINARY="$candidate"
      break
    fi
  done
fi

if [[ ! -x "$BINARY" ]]; then
  echo "keepawake binary is missing or not executable. Set parameter 8 or install the package first." >&2
  exit 1
fi

ARGS=()
case "$MODE" in
  indefinite)
    ARGS+=(--indefinite)
    ;;
  duration:*)
    ARGS+=(--duration "${MODE#duration:}")
    ;;
  until:*)
    ARGS+=(--until "${MODE#until:}")
    ;;
  schedule:*)
    ARGS+=(--schedule "${MODE#schedule:}")
    ;;
  app:*)
    ARGS+=(--while-app "${MODE#app:}")
    ;;
  process:*)
    ARGS+=(--while-process "${MODE#process:}")
    ;;
  *)
    echo "Invalid mode \"$MODE\"." >&2
    echo "Use indefinite, duration:8h, until:18:00, schedule:Mon-Fri 08:00-18:00, app:zoom.us, or process:backupd." >&2
    exit 1
    ;;
esac

if [[ -n "$PROFILE" && "$PROFILE" != "default" ]]; then
  IFS='+' read -r -a PARTS <<< "$PROFILE"
  for part in "${PARTS[@]}"; do
    case "$part" in
      display) ARGS+=(--display) ;;
      idle) ARGS+=(--idle-system) ;;
      system) ARGS+=(--system) ;;
      disk) ARGS+=(--disk) ;;
      user) ARGS+=(--user-activity) ;;
      "") ;;
      *)
        echo "Unknown profile component \"$part\". Use display, idle, system, disk, or user." >&2
        exit 1
        ;;
    esac
  done
fi

if [[ -n "$REASON" ]]; then
  ARGS+=(--reason "$REASON")
fi

if [[ "$TARGET" == "daemon" ]]; then
  "$BINARY" install --daemon --no-copy --binary "$BINARY" "${ARGS[@]}"
elif [[ "$TARGET" == "agent" ]]; then
  CONSOLE_USER="$(stat -f%Su /dev/console 2>/dev/null || true)"
  if [[ -z "$CONSOLE_USER" || "$CONSOLE_USER" == "root" || "$CONSOLE_USER" == "loginwindow" ]]; then
    echo "No console user is logged in, so a LaunchAgent cannot be bootstrapped." >&2
    exit 1
  fi
  "$BINARY" install --agent --user "$CONSOLE_USER" --no-copy --binary "$BINARY" "${ARGS[@]}"
else
  echo "Parameter 5 must be daemon or agent." >&2
  exit 1
fi

"$BINARY" status || true
exit 0
