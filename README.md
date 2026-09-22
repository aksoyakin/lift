# Lift

**macOS için focus follows mouse.** İmleci bir pencerenin üzerine götürün, kısa bir
an bekleyin — klavye odağı tıklamaya gerek kalmadan o pencereye geçer.

Lift menü çubuğunda yaşar, Dock'ta görünmez, boşta CPU kullanmaz ve hiçbir üçüncü
parti bağımlılığı yoktur.

---

## Neden?

Pencereler arasında geçiş yapmak için sürekli tıklamak, özellikle kod yazarken
veya iki belgeyi karşılaştırırken gereksiz bir adım. Linux ve BSD masaüstlerinde
onlarca yıldır standart olan "focus follows mouse" davranışı macOS'ta yok.

Lift bunu ekler — ama dikkatli davranarak. Naif bir uygulama, imleç bir pencerenin
üzerinden geçer geçmez odağı değiştirir ve sistemi kullanılamaz hale getirir.
Lift'in asıl işi odağı değiştirmek değil, **ne zaman değiştirmemesi gerektiğine
karar vermek.**

---

## Kurulum

### İndir

[**Releases**](../../releases) sayfasından en son `Lift-x.y.dmg` dosyasını indirin,
açın ve `Lift.app`'i `Applications` klasörüne sürükleyin.

Uygulama Apple tarafından notarize edilmiştir; açarken herhangi bir güvenlik
uyarısı görmezsiniz.

### Erişilebilirlik izni verin

Lift'in imlecin altındaki pencereyi görebilmesi için macOS'un Erişilebilirlik
iznine ihtiyacı var. Bu izin olmadan uygulama hiçbir şey yapamaz.

İlk açılışta bir sistem diyaloğu çıkar. **Sistem Ayarları → Gizlilik ve Güvenlik →
Erişilebilirlik** altından Lift'i açın.

İzni verdiğiniz anda uygulama çalışmaya başlar; yeniden başlatmanız gerekmez.

---

## Kullanım

Menü çubuğundaki ikona tıklayın:

| Öğe | Açıklama |
|---|---|
| **Etkin** ⌘E | Odak takibini aç/kapat |
| **Gecikme** | Anında · 100 ms · 150 ms · 300 ms · 500 ms |
| **Girişte başlat** | Oturum açılışında otomatik başlat |
| **Çıkış** ⌘Q | |

Ayarlar anında etkilidir.

**Gecikme**, odağın geçmesi için imlecin pencerede ne kadar beklemesi gerektiğini
belirler. Varsayılan 150 ms çoğu kullanım için dengelidir: istemsiz geçişleri
önleyecek kadar uzun, fark edilmeyecek kadar kısa. Daha az istemsiz geçiş için
300–500 ms deneyin.

---

## Odak ne zaman değişmez

Lift dört durumda odağa dokunmaz. Bunlar uygulamanın kullanılabilir olmasını
sağlayan asıl özelliklerdir:

| Durum | Davranış |
|---|---|
| **Sürükleme** | Herhangi bir fare tuşu basılıyken odak değişmez. Dosya sürüklerken üzerinden geçtiğiniz pencereler odak çalmaz. |
| **Kaydırma** | Kaydırma sonrası 300 ms boyunca odak kilitlenir. Arka plandaki bir pencerede kaydırma yaparken odak kaymaz. |
| **Yazma** | Son tuş basımından sonra 1 saniye odak kilitlenir. Cümlenin ortasında fareye çarpmak metni başka pencereye göndermez. |
| **Hızlı geçiş** | İmleç pencereler arasında hızlıca geçerken hiçbir şey olmaz. Yalnızca gerçekten durulan pencere odaklanır. |

Kilit süresi dolduğunda imleç hâlâ aynı pencerenin üzerindeyse odak geç de olsa
geçer; yeni bir fare hareketi beklemeniz gerekmez.

Hedef olarak yalnızca standart pencereler ve diyaloglar kabul edilir. Menüler,
Dock öğeleri, açılır kutular, araç paletleri ve küçültülmüş pencereler hedef
değildir. Aynı uygulamanın odakta olmayan başka bir penceresi geçerli hedeftir —
iki tarayıcı penceresi arasında da geçiş yapar.

---

## Bilinen sınırlar

**Odaklanan pencere öne de gelir.** macOS'un Erişilebilirlik API'sinde "odakla ama
öne getirme" ayrımı yapılamıyor: hem `kAXMain` hem `kAXFocused` yazımı pencereyi
öne alıyor. Bu, iki farklı uygulamanın ve aynı uygulamanın iki penceresinin
z-sırası kaydedilerek ölçüldü. X11'deki gibi arka plandaki pencereye yazıp onu
arkada bırakmak bu platformda mümkün değil.

**Web içerikli uygulamalarda konuma duyarlılık.** Electron ve benzeri uygulamalarda
imlecin altındaki öğe, sayfanın neresinde olduğuna göre farklı bir erişilebilirlik
alt ağacına düşer; nadiren pencereye ulaşılamayabilir.

**Space ve tam ekran algılanmaz.** Bu sürümde kapsam dışı.

**Arayüz yalnızca Türkçedir.**

---

## Gereksinimler

macOS 13 veya üzeri. Apple Silicon ve Intel desteklenir.

---

## Kaynak koddan derleme

```sh
git clone <repo-url> && cd lift
xcodebuild -project Lift.xcodeproj -scheme Lift -configuration Release build
open ~/Library/Developer/Xcode/DerivedData/Lift-*/Build/Products/Release/Lift.app
```

Günlük kullanımda Release derlemesini tercih edin; Debug derlemesi optimizasyonsuz
derlendiği için menü çubuğu menüsünde gözle görülür takılmaya yol açıyor.

> Geçerli bir imzalama sertifikası olmayan makinelerde proje ad-hoc imzayla
> derlenir. Ad-hoc imzanın kimliği her derlemede değiştiği için macOS önceki
> Erişilebilirlik iznini geçersiz sayar. Yeniden derledikten sonra izin
> çalışmıyorsa:
> ```sh
> tccutil reset Accessibility com.aksoyakin.lift
> ```
> Bu yalnızca kendi derlediğiniz sürümler için geçerlidir; indirilen sürümde
> böyle bir sorun yoktur.

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
| `PermissionManager.swift` | Erişilebilirlik izni kontrolü ve bekleme |
| `EventMonitor.swift` | Global olay monitörleri, 50 ms throttle |
| `WindowResolver.swift` | Ekran noktası → pencere çözümü ve filtreler |
| `FocusEngine.swift` | Karar mantığı: kilitler ve debounce |
| `FocusActions.swift` | Fiili odaklama |
| `MenuBarController.swift` | NSStatusItem menüsü |

`FocusEngine` hiçbir somut sınıfa bağlı değildir; yalnızca protokollere. Ekran,
zaman ve zamanlayıcı bağımlılıkları dışarıdan verilir — bu sayede 23 birim testi
ekranda pencere açmadan ve gerçek zaman beklemeden, milisaniyeler içinde çalışır.

```sh
xcodebuild -project Lift.xcodeproj -scheme Lift -configuration Debug test
```

Kodu okumak için önerilen sıra: `main.swift` → `AppDelegate.swift` →
`SettingsStore.swift` → `EventMonitor.swift` → `FocusEngine.swift` →
`FocusActions.swift` → `LiftTests/FocusEngineTests.swift` → `WindowResolver.swift`.
`FocusEngine` projenin en önemli, `WindowResolver` en zor dosyasıdır.

---

## Bir pencereye odak geçmiyorsa

Her uygulama erişilebilirlik bilgisini kendi sağlar ve standarda uyma derecesi
değişir. Sorunu tahmin etmek yerine `WindowResolver`'a neden elediğini sorun:

```sh
log stream --level debug --predicate 'subsystem == "com.aksoyakin.lift"'
```

Akış açıkken imleci sorunlu pencerenin üzerine götürün.

| Satır | Anlamı |
|---|---|
| `elendi: uygun olmayan subrole=...` | Pencerenin alt rolü `AXStandardWindow` veya `AXDialog` değil |
| `elendi: pencere küçültülmüş` | Beklenen davranış, hata değil |
| `pencereye ulaşılamadı: hitRole=...` | İmlecin altındaki öğeden pencereye çıkılamadı |
| *hiç satır yok* | Çözümleme başarılı; sorun odaklama tarafında |

Bu kayıtlar `debug` seviyesindedir; diske yazılmaz, yalnızca yukarıdaki komut
çalışırken üretilir. Sorun bildirirken bu çıktıyı ve imlecin pencerenin neresinde
olduğunu ekleyin.
