#!/bin/bash
# Breathy'yi derler, .app paketini oluşturur, imzalar, ~/Applications'a kurar ve başlatır.
#
#   ./build.sh               derle + kur + başlat
#   ./build.sh --no-run      sadece derle ve build/Breathy.app oluştur
#   ./build.sh --universal   Apple Silicon + Intel (başka Mac'e taşımak için)
#   ./build.sh --dev-tools   geliştirici modlarıyla (--report, --snapshot); asla yayınlanmaz
#
# İmza: scripts/setup-signing.sh ile oluşturulan "Breathy Local Signing" sertifikası varsa
# onunla imzalar (macOS, Tam Disk Erişimi iznini derlemeler arasında hatırlar).
# Yoksa geçici (ad-hoc) imza kullanır.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Breathy"
SIGN_ID="${BREATHY_SIGN_ID:-Breathy Local Signing}"
APP_DIR="build/${APP_NAME}.app"
INSTALL_DIR="$HOME/Applications"
RUN=1
UNIVERSAL=0
FLAGS=()
for arg in "$@"; do
  case "$arg" in
    --no-run) RUN=0 ;;
    --universal) UNIVERSAL=1 ;;
    --dev-tools) FLAGS=(-Xswiftc -DBREATHY_DEV_TOOLS) ;;
    *) echo "Bilinmeyen seçenek: $arg" >&2; exit 2 ;;
  esac
done

if [[ $UNIVERSAL -eq 1 ]]; then
  echo "▸ Derleniyor (release, Apple Silicon + Intel)…"
  swift build -c release --arch arm64 ${FLAGS[@]+"${FLAGS[@]}"}
  swift build -c release --arch x86_64 ${FLAGS[@]+"${FLAGS[@]}"}
  BIN="build/${APP_NAME}-universal"
  mkdir -p build
  lipo -create \
    "$(swift build -c release --arch arm64 --show-bin-path)/${APP_NAME}" \
    "$(swift build -c release --arch x86_64 --show-bin-path)/${APP_NAME}" \
    -output "$BIN"
else
  echo "▸ Derleniyor (release)…"
  swift build -c release --arch arm64 ${FLAGS[@]+"${FLAGS[@]}"}
  BIN="$(swift build -c release --arch arm64 --show-bin-path)/${APP_NAME}"
fi

echo "▸ Paket oluşturuluyor: ${APP_DIR}"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/"

if security find-identity -p codesigning 2>/dev/null | grep -q "\"${SIGN_ID}\""; then
  echo "▸ İmzalanıyor: ${SIGN_ID}"
  codesign --force --sign "$SIGN_ID" "$APP_DIR"
else
  echo "⚠︎ '${SIGN_ID}' sertifikası yok; geçici (ad-hoc) imza kullanılıyor."
  echo "  Tam Disk Erişimi her derlemede sıfırlanır. Düzeltmek için: scripts/setup-signing.sh"
  codesign --force --sign - "$APP_DIR"
fi

if [[ $RUN -eq 0 ]]; then
  echo "✓ Hazır: ${APP_DIR}"
  exit 0
fi

echo "▸ Kuruluyor: ${INSTALL_DIR}/${APP_NAME}.app"
pkill -x "$APP_NAME" 2>/dev/null && sleep 0.5 || true
mkdir -p "$INSTALL_DIR"
rm -rf "${INSTALL_DIR:?}/${APP_NAME}.app"
cp -R "$APP_DIR" "$INSTALL_DIR/"
open "${INSTALL_DIR}/${APP_NAME}.app"
echo "✓ Breathy çalışıyor — sağ üstteki rüzgâr simgesine bak."
