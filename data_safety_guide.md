# Data Safety Form Rehberi - Play Console

> 20 Ekim 2026 denetimi: Bu belge gönderilmiş bir Play Console beyanı değildir.
> Yayınlanan uygulama, backend ve tüm SDK veri akışlarıyla doğrulanmalıdır.
> Backend'de ortak öğrenci şifresi ve plain_password saklama tespit edildi;
> HTTPS kullanılması bu güvenlik sorunlarını çözmez. Yayın öncesi giderilmelidir.

Bu rehberi Play Console > Uygulama icerigi > Veri guvenligi bolumunde
adim adim takip et.

---

## 1. Veri Toplama ve Paylasma Genel Bakis

| Soru | Cevap |
|------|-------|
| Uygulamaniz herhangi bir kullanici verisi topluyor mu? | EVET |
| Uygulamaniz herhangi bir kullanici verisini ucuncu taraflarla paylasiyor mu? | Google Cloud hizmet sağlayıcısı, okul içi görsel aktarımı ve okullar arasında görülen kapaklar için Google'ın paylaşım tanımları/istisnaları doğrulanmalı; otomatik HAYIR seçilmemeli |
| Uygulamaniz verileri sifreleme ile mi aktariyor? | EVET (HTTPS) |
| Kullanicilar verilerinin silinmesini talep edebilir mi? | EVET |

---

## 2. Veri Turleri (isaretlenmesi gerekenler)

### Kisisel Bilgiler
- [x] Ad (ogrenci adi, soyadi)
- [x] Kullanici kimlikleri (ogrenci numarasi)

### Iletisim Bilgileri
- [x] E-posta adresi (istege bagli, profil kurulumunda)
- [x] Telefon numarasi (istege bagli, profil kurulumunda)

### Uygulama Etkinligi
- [x] Uygulama icindeki diger kullanici tarafindan olusturulan icerik
  (rezervasyonlar, odunc gecmisi)

### Uygulama Bilgileri ve Performansi
- [ ] Tanılamalar: Flutter varsayılan olarak geliştiriciye crash raporu gönderiyor varsayımı yapılmamalı. Kullanılan SDK'lar (ML Kit dahil) ve sunucu logları ayrıca incelenmeli.

### Cihaz veya Diger Kimlikler
- [ ] Cihaz kimligi - HAYIR, toplanmiyor

### Konum
- [ ] HAYIR - konum verisi toplanmiyor

### Finansal Bilgiler
- [ ] HAYIR - odeme bilgisi toplanmiyor

### Saglik ve Fitness
- [ ] HAYIR

### Mesajlar
- [ ] HAYIR

### Fotograf ve Videolar
- [x] Fotoğraflar: isteğe bağlı kitap kapağı, okul logosu ve duyuru görselleri sunucuya yükleniyor. Kapaklar kamera ile de çekilebiliyor. Barkod görüntüsünün yerel işlenmesi bu yüklemeleri kapsamıyor.

### Ses
- [ ] HAYIR

### Dosyalar ve Belgeler
- [x] Excel öğrenci listesi sunucuya yüklenip işleniyor. Dosya/belge ve içerdiği kişisel veriler, saklama davranışıyla birlikte beyan edilmeli.

### Takvim
- [ ] HAYIR

### Kisiler
- [ ] HAYIR

### Web'de Gezinme Gecmisi
- [ ] HAYIR

---

## 3. Her Veri Turu Icin Detay

### Ad (ogrenci adi, soyadi)
| Soru | Cevap |
|------|-------|
| Toplanma amaci | Uygulama islevselligi |
| Paylasilir mi? | Hayir |
| Zorunlu mu? | Evet |
| Isleme amaci | Kutuphane islemlerinde ogrenci tanimlamasi |

### Kullanici Kimligi (ogrenci numarasi)
| Soru | Cevap |
|------|-------|
| Toplanma amaci | Uygulama islevselligi, Hesap yonetimi |
| Paylasilir mi? | Hayir |
| Zorunlu mu? | Evet |
| Isleme amaci | Ogrenci girisi ve kitap islemleri |

### E-posta Adresi
| Soru | Cevap |
|------|-------|
| Toplanma amaci | Uygulama islevselligi |
| Paylasilir mi? | Hayir |
| Zorunlu mu? | Hayir (istege bagli) |
| Isleme amaci | Profil bilgisi |

### Telefon Numarasi
| Soru | Cevap |
|------|-------|
| Toplanma amaci | Uygulama islevselligi |
| Paylasilir mi? | Hayir |
| Zorunlu mu? | Hayir (istege bagli) |
| Isleme amaci | Profil bilgisi |

### Diger Kullanici Icerigi (rezervasyon, odunc gecmisi)
| Soru | Cevap |
|------|-------|
| Toplanma amaci | Uygulama islevselligi |
| Paylasilir mi? | Hayir |
| Zorunlu mu? | Evet (islem bazli otomatik) |
| Isleme amaci | Kutuphane islem kayitlari |

---

## 4. Cocuklara Yonelik Icerik Beyani

| Soru | Cevap |
|------|-------|
| Hedef kitle 13 yas altini iceriyor mu? | EVET (okul uygulamasi) |
| Families Policy gereksinimlerine uyuyor mu? | Çocuk verileri, SDK uygunluğu ve içerik için ayrıca doğrulanmalı; bu rehber uyumluluk kanıtı değildir |
| Reklam var mi? | HAYIR |
| Ucuncu parti SDK ile veri paylasimi var mi? | SDK sağlayıcılarının güncel veri açıklamalarıyla doğrulanmalı |

Gerçek hedef yaş gruplarını seç. Ortaokul öğrencileri hedef kitlenin içindeyken
13 yaş altını incelemeden kaçınmak için dışlama. İlkokul gerçekten destekleniyorsa
ilgili yaş gruplarını da değerlendir. Çocukları hedefleyen uygulamalar Families
politikasını sağlamalıdır. Önceki rehberin yalnız 13+ seçme önerisi yanlıştı.

---

## 5. Izinler Aciklamasi (Store Listing icin)

| Izin | Aciklama |
|------|----------|
| CAMERA | Kitap barkodlarını taramak ve kullanıcı isteğiyle kitap kapağı fotoğrafı çekmek için |
| INTERNET | Kutuphane verilerini sunucuyla senkronize etmek icin |
| POST_NOTIFICATIONS | Kitap iade hatirlatmalari ve okul duyurulari icin |
| RECEIVE_BOOT_COMPLETED | Zamanlanmis bildirimlerin cihaz yeniden baslatildiktan sonra da calismasi icin |
| WRITE_EXTERNAL_STORAGE | Kitap listesini Excel/PDF olarak indirmek icin (Android 9 ve alti) |

## Yayın öncesi ek doğrulamalar

- Gizlilik metnine kapak, logo, duyuru görseli ve Excel veri akışlarını ekle.
- Gizlilikteki yalnız bcrypt ile şifre saklama iddiası, backend'deki düz metin saklama giderilmeden doğru değildir.
- Hesap silmeyi sentetik test hesabında ilişkili verilerle birlikte doğrula. Yedek saklama süresini ayrıca açıkla.
- İncelemeciye ayrı test okulunda öğrenci ve yetkili hesapları, okul kodu ve kademe bilgisi sağla.
- Gizlilik URL: https://raflylib.online/privacy.html
- Hesap silme URL: https://raflylib.online/hesap-silme.html

Kaynaklar: [Veri Güvenliği](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en),
[Families](https://support.google.com/googleplay/android-developer/answer/9893335?hl=en),
[Kullanıcı verileri](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en),
[Hesap silme](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en).
