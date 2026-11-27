#!/bin/sh
# Build Archrium end to end on a macOS runner.
set -eux

stage=$1

case "$stage" in
deps)
  brew install meson ninja gperf bison flex pkg-config autoconf automake libtool nasm groff
  dependencies/prepare.sh --product macos
  dependencies/build.sh
  dependencies/prepare.sh --product apple-gpu-vulkan-experiment
  dependencies/build-apple-gpu.sh --platform ios
  dependencies/prepare.sh --product ios-network
  dependencies/build-ios-network.sh --platform ios
  dependencies/prepare.sh --product ios-storage
  dependencies/build-ios-storage.sh
  dependencies/prepare.sh --product ios-compression
  dependencies/build-ios-zstd.sh
  ;;
runtime)
  cmake --preset kernarium-ios-device
  cmake --build --preset kernarium-ios-device
  cmake --preset kernarium-ios-device-android
  cmake --build --preset kernarium-ios-device-android
  chmod +x Kernarium/scripts/package-ios-frameworks.sh
  Kernarium/scripts/package-ios-frameworks.sh --sdk device
  ;;
app)
  xcodebuild \
    -project Kernarium/Kernarium.xcodeproj \
    -scheme Kernarium \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    ARCHS=arm64 \
    -derivedDataPath .build/DerivedData \
    build
  APP=$(find .build/DerivedData/Build/Products/Release-iphoneos -maxdepth 1 -name '*.app' | head -1)
  test -n "$APP"
  mkdir -p Payload
  cp -R "$APP" Payload/
  zip -qry Archrium-unsigned.ipa Payload
  ;;
*)
  echo "unknown stage: $stage" >&2
  exit 1
  ;;
esac
