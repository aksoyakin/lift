#!/bin/bash
#
# Lift'i dağıtıma hazırlar: imzala → paketle → notarize et → bileti iliştir.
#
#   Tools/release.sh 1.0
#
# Tek seferlik hazırlık için README'deki "Dağıtım" bölümüne bakın.
#
set -euo pipefail

VERSION="${1:-}"
TEAM_ID="ZXM7ATF34C"
NOTARY_PROFILE="${NOTARY_PROFILE:-lift-notary}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
ARCHIVE="$BUILD_DIR/Lift.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/Lift.app"

if [ -z "$VERSION" ]; then
    echo "kullanım: Tools/release.sh <sürüm>    örn: Tools/release.sh 1.0" >&2
    exit 1
fi

DMG="$BUILD_DIR/Lift-$VERSION.dmg"

step() { printf "\n\033[1m▸ %s\033[0m\n" "$1"; }
fail() { printf "\n\033[31m✗ %s\033[0m\n" "$1" >&2; exit 1; }

# ─── Ön koşullar ────────────────────────────────────────────────────────────

step "Ön koşullar denetleniyor"

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    fail "Developer ID Application sertifikası bulunamadı.
     Xcode → Settings → Accounts → (hesabın) → Manage Certificates → + →
     Developer ID Application ile oluşturun."
fi
echo "  sertifika: tamam"

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    fail "Notarization kimlik bilgisi '$NOTARY_PROFILE' bulunamadı. Bir kez şunu çalıştırın:
     xcrun notarytool store-credentials $NOTARY_PROFILE \\
       --apple-id <apple-id> --team-id $TEAM_ID --password <uygulamaya-özel-parola>
     Uygulamaya özel parola: appleid.apple.com → Oturum Açma ve Güvenlik"
fi
echo "  notarization kimliği: tamam"

# ─── Derle ve arşivle ───────────────────────────────────────────────────────

step "Arşivleniyor (sürüm $VERSION)"
rm -rf "$BUILD_DIR"
xcodebuild archive \
    -project "$PROJECT_ROOT/Lift.xcodeproj" \
    -scheme Lift \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$VERSION" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    ENABLE_HARDENED_RUNTIME=YES \
    | grep -E "error:|warning:|ARCHIVE" || true

[ -d "$ARCHIVE" ] || fail "Arşiv oluşturulamadı."

step "Dışa aktarılıyor"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$PROJECT_ROOT/Tools/ExportOptions.plist" \
    | grep -E "error:|EXPORT" || true

[ -d "$APP" ] || fail "Dışa aktarma başarısız."

# İmzanın gerçekten Developer ID olduğunu ve hardened runtime'ın açık olduğunu doğrula.
codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/  /'
codesign -d --verbose=2 "$APP" 2>&1 | grep -E "Authority=Developer ID|flags=" | sed 's/^/  /'

# ─── DMG paketle ────────────────────────────────────────────────────────────

step "DMG hazırlanıyor"
STAGING="$BUILD_DIR/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "Lift" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
echo "  $DMG"

# DMG'nin kendisi de imzalanmalı; aksi halde indirilen dosya doğrulanamaz.
codesign --sign "Developer ID Application" --timestamp "$DMG"

# ─── Notarize et ────────────────────────────────────────────────────────────

step "Apple'a gönderiliyor (birkaç dakika sürebilir)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

step "Bilet iliştiriliyor"
# Önce uygulamaya, sonra DMG'ye. Yalnızca DMG'ye iliştirmek yetmez: kullanıcı
# uygulamayı Applications'a kopyaladığında bilet dosyanın içinde taşınmaz ve
# Gatekeeper onu Apple'dan çevrimiçi sorgulamak zorunda kalır.
xcrun stapler staple "$APP"

# Uygulama değiştiği için DMG yeniden paketlenip imzalanmalı.
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Lift" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
codesign --sign "Developer ID Application" --timestamp "$DMG"

# Yeni DMG'nin kendisi de notarize edilip biletlenmeli.
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

# ─── Son doğrulama ──────────────────────────────────────────────────────────

step "Doğrulanıyor"
xcrun stapler validate "$DMG" | sed 's/^/  /'
spctl --assess --type open --context context:primary-signature -vv "$DMG" 2>&1 | sed 's/^/  /'

printf "\n\033[32m✓ Hazır: %s\033[0m\n" "$DMG"
echo "  Bu dosya doğrudan dağıtılabilir; indiren kişi Gatekeeper uyarısı görmez."
