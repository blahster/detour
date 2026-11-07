#!/bin/bash
# Detour build script.
#
#   ./build.sh test      parser and ranker tests (swiftc only, no signing)
#   ./build.sh build     generate the Xcode project and build a dev-signed Detour.app
#   ./build.sh run       build, then (re)launch
#   ./build.sh install   build, then copy to /Applications and launch
#   ./build.sh dist      Developer ID sign + notarize + staple -> dist/Detour.zip (shareable)
#
# Needs: Xcode (xcodebuild), `brew install xcodegen`, and Config.local (see Config.example).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Build/Products/Release/Detour.app"

load_config() {
  [ -f Config.local ] && source Config.local
  : "${DEVELOPMENT_TEAM:?Create Config.local from Config.example and set DEVELOPMENT_TEAM}"
  : "${BUNDLE_ID:?Create Config.local from Config.example and set BUNDLE_ID}"
  command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen"; exit 1; }
  export DEVELOPMENT_TEAM BUNDLE_ID
}

build() {
  load_config
  xcodegen generate --quiet
  xcodebuild -project Detour.xcodeproj -scheme Detour -configuration Release \
    -derivedDataPath build -allowProvisioningUpdates -quiet build
  echo "Built $APP"
}

dist() {
  load_config
  : "${NOTARY_PROFILE:?Set NOTARY_PROFILE in Config.local (see README, 'Share it with friends')}"
  local identity="${DIST_IDENTITY:-Developer ID Application}"
  security find-identity -v -p codesigning | grep -q "Developer ID Application" || {
    echo "No 'Developer ID Application' certificate in your keychain. See README, 'Share it with friends'."
    exit 1
  }

  xcodegen generate --quiet
  rm -rf build-dist dist
  mkdir -p dist
  # Same project, but signed for distribution: Developer ID, hardened runtime, secure timestamp.
  xcodebuild -project Detour.xcodeproj -scheme Detour -configuration Release \
    -derivedDataPath build-dist -quiet build \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$identity" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    ENABLE_HARDENED_RUNTIME=YES \
    CODE_SIGN_ENTITLEMENTS=Config/Detour.entitlements \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    ONLY_ACTIVE_ARCH=NO

  local app="build-dist/Build/Products/Release/Detour.app"
  codesign --verify --deep --strict --verbose=2 "$app"
  echo "Architectures: $(lipo -archs "$app/Contents/MacOS/Detour")"
  # Notarization rejects get-task-allow (a debugging entitlement). Fail early if it slipped in.
  if codesign -d --entitlements - "$app" 2>&1 | grep -q "get-task-allow"; then
    echo "The build still carries com.apple.security.get-task-allow; not submitting."
    exit 1
  fi

  ditto -c -k --keepParent "$app" build-dist/Detour-notarize.zip
  echo "Submitting to Apple for notarization (usually a few minutes)..."
  local out
  out=$(xcrun notarytool submit build-dist/Detour-notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait 2>&1) || true
  echo "$out"
  echo "$out" | grep -q "status: Accepted" || {
    echo
    echo "Notarization did not succeed. Get the reason with:"
    echo "  xcrun notarytool log <submission id above> --keychain-profile $NOTARY_PROFILE"
    exit 1
  }

  xcrun stapler staple "$app"
  spctl -a -vv "$app"
  ditto -c -k --keepParent "$app" dist/Detour.zip
  echo "Ready to share: dist/Detour.zip"
}

launch() {
  pkill -x Detour 2>/dev/null || true
  open "$1"
}

case "${1:-build}" in
  test)
    mkdir -p build
    swiftc -swift-version 5 Sources/DetourCore/*.swift Tests/main.swift -o build/detour-tests
    ./build/detour-tests
    ;;
  build)   build ;;
  run)     build; launch "$APP" ;;
  install)
    build
    pkill -x Detour 2>/dev/null || true
    rm -rf /Applications/Detour.app
    cp -R "$APP" /Applications/Detour.app
    open /Applications/Detour.app
    ;;
  dist)    dist ;;
  *) echo "usage: $0 [test|build|run|install|dist]"; exit 2 ;;
esac
