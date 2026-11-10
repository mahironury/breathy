# Breathy

Mac'ine nefes aldıran, menü çubuğunda yaşayan hafif bir disk temizleyici.

- Menü çubuğunda boş alanı gösterir; panelde doluluk yüzdesi, tek dokunuşla Çöp'ü boşaltma ve tarama.
- Önbellekleri, logları, eski `node_modules` ve derleme çıktılarını, eski kurulum dosyalarını, büyük ve çift dosyaları, kaldırılmış uygulamaların artıklarını bulur.
- Büyük gizli klasörleri (`~/.gemini`, `~/.colima`…) gösterir; aylardır dokunulmamış eski kopyaları ayrıca belirtir.
- Geliştirici araçlarının (VS Code, Cursor, Antigravity, Windsurf) yeniden oluşan önbelleklerini ve eski ekran kayıtlarını bulur. Sohbet geçmişine, planlara ve dosyaların yerel geçmişine dokunmaz.
- Fotoğraf/video için Lightroom önizlemelerini ve Final Cut Pro render dosyalarını, iPhone/iPad için eski güncelleme dosyalarını bulur.
- Geçen taramadan beri en çok büyüyen klasörleri gösterir.
- Türe göre temizler: kendiliğinden yeniden oluşanlar (önbellek, log, `node_modules`) doğrudan silinir; kişisel dosyalar Çöp'e gider. Panelden tek tıkla sadece güvenli olanlar temizlenir.
- Arka planda tarama yapmaz. Boş alan 10 GB'ın altına inince tek bir bildirim gönderir.

Gereken: macOS 14 (Sonoma) ya da daha yenisi. Apple Silicon ve Intel.

## Kurulum

[Releases](../../releases/latest) sayfasından `Breathy-<sürüm>.zip` dosyasını indir, `Breathy.app`'i Uygulamalar klasörüne sürükle ve [Kurulum.txt](scripts/Kurulum.txt) adımlarını izle. Uygulama Apple onaylı olmadığı için ilk açılışta Sistem Ayarları → Gizlilik ve Güvenlik → **Yine de Aç** gerekir. Tarama için Tam Disk Erişimi izni istenir.

**Güncellemeler:** Breathy günde bir kez bu depodaki son sürüme bakar; yeni sürüm varsa panelde **Güncelle** düğmesi çıkar. İndirilen uygulama aynı sertifikayla imzalı değilse kurulmaz.

## Kaynaktan derleme

Xcode gerekmez; Command Line Tools (Swift 6) yeterli.

```bash
./scripts/setup-signing.sh   # bir kez: yerel imza sertifikası
./build.sh                   # derle, ~/Applications'a kur ve başlat
```

Kendi derlediğin kopya kendi sertifikanla imzalanır; bu depodaki sürümlerle güncellenmez.

## Güvenlik ilkeleri

- Silme kararını her zaman kullanıcı verir; otomatik ya da zamanlanmış silme yok.
- Anahtar zinciri, Mail, Mesajlar, Fotoğraflar arşivi, iCloud Drive, SSH anahtarları ve tercihler gibi yerlere hiçbir koşulda dokunulmaz.
- Açık bir uygulamanın verisi silinmez; çift dosyalarda her grupta en az bir kopya kalır.
- Her öğe silinmeden hemen önce yeniden denetlenir.
- Ağ isteği yalnızca güncelleme denetimi için GitHub'a yapılır.
