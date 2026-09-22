# Lift

macOS için "focus follows mouse": imleç bir pencerenin üzerinde kısa süre durduğunda
klavye odağı tıklamaya gerek kalmadan o pencereye geçer.

Lift yalnızca menü çubuğunda yaşar, Dock'ta görünmez ve boşta CPU kullanmaz.
Üçüncü parti bağımlılığı yoktur.

---

## Ne yapar

İmleç, odakta olmayan bir pencerenin üzerinde **150 ms** (ayarlanabilir) kesintisiz
kalırsa o pencere klavye odağını alır. Tıklamaya gerek yoktur.

Asıl iş, odağın ne zaman değişmemesi gerektiğine karar vermektir. Lift dört durumda
odağa dokunmaz:

| Durum | Davranış |
|---|---|
| **Sürükleme** | Herhangi bir fare tuşu basılıyken odak değişmez. Dosya sürüklerken üzerinden geçtiğin pencereler odak çalmaz. |
| **Kaydırma** | Kaydırma sonrası 300 ms boyunca odak kilitlenir. Arka plandaki bir pencerede kaydırma yaparken odak kaymaz. |
| **Yazma** | Son tuş basımından sonra 1 sn (ayarlanabilir) odak kilitlenir. Cümlenin ortasında fareye çarpmak metni başka pencereye göndermez. |
| **Geçiş** | İmleç pencereler arasında hızlıca geçerken hiçbir şey olmaz. Yalnızca gerçekten durulan pencere odaklanır. |

Kilit süresi dolduğunda imleç hâlâ aynı pencerenin üzerindeyse odak geç de olsa
geçer; yeni bir fare hareketi beklenmez.

Hedef olarak yalnızca standart pencereler ve diyaloglar kabul edilir. Menüler,
Dock öğeleri, açılır kutular, araç paletleri ve küçültülmüş pencereler hedef
değildir. Aynı uygulamanın odakta olmayan başka bir penceresi geçerli hedeftir —
yani iki Chrome penceresi arasında da geçiş yapar.

---

## Gereksinimler

- macOS 13 veya üzeri
- Erişilebilirlik izni (aşağıda)
- Derlemek için Xcode

---

## Kurulum

```sh
git clone <repo> && cd lift
xcodebuild -project Lift.xcodeproj -scheme Lift -configuration Release build
open ~/Library/Developer/Xcode/DerivedData/Lift-*/Build/Products/Release/Lift.app
```

Günlük kullanımda **Release** derlemesini tercih edin. Debug derlemesi
optimizasyonsuz derlendiği için menü çubuğu menüsünde gözle görülür takılmaya
yol açıyor.

### Erişilebilirlik izni

Lift'in imlecin altındaki pencereyi görebilmesi için bu izne ihtiyacı var. İlk
açılışta sistem diyaloğu çıkar; **Sistem Ayarları → Gizlilik ve Güvenlik →
Erişilebilirlik** altından Lift'i açın.

İzin verildiği anda motor kendiliğinden devreye girer, uygulamayı yeniden
başlatmanız gerekmez.

> Proje geçerli bir imzalama sertifikası olmadan ad-hoc imzayla derlenir. Ad-hoc
> imzanın kimliği her derlemede değiştiği için macOS önceki izni geçersiz sayar.
> Yeniden derledikten sonra izin çalışmıyorsa:
> ```sh
> tccutil reset Accessibility com.aksoyakin.lift
> ```

---

## Kullanım

Menü çubuğundaki ikona tıklayın:

| Öğe | Açıklama |
|---|---|
| **Etkin** ⌘E | Odak takibini aç/kapat. Kapalıyken hiçbir sorgu yapılmaz. |
| **Gecikme** | Anında · 100 ms · 150 ms · 300 ms · 500 ms |
| **Girişte başlat** | Oturum açılışında otomatik başlat |
| **Çıkış** ⌘Q | |

Ayarlar anında etkilidir; yeniden başlatma gerekmez.

### Menüde olmayan ayar

Yazma kilidinin süresi menüde yer almaz, komut satırından değiştirilebilir:

```sh
defaults write com.aksoyakin.lift typingGuardMs 1500   # varsayılan: 1000
```

---

## Bilinen sınırlar

**Odaklanan pencere öne de gelir.** macOS'un public Erişilebilirlik API'sinde
"odakla ama öne getirme" ayrımı yapılamıyor: hem `kAXMain` hem `kAXFocused`
yazımı pencereyi öne alıyor. Bu, iki farklı uygulamanın ve aynı uygulamanın iki
penceresinin z-sırası kaydedilerek ölçüldü. X11'deki gibi arka plandaki pencereye
yazıp onu arkada bırakmak bu platformda mümkün değil.

**Web içerikli uygulamalarda konuma duyarlılık.** Electron ve benzeri
uygulamalarda imlecin altındaki öğe, sayfanın neresinde olduğuna göre farklı bir
erişilebilirlik alt ağacına düşer. Nadiren pencereye ulaşılamayabilir.

**Space / tam ekran algılanmaz.** Bu sürümde kapsam dışı.

---

## Teşhis

Bir pencereye odak geçmiyorsa sebebi tahmin etmeyin — `WindowResolver` neden
elediğini söyler:

```sh
log stream --level debug --predicate 'subsystem == "com.aksoyakin.lift"'
```

Akış açıkken imleci sorunlu pencerenin üzerine götürün.

| Satır | Anlamı | Bakılacak yer |
|---|---|---|
| `elendi: uygun olmayan subrole=...` | Pencerenin alt rolü `AXStandardWindow` veya `AXDialog` değil | `focusableSubroles` |
| `elendi: pencere küçültülmüş` | Beklenen davranış, hata değil | — |
| `pencereye ulaşılamadı: hitRole=...` | İmlecin altındaki öğeden pencereye çıkılamadı | `enclosingWindow` |
| *hiç satır yok* | Çözümleme başarılı; sorun odaklama tarafında | `FocusActions` |

Bu kayıtlar `debug` seviyesindedir: diske yazılmaz, yalnızca yukarıdaki komut
çalışırken üretilir.

---

## Mimari

```
        EventMonitor  ──(olay)──▶  FocusEngine  ──(emir)──▶  FocusActions
                                        │
                                        ├──(sorgu)──▶  WindowResolver
                                        │
                                        └──(okuma)──▶  SettingsStore
                                                            ▲
        MenuBarController ──────────(yazma)─────────────────┘

        PermissionManager ──(izin geldi)──▶ AppDelegate ──▶ EventMonitor.start()
```

| Dosya | Sorumluluk |
|---|---|
| `main.swift` | NSApplication kurulumu |
| `AppDelegate.swift` | Modülleri bağlama, yaşam döngüsü |
| `SettingsStore.swift` | UserDefaults tabanlı ayarlar |
| `PermissionManager.swift` | AX izni kontrolü ve bekleme |
| `EventMonitor.swift` | Global olay monitörleri, 50 ms throttle |
| `WindowResolver.swift` | Ekran noktası → pencere çözümü ve filtreler |
| `FocusEngine.swift` | Karar mantığı: kilitler ve debounce |
| `FocusActions.swift` | Fiili odaklama |
| `MenuBarController.swift` | NSStatusItem menüsü |

`FocusEngine` hiçbir somut sınıfa bağlı değildir; yalnızca protokollere
(`WindowResolving`, `FocusPerforming`, `PointerLocating`, `FocusSettings`,
`MonotonicClock`, `DebounceScheduling`). Testler bu sayede ekranda pencere açmadan
ve gerçek zaman beklemeden çalışır.

---

## Dağıtım

Dağıtılabilir bir sürüm üretmek için:

```sh
Tools/release.sh 1.0
```

Script derler, Developer ID ile imzalar, `.dmg` paketler, Apple'a notarization
için gönderir, dönen bileti pakete iliştirir ve sonucu doğrular. Çıktı
`build/Lift-1.0.dmg` olur ve indiren kişi hiçbir Gatekeeper uyarısı görmez.

### Tek seferlik hazırlık

**1. Developer ID sertifikası.** Xcode → Settings → Accounts → hesabınızı seçin →
Manage Certificates → **+** → *Developer ID Application*.

**2. Notarization kimlik bilgisi.** [appleid.apple.com](https://appleid.apple.com)
üzerinden uygulamaya özel bir parola oluşturun, sonra:

```sh
xcrun notarytool store-credentials lift-notary \
  --apple-id <apple-id> --team-id ZXM7ATF34C --password <uygulamaya-özel-parola>
```

İkisi de bir kez yapılır; sonraki sürümlerde yalnızca `Tools/release.sh` yeterlidir.

Notarization, uygulamanın **Hardened Runtime** ile imzalanmasını gerektirir; proje
zaten öyle yapılandırılmış. Erişilebilirlik izni notarization'dan bağımsızdır ve
her koşulda kullanıcıdan istenir.

### Uygulama ikonu

İkon, menü çubuğu sembolünden üretilir:

```sh
swift Tools/make-appicon.swift Lift/Assets.xcassets/AppIcon.appiconset
```

Sembolü veya rengi değiştirmek için scriptin başındaki `symbolName` ve gradyan
renklerini düzenleyip yeniden çalıştırın.

---

## Geliştirme

```sh
xcodebuild -project Lift.xcodeproj -scheme Lift -configuration Debug test
```

23 birim testi. Odaklama, dört kilidin her biri, debounce'un yeniden doğrulaması
ve ayarların anında etkisi için en az birer senaryo içerir.

### Kodu okuma sırası

Dosyaları alfabetik değil, verinin aktığı yönde okuyun:

1. Bu dosyanın **"Ne yapar"** bölümü — önce *ne* yapılacağını anlayın.
2. **`main.swift` → `AppDelegate.swift`** — giriş noktası ve bağlantı şeması.
3. **`SettingsStore.swift`** — en basit modül; projede her yerde kullanılan
   protokol + bağımlılık enjeksiyonu kalıbını burada görün.
4. **`EventMonitor.swift` → `FocusEngine.swift` → `FocusActions.swift`** —
   çekirdek boru hattı. `FocusEngine` projenin en önemli dosyasıdır.
5. **`LiftTests/FocusEngineTests.swift`** — davranış kurallarının çalıştırılabilir
   hâli. Bir davranışı anlamadıysanız testine bakın.
6. **`WindowResolver.swift`** — en zor dosya (erişilebilirlik ağacı, koordinat
   çevrimi). Motoru okuduktan sonra neden var olduğu anlaşılır.
7. **`PermissionManager.swift`, `MenuBarController.swift`** — bağımsız modüller.

### Kod standartları

- Guard-first stil: fonksiyonlar erken çıkışla düz akar, iç içe `if` kurulmaz.
- Magic number yok: süreler ve eşikler adlandırılmış sabit ya da ayardır.
- Force unwrap yalnızca guard ile korunmuş erişilebilirlik cast'lerinde.
- `print` yerine `os.Logger`; yalnızca durum geçişlerinde loglanır.
- Kod yorumsuzdur. İstisna, silindiğinde bilinçli bir kararın yanlışlıkla geri
  alınmasına yol açacak on satırdır.
