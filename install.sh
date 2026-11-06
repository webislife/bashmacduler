#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TARGET_INPUT="${BASHMACDULER_INSTALL_PATH:-${SCRIPTBAR_INSTALL_PATH:-/Applications/BashMacDuler.app}}"
if [[ "$TARGET_INPUT" != /* ]]; then
    TARGET_INPUT="$PWD/$TARGET_INPUT"
fi

TARGET_NAME="$(basename "$TARGET_INPUT")"
TARGET_PARENT_INPUT="$(dirname "$TARGET_INPUT")"
if [[ "$TARGET_NAME" != "BashMacDuler.app" ]]; then
    echo "Цель установки должна называться BashMacDuler.app: $TARGET_INPUT"
    exit 1
fi

if [[ ! -d "$TARGET_PARENT_INPUT" ]]; then
    echo "Каталог установки не существует: $TARGET_PARENT_INPUT"
    exit 1
fi

TARGET_PARENT="$(cd -P -- "$TARGET_PARENT_INPUT" && pwd)"
TARGET="$TARGET_PARENT/$TARGET_NAME"
if [[ "$TARGET_PARENT" == "/" ]]; then
    echo "Установка непосредственно в корень диска запрещена."
    exit 1
fi

if [[ ! -w "$TARGET_PARENT" ]]; then
    echo "Нет прав на запись в $TARGET_PARENT. Запустите установку от пользователя с правами администратора."
    exit 1
fi

if [[ -L "$TARGET" ]]; then
    echo "Цель установки не должна быть символической ссылкой: $TARGET"
    exit 1
fi

EXPECTED_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ROOT/Info.plist")"
if [[ -e "$TARGET" ]]; then
    if [[ ! -d "$TARGET" || ! -f "$TARGET/Contents/Info.plist" ]]; then
        echo "Отказ: существующая цель не является приложением BashMacDuler: $TARGET"
        exit 1
    fi
    EXISTING_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$TARGET/Contents/Info.plist" 2>/dev/null || true)"
    if [[ "$EXISTING_BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
        echo "Отказ: bundle identifier существующего приложения не совпадает ($EXISTING_BUNDLE_ID)."
        exit 1
    fi
fi

"$ROOT/build.sh"

if pgrep -x "BashMacDuler" >/dev/null 2>&1 || pgrep -x "ScriptBar" >/dev/null 2>&1; then
    osascript -e 'tell application id "com.local.ScriptBar" to quit' >/dev/null 2>&1 || true
    sleep 1
    if pgrep -x "BashMacDuler" >/dev/null 2>&1 || pgrep -x "ScriptBar" >/dev/null 2>&1; then
        echo "Закройте BashMacDuler через кнопку «Выйти» и повторите установку."
        exit 1
    fi
fi

STAGE_ROOT="$(mktemp -d "$TARGET_PARENT/.BashMacDulerInstall.XXXXXX")"
STAGED_APP="$STAGE_ROOT/BashMacDuler.app"
BACKUP_APP="$STAGE_ROOT/Previous.app"
NEW_APP_INSTALLED=0
INSTALL_COMPLETE=0

cleanup_install() {
    local status=$?
    if [[ "$INSTALL_COMPLETE" != "1" ]]; then
        if [[ "$NEW_APP_INSTALLED" == "1" && -e "$TARGET" ]]; then
            rm -rf "$TARGET" || true
        fi
        if [[ -d "$BACKUP_APP" && ! -e "$TARGET" ]]; then
            mv "$BACKUP_APP" "$TARGET" || true
        fi
    fi
    rm -rf "$STAGE_ROOT"
    exit "$status"
}
trap cleanup_install EXIT

ditto "$ROOT/build/BashMacDuler.app" "$STAGED_APP"
xattr -cr "$STAGED_APP" 2>/dev/null || true
codesign --verify --deep --strict "$STAGED_APP"

if [[ -e "$TARGET" ]]; then
    mv "$TARGET" "$BACKUP_APP"
fi
mv "$STAGED_APP" "$TARGET"
NEW_APP_INSTALLED=1
codesign --verify --deep --strict "$TARGET"

if [[ -d "$BACKUP_APP" ]]; then
    rm -rf "$BACKUP_APP"
fi
INSTALL_COMPLETE=1

if [[ "${BASHMACDULER_SKIP_OPEN:-${SCRIPTBAR_SKIP_OPEN:-0}}" != "1" ]]; then
    open "$TARGET"
fi

echo "BashMacDuler установлен: $TARGET"
