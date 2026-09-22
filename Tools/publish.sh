#!/bin/bash
#
# Notarize edilmiş bir sürümü yayımlar: etiketler, GitHub Release açar,
# Homebrew cask'ini günceller.
#
#   Tools/release.sh 1.1     # önce: derle, imzala, notarize et
#   Tools/publish.sh 1.1     # sonra: yayımla
#
# Sürüm notu için Tools/release-notes/<sürüm>.md dosyası varsa kullanılır.
#
set -euo pipefail

VERSION="${1:-}"
REPO="aksoyakin/lift"
TAP_REPO="aksoyakin/homebrew-lift"
# brew komutlarında tap adı "homebrew-" öneki olmadan yazılır.
TAP_NAME="aksoyakin/lift"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG="$PROJECT_ROOT/build/Lift-$VERSION.dmg"
NOTES_FILE="$PROJECT_ROOT/Tools/release-notes/$VERSION.md"

step() { printf "\n\033[1m▸ %s\033[0m\n" "$1"; }
fail() { printf "\n\033[31m✗ %s\033[0m\n" "$1" >&2; exit 1; }

if [ -z "$VERSION" ]; then
    echo "kullanım: Tools/publish.sh <sürüm>    örn: Tools/publish.sh 1.1" >&2
    exit 1
fi

# ─── Ön koşullar ────────────────────────────────────────────────────────────

step "Ön koşullar denetleniyor"

[ -f "$DMG" ] || fail "$DMG bulunamadı. Önce: Tools/release.sh $VERSION"

# Biletsiz bir paketi yayımlamak, indiren herkeste Gatekeeper uyarısı demek.
xcrun stapler validate "$DMG" >/dev/null 2>&1 \
    || fail "DMG'de notarization bileti yok. Önce: Tools/release.sh $VERSION"
echo "  paket: biletli ve doğrulanmış"

command -v gh >/dev/null || fail "gh CLI kurulu değil."
gh auth status >/dev/null 2>&1 || fail "gh oturumu yok. Çalıştırın: gh auth login"
echo "  gh: oturum açık"

# Paketteki sürüm ile yayımlanan sürüm uyuşmazsa kullanıcı yanlış sürüm indirir.
BUNDLE_VERSION=$(/usr/bin/hdiutil attach -nobrowse -quiet "$DMG" -mountpoint /tmp/lift-publish 2>/dev/null \
    && /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" /tmp/lift-publish/Lift.app/Contents/Info.plist 2>/dev/null \
    || echo "?")
/usr/bin/hdiutil detach /tmp/lift-publish -quiet 2>/dev/null || true
[ "$BUNDLE_VERSION" = "$VERSION" ] \
    || fail "Paket içindeki sürüm ($BUNDLE_VERSION) istenen sürümle ($VERSION) uyuşmuyor."
echo "  sürüm: $VERSION (paketle uyumlu)"

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo "  sha256: $SHA"

# ─── Etiket ─────────────────────────────────────────────────────────────────

step "Etiketleniyor"
cd "$PROJECT_ROOT"
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
    echo "  v$VERSION zaten var"
else
    git tag -a "v$VERSION" -m "Lift $VERSION"
    echo "  v$VERSION oluşturuldu"
fi
git push -q origin "v$VERSION" 2>/dev/null || true

# ─── GitHub Release ─────────────────────────────────────────────────────────

step "GitHub Release açılıyor"

if [ -f "$NOTES_FILE" ]; then
    NOTES_ARG=(--notes-file "$NOTES_FILE")
    echo "  sürüm notu: $NOTES_FILE"
else
    TMP_NOTES=$(mktemp)
    cat > "$TMP_NOTES" <<EOF
### Kurulum

\`\`\`sh
brew install --cask $TAP_NAME/lift
\`\`\`

Ya da \`Lift-$VERSION.dmg\` dosyasını indirip \`Lift.app\`'i \`Applications\` klasörüne sürükleyin.

Uygulamayı ilk açtığınızda **Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik**
altından Lift'e izin vermeniz gerekir.

---

\`\`\`
SHA-256: $SHA
\`\`\`
EOF
    NOTES_ARG=(--notes-file "$TMP_NOTES")
    echo "  sürüm notu: varsayılan şablon"
fi

if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
    gh release upload "v$VERSION" "$DMG" --repo "$REPO" --clobber
    echo "  mevcut release güncellendi"
else
    gh release create "v$VERSION" "$DMG" --repo "$REPO" \
        --title "Lift $VERSION" "${NOTES_ARG[@]}"
    echo "  release oluşturuldu"
fi
[ -n "${TMP_NOTES:-}" ] && rm -f "$TMP_NOTES"

# ─── Homebrew cask ──────────────────────────────────────────────────────────

step "Homebrew cask güncelleniyor"

TAP_DIR=$(mktemp -d)
gh repo clone "$TAP_REPO" "$TAP_DIR" -- --quiet 2>/dev/null \
    || fail "Tap deposu klonlanamadı: $TAP_REPO"

CASK="$TAP_DIR/Casks/lift.rb"
[ -f "$CASK" ] || fail "Cask dosyası bulunamadı: Casks/lift.rb"

/usr/bin/sed -i '' \
    -e "s/^  version \".*\"$/  version \"$VERSION\"/" \
    -e "s/^  sha256 \".*\"$/  sha256 \"$SHA\"/" \
    "$CASK"

grep -q "version \"$VERSION\"" "$CASK" || fail "Cask'te sürüm güncellenemedi."
grep -q "sha256 \"$SHA\"" "$CASK" || fail "Cask'te sha256 güncellenemedi."

cd "$TAP_DIR"
if git diff --quiet; then
    echo "  cask zaten güncel"
else
    git add Casks/lift.rb
    git commit -q -m "Lift $VERSION"
    git push -q origin main
    echo "  cask $VERSION olarak güncellendi ve push edildi"
fi
rm -rf "$TAP_DIR"

# ─── Doğrulama ──────────────────────────────────────────────────────────────

step "Yayımlanan paket doğrulanıyor"

ASSET_URL="https://github.com/$REPO/releases/download/v$VERSION/Lift-$VERSION.dmg"
DOWNLOADED=$(mktemp)
curl -sL --max-time 120 -o "$DOWNLOADED" "$ASSET_URL" || fail "Paket indirilemedi."

REMOTE_SHA=$(shasum -a 256 "$DOWNLOADED" | awk '{print $1}')
[ "$REMOTE_SHA" = "$SHA" ] || fail "İndirilen paketin sha256 değeri uyuşmuyor."
echo "  sha256 eşleşiyor"

# İndirilen dosyanın Gatekeeper'dan geçtiğini, kullanıcının göreceği hâliyle doğrula.
xattr -w com.apple.quarantine "0083;$(printf %x "$(date +%s)");Safari;$(uuidgen)" "$DOWNLOADED"
spctl --assess --type open --context context:primary-signature "$DOWNLOADED" 2>/dev/null \
    || fail "İndirilen paket Gatekeeper denetiminden geçmedi."
echo "  Gatekeeper: kabul edildi"
rm -f "$DOWNLOADED"

printf "\n\033[32m✓ Lift %s yayımlandı\033[0m\n" "$VERSION"
echo "  https://github.com/$REPO/releases/tag/v$VERSION"
echo "  brew install --cask $TAP_NAME/lift"
