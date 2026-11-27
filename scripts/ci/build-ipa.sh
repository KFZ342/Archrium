#!/bin/sh
# Build Archrium end to end on a macOS runner.
set -eux

stage=$1

case "$stage" in
starter)
  sudo apt-get update
  sudo apt-get install -y build-essential bison flex gettext libncurses-dev libssl-dev \
    bc cpio rsync file wget curl unzip python3 git perl tar gzip bzip2 xz-utils debootstrap gdisk e2fsprogs
  rm -rf /tmp/starter-work /tmp/starter-release
  tools/rootfs/starter/build-all.sh --work /tmp/starter-work --output /tmp/starter-release --product boot-base-aarch64
  mkdir -p .build/starter
  BASE=$(find /tmp/starter-release -name uml-boot-base-aarch64.cpio.gz -print -quit)
  test -n "$BASE"
  cp "$BASE" .build/starter/uml-boot-base-aarch64.cpio.gz
  ;;
deps)
  brew install meson ninja gperf bison flex pkg-config autoconf automake libtool nasm groff
  dependencies/prepare.sh --product macos
  dependencies/build.sh
  python3 -m pip install --user --break-system-packages mako packaging pyyaml
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
  mkdir -p .build/rootfs/starter-20260928-boot-base-r1
  cp .build/starter/uml-boot-base-aarch64.cpio.gz \
    .build/rootfs/starter-20260928-boot-base-r1/uml-boot-base-aarch64.cpio.gz
  python3 - <<'PYEOF'
import hashlib, os
p='tools/rootfs/boot-ramdisk/accepted-aarch64.env'
size=os.path.getsize('.build/rootfs/starter-20260928-boot-base-r1/uml-boot-base-aarch64.cpio.gz')
sha=hashlib.sha256(open('.build/rootfs/starter-20260928-boot-base-r1/uml-boot-base-aarch64.cpio.gz','rb').read()).hexdigest()
s=open(p).read()
s=s.replace("UML_BOOT_BASE_SIZE=1398138", f"UML_BOOT_BASE_SIZE={size}")
import re
s=re.sub(r"UML_BOOT_BASE_SHA256='[0-9a-f]+'", f"UML_BOOT_BASE_SHA256='{sha}'", s)
open(p,'w').write(s)
print('boot base', size, sha)
PYEOF
  mkdir -p .build/kernel/artifacts
  curl -fL -o /tmp/android-kernel.tar.gz \
    https://github.com/imxieyi/Kernarium/releases/download/andarium-1.1/android-6.18-arm64-4k-20261119-6.18.60-ca1.tar.gz
  tar xzf /tmp/android-kernel.tar.gz -C .build/kernel/artifacts
  rm -rf .build/kernel/artifacts/mainline-6.18-arm64-4k-20261119-6.18.60-ca1
  cp -R .build/kernel/artifacts/android-6.18-arm64-4k-20261119-6.18.60-ca1 \
    .build/kernel/artifacts/mainline-6.18-arm64-4k-20261119-6.18.60-ca1
  python3 - <<'PYEOF'
import json
p='.build/kernel/artifacts/mainline-6.18-arm64-4k-20261119-6.18.60-ca1/kernel-artifact.json'
d=json.load(open(p))
d['family']='mainline-6.18'
d['directory_name']='mainline-6.18-arm64-4k-20261119-6.18.60-ca1'
json.dump(d,open(p,'w'),indent=2)
PYEOF
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
  if [ -z "${ARCHRIUM_ROOTFS:-}" ]; then
    mkdir -p .build/rootfs-parts
    rm -f .build/rootfs-parts/archrium.erofs.part.*
    gh release download rootfs-v1       -R "${GITHUB_REPOSITORY:-KFZ342/Archrium}"       -p 'archrium.erofs.part.*' -D .build/rootfs-parts
    cat .build/rootfs-parts/archrium.erofs.part.* > .build/archrium.erofs
    ARCHRIUM_ROOTFS=.build/archrium.erofs
  fi
  if [ -n "${ARCHRIUM_ROOTFS:-}" ]; then
    test -f "$ARCHRIUM_ROOTFS"
    cp "$ARCHRIUM_ROOTFS" "$APP/archrium.erofs"
  fi
  mkdir -p Payload
  cp -R "$APP" Payload/
  zip -qry Archrium-unsigned.ipa Payload
  ;;
*)
  echo "unknown stage: $stage" >&2
  exit 1
  ;;
esac
