# Sınıf Atlatma yayını — 22 Eylül 2026

Backend proje: `library-app-492714`, bölge: `europe-west1`, servis: `library-api`.

Önceki canlı sürüm: `library-api-00126-6d6`.
Yeni sürüm: `library-api-sinif-20260922`.
Yeni sürüme trafik aktarımından önce `/health` veritabanı kontrolü ve yetkisiz Sınıf Atlatma isteğinin 401 ile reddedilmesi doğrulandı.

Kaynak, canlı sürümün Cloud Build arşivi üzerine yalnızca Sınıf Atlatma değişiklikleri uygulanarak hazırlandı. Yerel diğer çalışmalar yayına eklenmedi. Veritabanı bağlantısı ve servis hesabı korundu. Üretimde JWT_SECRET tanımlandı; kullanıcıların yeniden giriş yapması gerekir. Anahtar bu dosyada veya GitHub'da bulunmaz.

Web deposu: `EmirSaki/rafly`, yayın commit'i: `f731321a0d27a1d098498c3d7707df8e0af4efe7`.
GitHub Pages çalışması: https://github.com/EmirSaki/rafly/actions/runs/35720700086

## Geri dönüş

Backend trafiğini önceki sürüme yönlendirme:

`gcloud run services update-traffic library-api --region=europe-west1 --project=library-app-492714 --to-revisions=library-api-00126-6d6=100`

Web panelini geri almak için `f731321a0d27a1d098498c3d7707df8e0af4efe7` commit'i yeni bir revert commit'iyle geri alınır ve main dalına gönderilir. Diğer yerel dosya değişiklikleri korunmalıdır.

Bu komutlar yalnızca uygulama sürümünü geri alır; kullanıcıların sonradan yaptığı öğrenci silmelerini geri getirmez. Veri geri dönüşü için veritabanı yedeği gerekir.

10 otomatik test geçti. Canlı öğrenci verileri üzerinde sınıf atlatma veya silme işlemi çalıştırılmadı; gerçek verilerle uçtan uca silme testi yapılmadı.

## Excel özet satırı düzeltmesi

22 Eylül 2026: `library-api-xlsfix-20260922` yayımlandı ve canlı trafiğin %100'ü bu sürüme aktarıldı. Kaynak, `library-api-sinif-20260922` arşivinden hazırlandı; yalnızca `student.controller.js` içindeki Excel özet satırı tanıma ve gerçek Excel satır numarası düzeltmesi eklendi.

Kullanıcının 5 A.XLS dosyası yerelde 27 öğrenciyle başarıyla okundu. XLS/XLSX regresyonları dahil 12 test geçti. Yeni sürümün ve ana canlı adresin `/health` kontrolleri veritabanı bağlantısını doğruladı; yeni sürümde yetkisiz sınıf atlatma isteği 401 döndü. Canlı öğrenci kayıtlarında sınıf atlatma işlemi çalıştırılmadı.

Bu düzeltmeyi geri almak için:

`gcloud run services update-traffic library-api --region=europe-west1 --project=library-app-492714 --to-revisions=library-api-sinif-20260922=100`

## Tüm sınıf listelerinin Excel düzenleri

`library-api-xlsall-20260922` yayımlandı ve trafiğin %100'ü aktarıldı. XLS birleştirilmiş hücreleri başlık sütununa göre çözülüyor; lise/hazırlık özetleri sütun konumundan bağımsız tanınıyor. XLSX boş birleşik hücre kontrolü de düzeltildi. Önceki yayın kaynağında yalnızca `student.controller.js` değiştirildi.

Paylaşılan 26 dosyanın tamamı strict kontrolden geçti. 554 öğrencinin sınıf bazında sayıları dosya toplamlarıyla, numara ve ad-soyadları bağımsız satır okumasıyla eşleşti. Birleşik liste plan doğrulaması geçti. XLS/XLSX düzen ve eksik bilgi testleri dahil 16 test başarılı. Yeni sürüm ve ana adres sağlık/veritabanı kontrolleri başarılı; yetkisiz önizleme isteği 401 döndü. Canlı öğrenci verileri üzerinde sınıf atlatma çalıştırılmadı.

Bu sürümün geri dönüşü: `gcloud run services update-traffic library-api --region=europe-west1 --project=library-app-492714 --to-revisions=library-api-xlsfix-20260922=100`.
