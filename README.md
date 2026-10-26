# Rafly

Okul kütüphane yönetim sistemi. Üç modülden oluşur:

| Modül | Klasör | Açıklama |
|---|---|---|
| Frontend (mobil) | `/` (`lib/`, `android/`, `ios/`) | Flutter uygulaması (`com.rafly.app`) |
| Backend | `backend/` | Node.js / Express + PostgreSQL API (Cloud Run) |
| Web | `docs/`, `panel-src/` | raflylib.online landing sayfası, öğrenci paneli (`docs/ogrenci`) ve personel paneli kaynağı (`panel-src`, çıktı `docs/panel`) |

## Backend

```bash
cd backend
npm install
npm start
```

Ortam değişkenleri `backend/.env` içinde tutulur (git'e eklenmez).
Deploy: `cd backend && gcloud run deploy library-api --source . --region europe-west1`

## Frontend

```bash
flutter pub get
flutter run
```

## Web

GitHub Pages `docs/` klasöründen yayınlanır. Personel paneli değişikliği `panel-src/` içinde yapılır,
`npm run build` çıktısı `docs/panel/` altına kopyalanır.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
