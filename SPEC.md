
# SPEC: FocusFollowsMouse — macOS Menü Çubuğu Uygulaması

Bu doküman bir yapay zeka kodlama ajanına yöneliktir. Görevleri sırayla uygula,
her görevin "bitti" tanımını sağla, davranış kurallarına harfiyen uy.

---

## 1. Hedef

macOS için "focus follows mouse" uygulaması yaz: imleç hangi pencerenin
üzerinde durursa klavye odağı otomatik olarak o pencereye geçer. Uygulama
yalnızca menü çubuğunda yaşar, Dock'ta görünmez.

## 2. Kısıtlar (değiştirilemez)

- Dil: **Swift 5.9+**, UI: **AppKit**. SwiftUI kullanma.
- Minimum hedef: **macOS 13**.
- **App Sandbox KAPALI** olacak (Accessibility API sandbox ile çalışmaz).
- `Info.plist` → `LSUIElement = YES`.
- Storyboard/XIB kullanma; giriş noktası `main.swift` + `AppDelegate`.
- Üçüncü parti bağımlılık yok (SPM paketi ekleme).
- Pencere tespiti **Accessibility (AX) API** ile yapılacak
  (`AXUIElementCopyElementAtPosition`), CGWindowList ile değil.
- Login'de başlatma **SMAppService** ile (eski SMLoginItemSetEnabled değil).

## 3. Mimari

Aşağıdaki dosyaları oluştur; her modül tek sorumluluk taşır:

| Dosya | Sorumluluk |
|---|---|
| `main.swift` | NSApplication kurulumu |
| `AppDelegate.swift` | Modülleri bağlama, yaşam döngüsü |
| `SettingsStore.swift` | UserDefaults tabanlı ayarlar (singleton) |
| `PermissionManager.swift` | AX izni kontrolü + izin verilene kadar bekleme |
| `EventMonitor.swift` | Global NSEvent monitörleri; delegate ile olay yayını |
| `WindowResolver.swift` | Ekran noktası → (AXUIElement pencere, pid) çözümü |
| `FocusEngine.swift` | Karar mantığı: kilitler + debounce (EventMonitor'un delegate'i) |
| `FocusActions.swift` | Fiili odaklama (activate + AX main/raise) |
| `MenuBarController.swift` | NSStatusItem menüsü |

Bağımlılık yönü: `EventMonitor → FocusEngine → WindowResolver / FocusActions`.
`FocusEngine` test edilebilirlik için `WindowResolver` ve `FocusActions`'a
protokoller üzerinden bağlansın (dependency injection).

## 4. Ayarlar (UserDefaults, anında etkili)

| Anahtar | Tip | Varsayılan | Anlam |
|---|---|---|---|
| `isEnabled` | Bool | `true` | Uygulama aktif mi |
| `raiseWindow` | Bool | `false` | true: focus+raise, false: sadece focus |
| `delayMs` | Int | `150` | Debounce süresi (ms) |
| `typingGuardMs` | Int | `1000` | Son tuş basımı sonrası odak kilidi (ms) |

Ayar değişikliği uygulama yeniden başlatılmadan etki ETMELİDİR.

## 5. Davranış Kuralları (normatif)

Her kural test edilebilir bir sözleşmedir. "MELİ/MEZ" bağlayıcıdır.

### 5.1 Odaklama
- R1. İmleç, öndeki uygulamaya ait OLMAYAN bir pencerede `delayMs` süresince
  kesintisiz kalırsa, o pencere odaklanMALIdır.
- R2. `delayMs` dolmadan imleç başka pencereye/boşluğa geçerse odak DEĞİŞMEMELİdir
  (bekleyen zamanlayıcı iptal edilir).
- R3. Süre dolduğunda imlecin hâlâ aynı pencerede olduğu YENİDEN doğrulanmalıdır;
  değilse odaklama yapılMAZ.
- R4. `raiseWindow == false` iken pencere odak alır ama `kAXRaiseAction`
  çağrılMAZ. `true` iken çağrılır.
- R5. Hedef pencere zaten odaklı pencereyse hiçbir AX yazma çağrısı yapılMAZ.
- R6. Aynı uygulamanın odaklı olmayan farklı bir penceresi de R1'e tabidir
  (uygulama önde diye atlanmaz).

### 5.2 Kilitler
- R7. Herhangi bir mouse tuşu basılıyken (drag) odak DEĞİŞMEZ; bekleyen
  zamanlayıcı iptal edilir. Tuş bırakılınca normal davranış döner.
- R8. Scroll olayından sonraki **300 ms** boyunca odak DEĞİŞMEZ.
- R9. Son `keyDown` veya `flagsChanged` olayından sonraki `typingGuardMs`
  boyunca odak DEĞİŞMEZ (typing guard).
- R10. `isEnabled == false` iken hiçbir AX sorgusu ve odaklama yapılMAZ
  (mouse handler en başta çıkar).

### 5.3 Pencere filtresi
- R11. Yalnızca `kAXRole == kAXWindowRole` olan öğeler odaklanabilir hedeftir.
  Menü, popup, tooltip, Dock öğeleri hedef DEĞİLdir.
- R12. `kAXMinimizedAttribute == true` olan pencere hedef DEĞİLdir.
- R13. `kAXSubroleAttribute` değeri `AXStandardWindow` veya
  `AXDialog` dışındaysa pencere hedef DEĞİLdir.

### 5.4 Koordinatlar
- R14. `NSEvent.mouseLocation` sol-ALT orijinlidir; AX API sol-ÜST bekler.
  Dönüşüm: `axY = NSScreen.screens[0].frame.height - cocoaY`.
  (Çoklu monitörde global düzlem için ana ekran yüksekliği referanstır.)

### 5.5 Performans
- R15. Mouse-moved olayları en fazla **50 ms'de bir** işlenMELİdir (throttle).
- R16. AX sorguları yalnızca tüm ucuz guard'lar (R7–R10) geçildikten sonra
  yapılMALIdır.
- R17. Boşta CPU kullanımı ~%0 olmalı; sürekli polling/Timer döngüsü kurulMAZ
  (yalnızca event-driven + tek seferlik debounce timer'ı).

### 5.6 İzin akışı
- R18. Açılışta `AXIsProcessTrusted()` kontrol edilir. İzin yoksa
  `AXIsProcessTrustedWithOptions` prompt seçeneğiyle çağrılır ve saniyede bir
  yoklanır; izin verilir verilmez motor otomatik başlar (yeniden başlatma
  gerekMEZ).

### 5.7 Menü çubuğu
- R19. Menü şunları içerir: "Etkin" (toggle, ⌘E), "Pencereyi öne getir"
  (toggle), "Gecikme" alt menüsü (Anında/100/150/300/500 ms, seçili olan
  işaretli), "Girişte başlat" (SMAppService toggle), ayırıcı, "Çıkış" (⌘Q).
- R20. Her toggle sonrası menü durumu (checkmark'lar) güncellenMELİdir.
- R21. İkon: SF Symbol `cursorarrow.rays`.

## 6. Tuzaklı API Referansları

Aşağıdaki çağrı kalıpları doğrudur; bunlardan sapma.

```swift
// İmleç altındaki AX öğesi (systemWide bir kez oluşturulup saklanır):
let systemWide = AXUIElementCreateSystemWide()
var element: AXUIElement?
AXUIElementCopyElementAtPosition(systemWide, Float(x), Float(y), &element)

// Öğeden pencereye:
AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &value)

// Pencereden pid:
var pid: pid_t = 0
AXUIElementGetPid(window, &pid)

// Odaklama sırası: önce uygulama, sonra pencere:
NSRunningApplication(processIdentifier: pid)?.activate()
AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
// yalnızca raiseWindow == true ise:
AXUIElementPerformAction(window, kAXRaiseAction as CFString)

// İki AXUIElement karşılaştırması CFEqual ile yapılır, == ile DEĞİL:
CFEqual(windowA, windowB)
```

Bilinen platform sınırı: farklı uygulamalar arası "focus without raise" tam
mümkün değildir (activate, macOS'un ana pencereyi öne almasına yol açabilir).
Bu davranış kabul edilir; workaround arama.

## 7. Görevler (bu sırayla)

1. **T1 — İskelet:** Proje yapısı, `main.swift`, `AppDelegate`, boş modül
   dosyaları, `LSUIElement`. *Bitti:* uygulama derlenir, menü çubuğunda ikon
   görünür, Dock'ta görünmez.
2. **T2 — İzin:** `PermissionManager` (R18). *Bitti:* izinsiz açılışta sistem
   diyaloğu çıkar; izin verilince log'a "aktif" düşer.
3. **T3 — Ayarlar:** `SettingsStore` (bölüm 4). *Bitti:* birim testleri geçer.
4. **T4 — Çözümleme:** `WindowResolver` (R11–R14). *Bitti:* imleç koordinatı
   verilince doğru pencere/pid döner; menü ve Dock üzerinde nil döner.
5. **T5 — Olaylar:** `EventMonitor` (R15, delegate protokolü: mouseMoved,
   dragStart/End, scrolled, typed). *Bitti:* olaylar delegate'e throttle'lı ulaşır.
6. **T6 — Motor:** `FocusEngine` + `FocusActions` (R1–R10, R16–R17).
   *Bitti:* bölüm 8'deki A1–A8 senaryoları elle doğrulanır.
7. **T7 — Menü:** `MenuBarController` (R19–R21). *Bitti:* tüm ayarlar menüden
   değiştirilebilir ve anında etki eder.
8. **T8 — Birim testleri:** `FocusEngine` debounce/kilit mantığı mock
   resolver/actions ile test edilir. *Bitti:* R1, R2, R7, R8, R9, R10 için
   en az birer test vardır ve geçer.

## 8. Kabul Testleri

| # | Adımlar | Beklenen |
|---|---|---|
| A1 | İki pencere aç; imleci arkadakine götür, 150 ms bekle | Arka pencere odaklanır |
| A2 | İmleci pencereler üzerinden 150 ms'den hızlı geçir | Odak hiç değişmez |
| A3 | Dosya sürüklerken başka pencere üzerinden geç | Odak değişmez, drop çalışır |
| A4 | Arkadaki pencerede scroll yap | İçerik kayar, odak değişmez |
| A5 | Ön pencerede yazarken imleci arka pencereye it | 1 sn boyunca odak değişmez; 1 sn sonra imleç hâlâ oradaysa değişir |
| A6 | Menü çubuğundan menü açıkken imleci gezdir | Menü kapanmaz, odak çalınmaz |
| A7 | Menüden "Etkin"i kapat, imleci gezdir | Hiçbir odak değişimi olmaz |
| A8 | Gecikmeyi 500 ms yap, A1'i tekrarla | Odak ~500 ms sonra geçer |
| A9 | raiseWindow kapalıyken üst üste iki pencerede arkadakine odaklan | Arkadaki odak alır; aynı uygulamadaysa öne gelmez |
| A10 | İzni Sistem Ayarları'ndan kaldırıp uygulamayı yeniden aç | İzin diyaloğu çıkar; onay sonrası motor kendiliğinden başlar |

## 9. Kapsam Dışı (yapma)

- Per-app istisna listesi, global kısayol, çoklu monitör başına ayar,
  Sparkle güncelleme, ayarlar penceresi, görsel odak ipucu.
- Space/fullscreen algılama (v1.1'e ertelendi).
- Notarization/dağıtım scriptleri.

## 10. Kod Standartları

- Force unwrap yalnızca AX cast'lerinde (`value as! AXUIElement`) ve guard'la
  korunmuş bağlamda; başka yerde kullanma.
- Her public tip ve fonksiyona tek satır doc comment.
- Guard-first stil: fonksiyonlar erken çıkışla düz akar, iç içe if kurma.
- Magic number yok: süreler ve eşikler adlandırılmış sabit ya da ayar olmalı.
- `print` yerine `NSLog`/`os.Logger`; yalnızca durum geçişlerinde logla.
