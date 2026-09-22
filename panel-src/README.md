# Rafly personel paneli

Mevcut LibraryDesktop React kaynaklarının GitHub Pages paneli için alınan kaynak kopyasıdır. Bundan sonraki web paneli değişiklikleri bu klasörde geliştirilebilir.

## Derleme

`npm ci` ardından `npm run build`. `dist` içeriği reponun `docs/panel` klasörüne kopyalanır. Vite taban yolu `/panel/` olarak ayarlıdır.

## Sınıf Atlatma / Kural

- Öğrenci Ekle yanındaki Sınıf Atlatma ekranında kapsam seçilir ve kapsamın tüm sınıf dosyaları birlikte yüklenir.
- Mevcut Excel Yükle ile aynı, tek çalışma sayfalı `.xls` / `.xlsx` formatı kullanılır. PDF desteği henüz yoktur.
- Numara ve tam ad, Türkçe büyük/küçük harf ve gereksiz boşluklar normalleştirilerek eşleştirilir. Numaranın başındaki sıfırlar korunur. Sınıf eşleştirme anahtarına dahil değildir.
- Eşleşen öğrencinin kimliği, hesabı, parolası, ödünçleri ve geçmişi korunur; sınıf, şube kodu ve sınıftan türeyen kademe güncellenir.
- Yeni öğrenciler listeye eklenir. Kapsam içinde yeni listede olmayanlar (8 ve 12 dahil) silme önizlemesine girer. Yeni listede eşleşen 8/12 öğrencileri silinmez.
- Mükerrer kimlikler, aynı sınıfta numara çakışmaları, eksik kayıtlar ve kademe geçişinin tek kademe kapsamında yapılması engellenir.
- Önizleme sonrasında silinecekler gerçek `.xlsx` dosyası olarak indirilir; kullanıcı dosyayı kaydettiğini ve silme listesini onaylar. Tarayıcının dosyayı diske gerçekten kaydettiği otomatik olarak doğrulanamaz.
- Silinecek öğrencide aktif ödünç veya rezervasyon varsa işlem durur; otomatik iade yapılmaz.
- Liste değişirse veya 30 dakika geçerse yeni önizleme ve yedek gerekir. Kaydetme tek veritabanı işlemi içinde gerçekleşir.

## Yayınlama bağımlılığı

Önce library-api backend'in `POST /api/students/promotion/:phase` uç noktaları (`preview`, `report`, `commit`) yayınlanmalıdır. Sonra web paneli yayınlanır. Yeni uç noktalar aynı okula ait teacher/admin JWT gerektirir.

Backend testleri: `node --test test/studentPromotion.test.js test/studentPromotionController.test.js`.
Testler eşleştirme, Excel okuma, yetkilendirme ve taklit veritabanı ile işlem akışını doğrular. Gerçek PostgreSQL üzerinde uçtan uca doğrulama ayrıca gerekir.
