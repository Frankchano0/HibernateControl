#!/bin/bash
# build_dmg.sh — 生成带 Applications 拖拽快捷方式的 DMG
# 用法: ./scripts/build_dmg.sh [版本号]  例: ./scripts/build_dmg.sh v5.3
# 默认输出到 ~/Desktop/

set -e

VERSION=${1:-"latest"}
APP_NAME="HibernateControl"
APP_PATH="$(dirname "$0")/../${APP_NAME}.app"
OUT_DIR="${2:-$HOME/Desktop}"
OUT_FILE="${OUT_DIR}/${APP_NAME}_${VERSION}.dmg"
TMP_DMG="/tmp/${APP_NAME}_${VERSION}.dmg"

echo "📦 Building DMG: ${APP_NAME} ${VERSION}"

create-dmg \
  --volname "${APP_NAME}" \
  --volicon "${APP_PATH}/Contents/Resources/AppIcon.icns" \
  --window-pos 200 120 \
  --window-size 560 320 \
  --icon-size 128 \
  --icon "${APP_NAME}.app" 140 150 \
  --hide-extension "${APP_NAME}.app" \
  --app-drop-link 420 150 \
  "${TMP_DMG}" \
  "${APP_PATH}"

cp "${TMP_DMG}" "${OUT_FILE}"
rm -f "${TMP_DMG}"

echo "✅ DMG 已生成: ${OUT_FILE} ($(du -h "${OUT_FILE}" | cut -f1))"
