# Öğrenci paneli yayın notu — 29 Ekim 2026

- Kaynak: EmirSaki/rafly ana dalı, PR #1; GitHub Pages dağıtımı başarılı. Canlı adres: https://raflylib.online/ogrenci/
- Yeni öğrenci tasarımı, gerçek API ve kitap listesi canlı sitede doğrulandı (8.099 kitap).
- backend/src/controllers/student.controller.js içindeki rezervasyon geçmişi sorgusuna cover_url eklendi ve GitHub ana dalına alındı. Cloud Run servisine bu backend değişikliği henüz dağıtılmadı.
- Cloud Run konsolu, kullanılan Google hesabında zorunlu iki aşamalı doğrulama nedeniyle erişimi engelliyor. Yetkili hesapta iki aşamalı doğrulama tamamlandıktan sonra library-app-492714 projesindeki europe-west1/library-api servisine ana daldaki backend kodu dağıtılmalı; ardından geçmişteki gerçek kapaklar test edilmeli.
- Yerel Node testleri: 11 başarılı; git diff --check başarılı. Yayından sonra canlı sayfada tema ve gerçek kitap listesi kontrol edildi.
