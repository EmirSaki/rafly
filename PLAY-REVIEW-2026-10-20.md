# Rafly Google Play güncelleme incelemesi

Güncelleme hazırlığı: Kullanıcının üretim ekranında mevcut sürüm 4 (1.0.0) görüldükten sonra proje ve giriş ekranı sürümü 1.0.1+5 olarak artırıldı. Aşağıdaki sürüm 4 bilgileri ilk denetim anını anlatır. Sürüm 5 başka bir kanalda kullanılmışsa daha yüksek kodla yeniden derlenmelidir. Güvenlik/beyan bulguları bu sürüm artırımıyla çözülmüş değildir.

Tarih: 20 Ekim 2026. Paket: `com.rafly.app`. Yerel sürüm: `1.0.0+4`.

## Sonuç

Android yayın derlemesi üretilebiliyor; ancak aşağıdaki güvenlik ve beyan sorunları giderilmeden üretim incelemesine gönderilmesini önermiyorum. Bu bir Google onay garantisi değildir. Play Console oturumu, önceki yüklemelerin en yüksek sürüm kodu ve incelemeci hesapları görülmedi. Kullanıcı önceki sürümünün reddedilmediğini belirtti.

## Yayın öncesi önemli bulgular

1. **Ortak öğrenci şifresi:** Backend `src/controllers/student.controller.js`, `loginStudent`, öğrenciye özel hash yerine ortak `STUDENT_PASSWORD` karşılaştırıyor. Profilde şifre değiştirme sunulsa da girişte o hash doğrulanmıyor. Ayrı hesap doğrulaması ve güvenli ilk giriş/parola yenileme akışı gerekli. Bu akışı inceleme sırasında habersiz değiştirmek mevcut öğrencilerin erişimini etkileyebileceğinden backend değiştirilmedi.
2. **Düz metin şifre:** Aynı controller kayıt, profil güncelleme ve toplu şifre işlemlerinde `plain_password` yazıyor. `docs/privacy.html` yalnız bcrypt ile saklandığını söylüyor. Düz metin yazımları, bunları okuyan ekranlar ve eski değerler birlikte ele alınmalı; sadece gizlilik metnini değiştirmek güvenlik çözümü değildir.
3. **Yetkilendirme:** Yerel backend `src/routes/student.routes.js` yönetim/listeme/silme uçları, `src/routes/user.routes.js` ve duyuru yazma/silme uçlarında yetkilendirme middleware'i görünmüyor. `src/app.js` öncesinde genel bir koruma yok. Android yetkili girişi token saklamıyor; `lib/services/api_service.dart` yönetim çağrıları için Bearer göndermiyor. Okul/rol sınırları her istekte sunucuda doğrulanmalı. Canlıda gerçek öğrenci verisi okunarak veya değiştirilerek açık istismarı denenmedi; bulgu kaynak kod incelemesidir.
4. **Eksik veri beyanı:** Uygulama kitap kapağı çekiyor/yüklüyor, okul logosu ve duyuru görselleri yüklüyor, Excel öğrenci listesi gönderiyor. Gizlilik metni kamerayı yalnız barkod olarak anlatıyor; eski Veri Güvenliği rehberi fotoğraf ve belgeleri dışlıyordu. Rehber düzeltildi. Gizlilik web sayfası henüz değiştirilmedi/yayımlanmadı; gerçek veri akışları ve saklama süreleriyle güncellenmeli.
5. **Çocuk hedef kitle:** Ortaokul öğrencilerini hedefleyen uygulamada 13 yaş altını gizleyen beyan kullanılmamalı. Rehberdeki yanlış öneri kaldırıldı. Families, SDK veri işleme uygunluğu ve okul/veli süreçleri gerçek kullanıma göre doğrulanmalı.
6. **Hesap silme:** Öğrenci profilinde düğme, backend DELETE endpoint'i ve dış silme sayfası var. Ancak silme, aktif ödünçleri otomatik iade ediyor; fiziksel kitap iadesiyle aynı işlem değildir. İlişkili rezervasyonların/verilerin silinmesi, anonimleştirme ve yedek saklama süresi sentetik hesapta doğrulanmalı. Gerçek hesap silinmedi.
7. **Eski Android dışa aktarma:** Android 9 ve altında native kod Downloads'a yazıyor; manifestte izin var ancak Dart akışında çalışma zamanı depolama izni isteği görülmedi. API 24–28 cihazda Excel/PDF dışa aktarma ayrıca denenmeli.
8. **İncelemeci erişimi:** Ayrı test okulunda yetkili ve öğrenci hesapları, kademe, okul kodu ve giriş adımları Play Console Uygulama erişimi alanına girilmeli. Hesap silme testi için ayrı sentetik hesap sağlanmalı. Gerçek öğrenci hesabı verilmemeli.

## Yapılan yerel değişiklikler

- Kullanıcının isteğiyle `lib/pages/add_book_page.dart` içindeki “Raf Olarak Ekle” kartı, ona ait gezinme kodu ve kullanılmayan import kaldırıldı. `shelf_batch_scan_page.dart`, `shelf_verification_page.dart` ve işlevleri korunuyor. Başka ekrandan bu akışa giriş referansı bulunmadı. Bu yalnız arayüz erişimini kaldırır; sunucu tarafında özellik yetkilendirmesi değildir.
- Giriş türü ekranına Gizlilik Politikası ve Hesap Silme bağlantıları eklendi; tarayıcı açılamazsa hata gösteriliyor.
- Açılış testindeki eksik SharedPreferences mock ayarı düzeltildi; bağlantıların görünürlüğü kontrol edildi.
- `data_safety_guide.md` yanlış fotoğraf/belge, Flutter crash ve yaş grubu önerileri açısından düzeltildi. Formun veya web sitesinin yayımlandığı anlamına gelmez.
- Başlangıçta mevcut `.claude/launch.json` değişikliğine dokunulmadı. Backend ve canlı servis değiştirilmedi.

## Doğrulama

- Flutter 3.41.1, Dart 3.11.0; AGP 8.11.1, NDK 28.2.13676358.
- Release manifest: minSdk 24, targetSdk 36. API 36 güncel Play hedefini karşılıyor.
- READ_MEDIA_IMAGES / VIDEO / AUDIO izinleri yok; READ_EXTERNAL_STORAGE en fazla API 32, WRITE_EXTERNAL_STORAGE en fazla API 28. Kamera donanımı zorunlu değil.
- 4 Flutter testi geçti. Değiştirilen Dart dosyalarının analizinde sorun yok. Tam proje analizinde önceden var olan 22 bilgi düzeyinde lint var; derleyici hatası/uyarı yok. Bazı finally blokları return içeriyor; ayrıca temizlenebilir.
- Flutter paket işlemleri Windows/Linux varsayılan plugin metadata uyarıları verdi; Android release derlemesini engellemedi. Kilit dosyası değişmedi.
- Release AAB başarıyla oluşturuldu; raf düğmesi kaldırıldıktan sonra yeniden derlendi.
- İncelenen AAB içindeki arm64-v8a/x86_64 toplam 14 native kütüphanenin ELF LOAD segment hizalamaları en az 16 KB. Mevcut APK için zipalign 16 KB kontrolü geçti. Bu, gerçek 16 KB cihaz testinin yerine geçmez.
- Mevcut APK imzası doğrulandı. SHA-256 sertifika parmak izi: `28fcbe4ef098f9ec9c24ef5e9a984ffe210d0f80c38bc5238a501b101a9d1060`. Console'daki upload certificate ile ayrıca karşılaştırılmalı.
- `https://raflylib.online/privacy.html`, `https://raflylib.online/hesap-silme.html` ve Android'in kullandığı API `/health` HTTP 200 döndü.
- Bağlı Android cihazı ve kurulu AVD bulunmadı. Kamera izin reddi, gerçek tarama, fotoğraf seçimi, hesap silme, Android 16 ekran kenarları, çevrimdışı kullanım ve eski sürümden yükseltme uçtan uca test edilmedi.

## Play Console'a yükleme sırası

1. Yukarıdaki güvenlik/beyan engellerini gider; gizlilik metnini gerçek davranışla eşleştirip webde yayımla.
2. Play Console → App bundle explorer içindeki **tüm kanallarda kullanılmış en yüksek versionCode** değerini öğren. Yerelde 4 var; yalnız Console maksimumu da 4 ise sonraki değer 5 olabilir. Aynı paket adı ve önceki upload key kullanılmalı.
3. Örnek: maksimum 4 doğrulanırsa `flutter build appbundle --release --build-name=1.0.1 --build-number=5`. Şu an üretilen `build/app/outputs/bundle/release/app-release.aab`, sürüm 4 ile derleme doğrulama çıktısıdır; doğrudan güncelleme diye yüklenmemeli.
4. Önce Internal testing kanalına AAB yükle. Play App Signing/upload sertifikası, hedef API ve native uyumluluk uyarılarını kontrol et.
5. Aynı mağaza sürümünün üzerine güncelleme kurarak oturumların/verilerin korunduğunu test et. Yetkili/öğrenci girişleri, kamera reddi ve tekrar açılması, barkod/manual ekleme, rezervasyon/iade, fotoğraf/Excel ve sentetik hesap silmeyi dene. 16 KB ve API 24–28 cihazları dahil et.
6. App content: Veri Güvenliği, gerçek hedef yaş grupları/Families, reklam beyanı, IARC içerik derecelendirmesi, uygulama erişimi ve hesap silme URL'sini güncelle. Önceki onay yeni sürümün beyanlarını otomatik doğrulamaz.
7. Store listing görselleri ve açıklaması yayınlanan Android özelliklerini göstermeli. Bu sürümde gizlenen raf toplu ekleme ekranını mağaza ekran görüntülerinden de çıkar.
8. Pre-launch report çökme/ANR, erişilebilirlik ve güvenlik sonuçlarını incele. Başarılı testlerden sonra üretim sürümü ve doğru değişiklik notuyla incelemeye gönder; aşamalı dağıtım kullan.

## Resmî kaynaklar (20 Ekim 2026 kontrolü)

- [Hedef API: güncellemeler için 31 Ağustos 2026'dan itibaren API 36](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en)
- [16 KB desteği: güncel sayfada güncelleme yayın engeli tarihi 1 Şubat 2027](https://developer.android.com/guide/practices/page-sizes)
- [Veri Güvenliği](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en)
- [Kullanıcı verileri ve gizlilik](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en)
- [Families ve doğru hedef kitle](https://support.google.com/googleplay/android-developer/answer/9893335?hl=en)
- [Hesap silme](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en)
