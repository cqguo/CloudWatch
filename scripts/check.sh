#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
swift test
xcodebuild -project CloudWatch.xcodeproj -target CloudWatch \
  -configuration Debug -sdk watchsimulator \
  CONFIGURATION_BUILD_DIR=build/Simulator CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY=- CODE_SIGN_ENTITLEMENTS=scripts/Simulator.entitlements build
xcodebuild -project CloudWatch.xcodeproj -target CloudWatch \
  -configuration Release -sdk watchos \
  CONFIGURATION_BUILD_DIR=build/Watch CODE_SIGNING_ALLOWED=NO build
