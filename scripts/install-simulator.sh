#!/bin/sh
# Pass a private configuration file; it is imported into Keychain and removed on first launch.
set -eu
cd "$(dirname "$0")/.."
: "${1:?Usage: sh scripts/install-simulator.sh /absolute/private/provisioning.json [simulator-udid]}"
DEVICE_ID="${2:-2CDA104A-F549-4B1B-81EB-8E11CAD0195D}"
xcrun simctl install "$DEVICE_ID" build/Simulator/CloudWatch.app
APP_DATA="$(xcrun simctl get_app_container "$DEVICE_ID" com.guochengqian.cloudwatch data)"
mkdir -p "$APP_DATA/Documents"
install -m 600 "$1" "$APP_DATA/Documents/provisioning.json"
xcrun simctl terminate "$DEVICE_ID" com.guochengqian.cloudwatch >/dev/null 2>&1 || true
xcrun simctl launch "$DEVICE_ID" com.guochengqian.cloudwatch
