#!/usr/bin/env bash
set -e

# =========================
# CONFIG (repo-root based)
# =========================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT="$SCRIPT_DIR"
CHECKOUT="$ROOT/webrtc"
SRC="$CHECKOUT/src"
DEPOT="$ROOT/depot_tools"
SDK="$ROOT/sdk"
RELEASE="$ROOT/release"

JOBS=$(nproc)

export PATH="$DEPOT:$PATH"

echo "===> Repo root: $ROOT"
echo "===> Using $JOBS threads"

# =========================
# HELP
# =========================

show_help() {
cat << EOF
WebRTC Multi-Build Script

Usage:
  ./build_webrtc.sh init                 -> setup depot_tools + fetch WebRTC
  ./build_webrtc.sh linux                -> build Linux
  ./build_webrtc.sh android             -> build all Android ABIs
  ./build_webrtc.sh windows             -> build Windows (experimental)
  ./build_webrtc.sh all                 -> build everything
  ./build_webrtc.sh linux android       -> build multiple targets

Options:
  --sync     Force re-sync of WebRTC deps

Targets:
  linux-x64
  android-arm64
  android-arm
  android-x64
  android-x86
  windows-x64

EOF
}

# =========================
# INIT
# =========================

init_webrtc() {
  echo "===> Setting up depot_tools..."

  if [ ! -d "$DEPOT" ]; then
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT"
  fi

  export PATH="$DEPOT:$PATH"

  echo "===> Creating WebRTC workspace..."
  mkdir -p "$CHECKOUT"
  cd "$CHECKOUT"

  if [ ! -d "$SRC" ]; then
    echo "===> Fetching WebRTC..."
    fetch --nohooks webrtc
  fi

  cd "$SRC"

  echo "===> Syncing..."
  gclient sync --force --reset --delete_unversioned_trees
  gclient runhooks

  echo "===> INIT DONE"
}

# =========================
# SYNC
# =========================

sync_webrtc() {
  echo "===> Syncing WebRTC..."
  cd "$CHECKOUT"
  gclient sync --force --reset --delete_unversioned_trees
  gclient runhooks
}

# =========================
# ANDROID DEP FIX
# =========================

ensure_android_deps() {
  echo "===> Ensuring Android deps..."
  cd "$CHECKOUT"
  gclient sync --force --reset --delete_unversioned_trees
  gclient runhooks
}

# =========================
# BUILD FUNCTION
# =========================

build_target() {
  NAME=$1
  GN_ARGS=$2
  OUT_DIR="$SRC/out/$NAME"

  echo ""
  echo "=============================="
  echo "===> Building: $NAME"
  echo "=============================="

  cd "$SRC"

  gn gen "$OUT_DIR" --args="$GN_ARGS"

  ninja -C "$OUT_DIR" webrtc -j$JOBS

  # ---- Package ----
  TARGET_SDK="$SDK/$NAME"
  rm -rf "$TARGET_SDK"
  mkdir -p "$TARGET_SDK/include" "$TARGET_SDK/lib"

  # headers
  cp -r api rtc_base modules media pc "$TARGET_SDK/include/" 2>/dev/null || true

  echo "===> Collecting libs ($NAME)..."
  find "$OUT_DIR/obj" -name "*.a" -exec cp {} "$TARGET_SDK/lib/" \;

  mkdir -p "$RELEASE"
  ZIP_NAME="webrtc-$NAME.zip"

  cd "$SDK"
  zip -r "$RELEASE/$ZIP_NAME" "$NAME" > /dev/null

  echo "===> DONE: $ZIP_NAME"
}

# =========================
# TARGET DEFINITIONS
# =========================

build_linux() {
  build_target "linux-x64" "
target_os=\"linux\"
target_cpu=\"x64\"
is_debug=false
rtc_use_pipewire=true
rtc_use_x11=true
is_clang=true
use_sysroot=false
treat_warnings_as_errors=false
"
}

build_android() {
  ensure_android_deps

  build_target "android-arm64" "
target_os=\"android\"
target_cpu=\"arm64\"
is_debug=false
is_clang=true
rtc_include_tests=false
rtc_build_examples=false
treat_warnings_as_errors=false
"

  build_target "android-arm" "
target_os=\"android\"
target_cpu=\"arm\"
is_debug=false
is_clang=true
rtc_include_tests=false
rtc_build_examples=false
treat_warnings_as_errors=false
"

  build_target "android-x64" "
target_os=\"android\"
target_cpu=\"x64\"
is_debug=false
is_clang=true
rtc_include_tests=false
rtc_build_examples=false
treat_warnings_as_errors=false
"

  build_target "android-x86" "
target_os=\"android\"
target_cpu=\"x86\"
is_debug=false
is_clang=true
rtc_include_tests=false
rtc_build_examples=false
treat_warnings_as_errors=false
"
}

build_windows() {
  build_target "windows-x64" "
target_os=\"win\"
target_cpu=\"x64\"
is_debug=false
is_clang=true
treat_warnings_as_errors=false
" || echo "⚠️ Windows build failed (expected on Linux)"
}

# =========================
# MAIN
# =========================

if [ $# -eq 0 ]; then
  show_help
  exit 0
fi

if [ "$1" == "help" ]; then
  show_help
  exit 0
fi

if [ "$1" == "init" ]; then
  init_webrtc
  exit 0
fi

FORCE_SYNC=0
ARGS=()

for arg in "$@"; do
  if [ "$arg" == "--sync" ]; then
    FORCE_SYNC=1
  else
    ARGS+=("$arg")
  fi
done

# Sync if requested or missing checkout
if [ $FORCE_SYNC -eq 1 ] || [ ! -d "$SRC" ]; then
  sync_webrtc
fi

# Run selected builds
for target in "${ARGS[@]}"; do
  case "$target" in
    linux)
      build_linux
      ;;
    android)
      build_android
      ;;
    windows)
      build_windows
      ;;
    all)
      build_linux
      build_android
      build_windows
      ;;
    *)
      echo "Unknown target: $target"
      show_help
      exit 1
      ;;
  esac
done

echo ""
echo "=============================="
echo "===> ALL DONE"
echo "Artifacts in: $RELEASE"
