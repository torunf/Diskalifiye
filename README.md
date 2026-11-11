# Diskalifiye

Mac'inde dosyaların nerede yer kapladığını gösteren ve nelerin temizlenebileceğini öneren yerel bir macOS uygulaması (SwiftUI).

## Özellikler

- **Disk Haritası** — klasörleri iç içe kutularla gösteren treemap; tıklayarak yakınlaş, sağ tıkla Finder'da göster ya da çöpe taşı. Yanında boyuta göre sıralı liste ve dosya türü dağılımı.
- **Temizlik Önerileri** — uygulama önbellekleri, günlükler, Xcode derleme verileri, paket yöneticisi önbellekleri, proje artıkları (`node_modules`, `Pods`, `build`, `target`, `.venv`…), Xcode arşivleri ve simülatörler, iPhone/iPad yedekleri, eski indirilenler. Her kategori "Güvenli" ya da "Dikkat" olarak etiketlenir.
- **Büyük Dosyalar** — en büyük dosyalar; türe ve ada göre filtreleme, çoklu seçim.
- **Kopya Dosyalar** — 1 MB üstü dosyaları SHA-256 içerik özetiyle karşılaştırır.

Hiçbir şey doğrudan silinmez: öğeler onay alındıktan sonra Çöp Kutusu'na taşınır.

## Kurulum

1. [Son sürümü indir](https://github.com/torunf/Diskalifiye/releases/latest) (`Diskalifiye-x.y.dmg`).
2. DMG'yi aç ve Diskalifiye'yi Uygulamalar klasörüne sürükle.
3. Uygulama Apple tarafından imzalanmadığı için ilk açılışta macOS engelleyebilir. **Sistem Ayarları → Gizlilik ve Güvenlik** bölümünden **Yine de Aç**'a bas ya da Terminal'de şunu çalıştır:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Diskalifiye.app
   ```

Apple Silicon ve Intel Mac'lerde çalışır (macOS 14+).

## Kaynaktan derleme

macOS 14+ ve Xcode (Swift 5.9+) gerekir.

```bash
./build.sh
open build/Diskalifiye.app
```

Daha eksiksiz sonuç için uygulamaya **Sistem Ayarları → Gizlilik ve Güvenlik → Tam Disk Erişimi** izni verebilirsin.

## Notlar

- 256 KB altındaki dosya ve klasörler haritada tek tek değil, "Küçük öğeler" bloğu olarak gösterilir.
- `main` dalına gönderilen her kod değişikliği GitHub Actions ile otomatik olarak yeni bir sürüm (v1.0, v1.1, …) olarak yayınlanır.

## Lisans

[MIT](LICENSE)
