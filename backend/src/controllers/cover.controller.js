const crypto = require("crypto");
const { Storage } = require("@google-cloud/storage");
const pool = require("../config/db");
const {
  deleteIsbnCache,
  invalidateSchoolBooksCache,
} = require("../../services/cache.service");

const BUCKET_NAME = process.env.COVER_BUCKET || "library-app-492714-kapaklar";

// Kapaklar tarayıcı/uygulama tarafında uzun süre önbelleklensin: aynı görseli
// tekrar tekrar indirmek hem yavaş hem de çıkış (egress) maliyeti demek.
// Dosya adı içeriğin özetini taşıdığı için içerik değişince URL de değişir,
// yani uzun önbellek güvenli.
const CACHE_CONTROL = "public, max-age=31536000, immutable";

const ALLOWED_MIME = {
  "image/jpeg": "jpg",
  "image/jpg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};

// İçerik tipini dosyanın ilk baytlarından (magic bytes) tespit eder.
// Flutter MultipartFile.fromBytes varsayılan olarak "application/octet-stream"
// gönderdiği için istemcinin bildirdiği mime'a güvenmeyip içeriğe bakarız.
function sniffImageType(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < 12) return null;
  // JPEG: FF D8 FF
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) {
    return { mime: "image/jpeg", ext: "jpg" };
  }
  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47) {
    return { mime: "image/png", ext: "png" };
  }
  // WEBP: "RIFF" .... "WEBP"
  if (
    buf[0] === 0x52 && buf[1] === 0x49 && buf[2] === 0x46 && buf[3] === 0x46 &&
    buf[8] === 0x57 && buf[9] === 0x45 && buf[10] === 0x42 && buf[11] === 0x50
  ) {
    return { mime: "image/webp", ext: "webp" };
  }
  return null;
}

let storage = null;
function getBucket() {
  if (!storage) storage = new Storage();
  return storage.bucket(BUCKET_NAME);
}

/** ISBN'i normalleştirir: rakam ve X dışındaki her şeyi atar. */
function normalizeIsbn(value) {
  return String(value || "").replace(/[^0-9Xx]/g, "").toUpperCase().trim();
}

/**
 * Kapak değişince önbellekleri temizler.
 *
 * ISBN yanıtı 10 dakika, okul kitap listeleri 2 dakika önbellekleniyor.
 * Temizlenmezse öğretmen kapağı yükledikten sonra eski hâlini görür ve
 * işlem başarısız sanıp tekrar tekrar yükler. Kapak tüm okulları
 * etkilediği için her okulun listesi tazelenir.
 */
async function onbellekTemizle(isbn) {
  try {
    deleteIsbnCache(isbn);
    const okullar = await pool.query("SELECT school_code FROM public.schools");
    for (const row of okullar.rows) {
      invalidateSchoolBooksCache(row.school_code);
    }
  } catch (error) {
    // Önbellek temizliği başarısız olsa da yükleme geçerli; sadece kaydet
    console.error("[COVER_CACHE_CLEAR]", error.message);
  }
}

/**
 * Bir ISBN'e manuel kapak yükler.
 *
 * Kapak `public.books` tablosuna yazılır ve bu tablo tüm okullarca ortak
 * kullanılır; dolayısıyla kapak **aynı ISBN'e sahip bütün okulların
 * kütüphanelerinde** görünür.
 *
 * Dikkat: aynı ISBN, farklı kitap adlarıyla birden çok satırda bulunabiliyor
 * (kayıtlar `isbn + book_name` ikilisiyle ekleniyor). Bu yüzden güncelleme
 * tek satıra değil, o ISBN'e ait TÜM satırlara uygulanır.
 */
const uploadCoverByIsbn = async (req, res, next) => {
  try {
    const isbn = normalizeIsbn(req.params.isbn);

    if (isbn.length !== 10 && isbn.length !== 13) {
      return res.status(400).json({
        success: false,
        message: "ISBN 10 ya da 13 haneli olmalı",
      });
    }

    if (!req.file || !req.file.buffer || req.file.buffer.length === 0) {
      return res.status(400).json({
        success: false,
        message: "Kapak görseli gerekli",
      });
    }

    // Önce istemcinin bildirdiği mime'a bak; tanınmıyorsa (ör. Flutter'ın
    // gönderdiği application/octet-stream) içeriğin baytlarından tespit et.
    let mime = String(req.file.mimetype || "").toLowerCase();
    let ext = ALLOWED_MIME[mime];
    if (!ext) {
      const sniffed = sniffImageType(req.file.buffer);
      if (sniffed) {
        mime = sniffed.mime;
        ext = sniffed.ext;
      }
    }
    if (!ext) {
      return res.status(400).json({
        success: false,
        message: "Sadece JPG, PNG ve WebP desteklenir",
      });
    }

    // Bu ISBN gerçekten kayıtlı mı? Yoksa kimsenin görmeyeceği bir dosya
    // yüklemiş oluruz.
    const mevcut = await pool.query(
      "SELECT book_id FROM public.books WHERE REPLACE(UPPER(COALESCE(isbn,'')), '-', '') = $1",
      [isbn]
    );

    if (mevcut.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Bu ISBN ile kayıtlı kitap bulunamadı",
      });
    }

    // İçerik özeti dosya adına girer: aynı görsel tekrar yüklenirse aynı
    // dosyaya yazılır, farklıysa yeni URL oluşur ve önbellek kendini yeniler.
    const hash = crypto
      .createHash("sha256")
      .update(req.file.buffer)
      .digest("hex")
      .slice(0, 12);

    const objectName = `kapaklar/${isbn}-${hash}.${ext}`;
    const file = getBucket().file(objectName);

    await file.save(req.file.buffer, {
      resumable: false,
      contentType: mime,
      metadata: { cacheControl: CACHE_CONTROL },
    });

    const publicUrl = `https://storage.googleapis.com/${BUCKET_NAME}/${objectName}`;

    // ISBN'e ait TÜM satırlar güncellenir -> her okulda görünür
    const guncel = await pool.query(
      `
      UPDATE public.books
      SET cover_url = $1
      WHERE REPLACE(UPPER(COALESCE(isbn,'')), '-', '') = $2
      RETURNING book_id, book_name
      `,
      [publicUrl, isbn]
    );

    await onbellekTemizle(isbn);

    return res.status(200).json({
      success: true,
      message: `Kapak kaydedildi ve ${guncel.rows.length} kayıtta güncellendi`,
      data: {
        isbn,
        cover_url: publicUrl,
        updatedBooks: guncel.rows.length,
        books: guncel.rows,
      },
    });
  } catch (error) {
    next(error);
  }
};

/** Bir ISBN'in kapağını kaldırır (tüm okullarda). */
const deleteCoverByIsbn = async (req, res, next) => {
  try {
    const isbn = normalizeIsbn(req.params.isbn);

    if (isbn.length !== 10 && isbn.length !== 13) {
      return res.status(400).json({
        success: false,
        message: "ISBN 10 ya da 13 haneli olmalı",
      });
    }

    const guncel = await pool.query(
      `
      UPDATE public.books
      SET cover_url = NULL
      WHERE REPLACE(UPPER(COALESCE(isbn,'')), '-', '') = $1
      RETURNING book_id
      `,
      [isbn]
    );

    await onbellekTemizle(isbn);

    return res.status(200).json({
      success: true,
      message: `Kapak kaldırıldı (${guncel.rows.length} kayıt)`,
      data: { isbn, updatedBooks: guncel.rows.length },
    });
  } catch (error) {
    next(error);
  }
};

module.exports = { uploadCoverByIsbn, deleteCoverByIsbn };
