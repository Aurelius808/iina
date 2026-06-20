#!/bin/bash

set -euo pipefail

SCRIPT_PATH=$(cd "$(dirname "$0")" && pwd)
ROOT_PATH=$(cd "$SCRIPT_PATH/.." && pwd)

xcodebuild \
  -project "$ROOT_PATH/iina.xcodeproj" \
  -scheme "Lilith Jam Sessions" \
  -configuration Debug \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  build
