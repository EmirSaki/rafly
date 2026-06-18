# Data Safety Form Rehberi - Play Console

Bu rehberi Play Console > Uygulama icerigi > Veri guvenligi bolumunde
adim adim takip et.

---

## 1. Veri Toplama ve Paylasma Genel Bakis

| Soru | Cevap |
|------|-------|
| Uygulamaniz herhangi bir kullanici verisi topluyor mu? | EVET |
| Uygulamaniz herhangi bir kullanici verisini ucuncu taraflarla paylasiyor mu? | HAYIR |
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
- [x] Tanilamalar (crash log varsa - Flutter default)

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
- [ ] HAYIR (kamera sadece barkod tarama icin, goruntu kaydedilmiyor)

### Ses
- [ ] HAYIR

### Dosyalar ve Belgeler
- [ ] HAYIR

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
| Families Policy gereksinimlerine uyuyor mu? | EVET |
| Reklam var mi? | HAYIR |
| Ucuncu parti SDK ile veri paylasimi var mi? | HAYIR |

NOT: "Hedef kitle" bolumunde "13 yas alti" secersen Google daha siki
inceleme yapar. "Herkes" secip aciklamada "okul ortaminda kullanilmak
uzere tasarlanmistir" yazmak daha guvenli bir stratejidir.
Onerilen hedef kitle secimi: "13-17 yas" ve "18 yas ustu"

---

## 5. Izinler Aciklamasi (Store Listing icin)

| Izin | Aciklama |
|------|----------|
| CAMERA | Kitap barkodlarini (ISBN) taramak icin kullanilir |
| INTERNET | Kutuphane verilerini sunucuyla senkronize etmek icin |
| POST_NOTIFICATIONS | Kitap iade hatirlatmalari ve okul duyurulari icin |
| RECEIVE_BOOT_COMPLETED | Zamanlanmis bildirimlerin cihaz yeniden baslatildiktan sonra da calismasi icin |
| WRITE_EXTERNAL_STORAGE | Kitap listesini Excel/PDF olarak indirmek icin (Android 9 ve alti) |
