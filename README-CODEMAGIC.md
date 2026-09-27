# Rafly — iOS'u Mac'siz build alma (Codemagic)

Windows'tan, Mac olmadan iOS uygulamasini App Store'a yuklemek icin adimlar.
Kod tarafi hazir; asagidaki tek seferlik kurulumu yapinca her build tek tikla alinir.

## Ön koşullar (tamam olanlar ✅)
- Apple Developer hesabi (aktif)
- App Store Connect'te uygulama kaydi: **Rafly Kütüphane** (bundle: `com.rafly.app`)
- GitHub repo: `EmirSaki/rafly` (kod push'landi)
- Team ID: `7562QS2QM7`

---

## 1. App Store Connect API anahtari oluştur
Bu anahtar, Codemagic'in senin adina imzalayip yukleme yapmasini saglar.

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Users and Access** → sekmelerden **Integrations** (veya **Keys**)
2. **App Store Connect API** → **+** (Generate API Key / Team Keys)
3. İsim: `Codemagic`, Erişim (Access): **App Manager**
4. **Generate** → oluşan anahtarda şunları not/indir:
   - **Issuer ID** (üstte, uzun bir kod)
   - **Key ID**
   - **`.p8` dosyasını indir** (SADECE BİR KEZ indirilebilir — kaydet!)

---

## 2. Codemagic hesabı + repo bağla
1. [codemagic.io](https://codemagic.io) → **Sign up with GitHub** → `EmirSaki/rafly` reposuna erişim ver
2. Panelde uygulamayı ekle: **Add application** → GitHub → `rafly` → **Flutter App**
3. Codemagic `codemagic.yaml` dosyasını repoda otomatik bulur.

---

## 3. API anahtarını Codemagic'e tanıt
1. Codemagic → sağ üst **Teams** (veya kullanıcı) → **Integrations** → **App Store Connect** → **Manage keys** → **Add key**
2. Doldur:
   - **Name:** `RaflyAppStoreKey`  ← `codemagic.yaml`'daki `app_store_connect:` ile **BİREBİR AYNI** olmalı
   - **Issuer ID:** (1. adımdan)
   - **Key ID:** (1. adımdan)
   - **API key (.p8):** indirdiğin dosyayı yükle
3. Kaydet.

> Not: İsmi farklı koyarsan, `codemagic.yaml` içindeki `RaflyAppStoreKey` satırını o isimle değiştir.

---

## 4. İmzalama (otomatik)
`codemagic.yaml` içinde `ios_signing.distribution_type: app_store` var. Codemagic,
1. adımdaki API anahtarıyla dağıtım sertifikasını ve provisioning profilini **otomatik**
oluşturur/yönetir. Elle sertifika uğraşı YOK.

---

## 5. Build başlat
1. Codemagic → uygulama → **Start new build**
2. Workflow: **Rafly iOS Release**, branch: **main** → **Start build**
3. ~10-15 dk sonra:
   - `.ipa` üretilir,
   - otomatik imzalanır,
   - **TestFlight'a yüklenir**.

---

## 6. Sonrası (App Store Connect'te)
1. **TestFlight** sekmesinde build görünür (birkaç dk "processing").
2. Kendi telefonunda (arkadaşının iPhone'u) TestFlight ile test et.
3. Hazırsan **Distribution** → metadata'yı doldur (ekran görüntüleri, açıklama, gizlilik anketi, demo giriş bilgisi) → **Add for Review**.

---

## Güncelleme akışı (bundan sonra)
1. Kodu değiştir → `pubspec.yaml`'da build numarasını artır (örn. `1.0.0+5`)
2. `git push origin main`
3. Codemagic → Start new build → TestFlight'a düşer → incelemeye gönder.

## Android'i de eklemek istersen
Ayni `codemagic.yaml`'a bir `android-release` workflow eklenebilir; Android keystore'unu
Codemagic'e yukleyip Play'e otomatik yukleme kurulur. Simdilik iOS'a odaklandik.
