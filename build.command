#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

echo ""
echo "===================================================="
echo "  Ethopex Workspace V1.11.12 — Expand Live Activity"
echo "  Data Manager + Campaign Automation"
echo "===================================================="
echo ""

if ! command -v xcrun >/dev/null 2>&1; then
  echo "Chưa có Apple Command Line Tools."
  xcode-select --install || true
  read -n 1 -s -r -p "Cài xong hãy chạy lại. Nhấn phím bất kỳ để đóng..."
  exit 1
fi

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Không tìm thấy Swift compiler."
  echo "Hãy chạy: xcode-select --install"
  read -n 1 -s -r -p "Nhấn phím bất kỳ để đóng..."
  exit 1
fi

ARCH="$(uname -m)"
APP="build/Ethopex Workspace.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

# Keep Swift's module cache inside a writable temporary directory. This makes
# the script work in clean CI runners and avoids permissions inherited from a
# previous local toolchain invocation.
BUILD_CACHE_DIR="${TMPDIR:-/tmp}/EthopexSwiftModuleCache"
mkdir -p "$BUILD_CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$BUILD_CACHE_DIR"

rm -rf build
mkdir -p "$MACOS" "$RES"

echo "Đang biên dịch bản tối ưu cho $ARCH..."

# IMPORTANT:
# -parse-as-library is intentional because CombinedMain.swift uses @main.
# This also guarantees accidental top-level executable expressions are rejected
# before the app is produced.
xcrun --sdk macosx swiftc \
  -parse-as-library \
  -O \
  -whole-module-optimization \
  -target "${ARCH}-apple-macos12.0" \
  -framework AppKit \
  -framework Foundation \
  -framework Security \
  Models.swift \
  FacebookPageSelection.swift \
  BulkImport.swift \
  WorkspaceUpdater.swift \
  DataManagerModule.swift \
  CampaignDataSource.swift \
  SourceParser.swift \
  GeminiAPI.swift \
  EthopexAPI.swift \
  CampaignTemplate.swift \
  QuizQA.swift \
  Pipeline.swift \
  LandingTranslationBatch.swift \
  MultilingualAutomation.swift \
  CampaignEngine.swift \
  APISettingsWindow.swift \
  CampaignModule.swift \
  CampaignSwiftUIHeader.swift \
  CombinedMain.swift \
  -o "$MACOS/EthopexWorkspace"

cp Info.plist "$APP/Contents/Info.plist"
cp NAM_QUIZ_MASTER_RULES.md "$RES/NAM_QUIZ_MASTER_RULES.md"

echo "Đang ký app local..."
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo ""
echo "===================================================="
echo " BUILD THÀNH CÔNG"
echo "===================================================="
echo ""
echo "App:"
echo "$APP"
echo ""
echo "Dữ liệu cũ giữ nguyên tại:"
echo "~/Library/Application Support/EthopexDataManager/"
echo ""
if [[ "${ETHOPEX_UPDATE_MODE:-0}" == "1" ]]; then
  echo "Update build mode: hoàn tất."
  exit 0
fi

if [[ "${CI:-0}" == "1" ]]; then
  echo "CI mode: bỏ qua bước mở app và chờ phím."
  exit 0
fi

echo "Đang mở app..."
open "$APP"

echo ""

read -n 1 -s -r -p "Nhấn phím bất kỳ để đóng Terminal..."
echo ""
