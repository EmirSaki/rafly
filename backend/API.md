# Rafly API Sözleşmesi

Frontend (Flutter) ve backend arasındaki endpoint listesi. Yeni endpoint eklenmeden ya da bir
endpoint'in istek/yanıt şekli değişmeden önce bu dosya güncellenir.

## Ortamlar

| Ortam | Adres |
|---|---|
| Canlı (Cloud Run) | `https://library-api-346058361420.europe-west1.run.app` |
| Yerel | `http://localhost:8080` (Android emülatörden: `http://10.0.2.2:8080`) |

Flutter tarafında adres `API_BASE_URL` ile seçilir:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

## Kimlik doğrulama

- Öğrenci uçları (`/api/students/profile`, `/api/students/reservations`) öğrenci token'ı ister (`authStudent`).
- Diğer uçların çoğu okul kodu (`:schoolCode` / `:schoolId`) ile çalışır.

## Endpoint listesi

Gövde ve yanıt şekilleri değiştiğinde ilgili satırın altına örnek JSON eklenmelidir.

### Kitaplar (`/api/books`)

| Metod | Yol | Açıklama |
|---|---|---|
| GET | `/` | Tüm kitaplar |
| GET | `/isbn/:isbn` | ISBN ile kitap |
| GET | `/:id` | Kitap detayı |
| POST | `/` | Kitap oluştur |
| PATCH | `/:id` | Kitap güncelle |
| DELETE | `/:id` | Kitap sil |
| POST | `/isbn/:isbn/cover` | Kapak yükle (`cover` alanı, multipart) |
| DELETE | `/isbn/:isbn/cover` | Kapak sil |

### Okullar (`/api/schools`)

| Metod | Yol | Açıklama |
|---|---|---|
| POST | `/` | Okul oluştur |
| GET | `/` | Okul listesi |
| POST | `/access` | Okul erişimi (kod ile giriş) |
| GET | `/:schoolCode/books` | Okul envanteri (sayfalı, arama) |
| GET | `/:schoolCode/books/export` | Envanter dışa aktarma |
| GET | `/:schoolCode/books/isbn/:isbn` | Okul içinde ISBN ile kitap |
| GET | `/:schoolCode/books/:bookId` | Okul kitap detayı |
| POST | `/:schoolCode/books` | Okula kitap ekle |
| PATCH | `/:schoolCode/books/:bookId` | Adet güncelle |
| DELETE | `/:schoolCode/books/:bookId` | Envanterden sil |
| GET | `/:schoolCode/logo` | Okul logosu |
| POST | `/:schoolCode/logo` | Logo yükle |
| DELETE | `/:schoolCode/logo` | Logo sil |
| GET | `/:schoolCode/report-cards` | Karne raporları |

### Öğrenciler (`/api/students`)

| Metod | Yol | Açıklama |
|---|---|---|
| GET | `/` | Öğrenci listesi |
| POST | `/` | Tekli öğrenci ekle |
| DELETE | `/` | Öğrenci sil |
| POST | `/import` | Excel ile toplu içe aktarma |
| POST | `/register` | Öğrenci kaydı |
| POST | `/login` | Öğrenci girişi |
| POST | `/bulk-passwords` | Toplu şifre atama |
| GET | `/profile` | Profilim (öğrenci) |
| PATCH | `/profile` | Profil güncelle (öğrenci) |
| DELETE | `/profile` | Hesabımı sil (öğrenci) |
| POST | `/reservations` | Rezervasyon oluştur (öğrenci) |
| GET | `/reservations` | Rezervasyonlarım (öğrenci) |
| POST | `/promotion/:phase` | Sınıf geçiş işlemi (dosya yükleme) |

### Rezervasyonlar (`/api/reservations`)

| Metod | Yol | Açıklama |
|---|---|---|
| GET | `/` | Rezervasyon listesi |
| GET | `/:id` | Rezervasyon detayı |
| POST | `/` | Rezervasyon oluştur |
| POST | `/loan-by-student` | Öğrenciye ödünç ver |
| PATCH | `/:id/loan` | Ödünç onayla |
| PATCH | `/:id/reject` | Reddet |
| PATCH | `/:id/return` | İade al |
| DELETE | `/:id` | Rezervasyon sil |

### Kullanıcılar (`/api/users`)

| Metod | Yol | Açıklama |
|---|---|---|
| POST | `/login` | Personel girişi |
| GET | `/` | Kullanıcı listesi |
| GET | `/:id` | Kullanıcı detayı |
| POST | `/` | Kullanıcı oluştur |
| PATCH | `/:id` | Kullanıcı güncelle |
| DELETE | `/:id` | Kullanıcı sil |

### Yönetim (`/api/admin`)

| Metod | Yol | Açıklama |
|---|---|---|
| POST | `/schools` | Okul oluştur |
| GET | `/schools` | Okul listesi |
| POST | `/schools/:schoolId/teachers` | Öğretmen ekle |
| GET | `/schools/:schoolId/teachers` | Öğretmen listesi |
| DELETE | `/schools/:schoolId/teachers/:teacherId` | Öğretmen sil |

### Duyurular (`/api/announcements`)

| Metod | Yol | Açıklama |
|---|---|---|
| GET | `/` | Duyuru listesi |
| GET | `/:id/images` | Duyuru görselleri |
| POST | `/` | Duyuru oluştur (görsel, en fazla 10) |
| DELETE | `/:id` | Duyuru sil |

## Değişiklik kuralı

1. Yeni ya da değişen endpoint önce bu dosyada tanımlanır.
2. Backend tarafı `backend/` içinde yazılır ve test edilir.
3. Flutter tarafı aynı PR'da ya da hemen ardından güncellenir.
