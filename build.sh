#!/bin/bash
set -euo pipefail

# Сборка Localhost Killer.app без Xcode-проекта: swiftc + ручной бандл + ad-hoc подпись.

APP_NAME="LocalhostKiller"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
RES_DIR="${APP_BUNDLE}/Contents/Resources"
BINARY="${MACOS_DIR}/${APP_NAME}"

# Архитектура хоста -> целевой triple.
ARCH="$(uname -m)"
case "${ARCH}" in
    arm64) TARGET="arm64-apple-macosx14.0" ;;
    x86_64) TARGET="x86_64-apple-macosx14.0" ;;
    *) echo "Неизвестная архитектура: ${ARCH}" >&2; exit 1 ;;
esac

echo "==> Компилирую (${TARGET})"
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS_DIR}" "${RES_DIR}"

swiftc -O \
    -target "${TARGET}" \
    -o "${BINARY}" \
    Sources/*.swift

echo "==> Генерирую иконку"
swift scripts/make-icon.swift
iconutil -c icns "${BUILD_DIR}/AppIcon.iconset" -o "${RES_DIR}/AppIcon.icns"
rm -rf "${BUILD_DIR}/AppIcon.iconset"

echo "==> Собираю бандл"
cp Info.plist "${APP_BUNDLE}/Contents/Info.plist"
printf 'APPL????' > "${APP_BUNDLE}/Contents/PkgInfo"

echo "==> Ad-hoc подпись (иначе macOS не запустит)"
codesign --force --deep --sign - "${APP_BUNDLE}"

echo ""
echo "Готово. Запуск:"
echo "    open ${APP_BUNDLE}"
