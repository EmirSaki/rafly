const pool = require("../config/db");
const winston = require("winston");
const axios = require("axios");
const { getBookByISBN } = require("../../services/googleBooksService");
const { getBookFromKasif } = require("../../services/kasifService");
const {
  getIsbnFromCache,
  setIsbnCache,
  setIsbnNotFoundCache,
  deleteIsbnCache,
} = require("../../services/cache.service");

function stripVolumeSuffix(title = "") {
  return String(title).replace(/\s*-\s*Cilt:\s*\d+\s*$/i, "").trim();
}

function extractVolumeNo(title = "") {
  const match = String(title).match(/-\s*Cilt:\s*(\d+)\s*$/i);
  return match ? Number(match[1]) : null;
}

function normalizeLookupIsbn(value = "") {
  return String(value).replace(/[^0-9Xx]/g, "").toUpperCase().trim();
}

// Sadece gerçekten eşleşmiş (Google/D&R/OL-edition) kapağı döndürür.
// Blind ISBN->URL üretmiyoruz; yanlış kapak riski var.
function resolveCoverUrl(storedOrFetched) {
  return String(storedOrFetched || "").trim();
}

// Katalogda kapağı boş bir kitap için, dış kaynaklardan (Google -> D&R/OL)
// kapağı bir kez çeker. Bulursa döndürür, yoksa "".
/**
 * Open Library'den doğrudan ISBN ile kapak.
 *
 * Open Library'nin künye ucu Türkçe kitapların çoğunda boş dönüyor, bu yüzden
 * künye üzerinden kapak aramak çalışmıyor. Kapak sunucusu ise ISBN'i doğrudan
 * kabul ediyor ve künye kaydı olmayan kitaplarda bile kapak verebiliyor.
 * `default=false` olmazsa kapak yokken "kapak yok" görseli döner.
 */
async function fetchOpenLibraryCover(isbn) {
  const normalized = String(isbn || "").replace(/[^0-9Xx]/g, "").toUpperCase();
  if (normalized.length !== 10 && normalized.length !== 13) return "";

  const url = `https://covers.openlibrary.org/b/isbn/${normalized}-L.jpg?default=false`;

  const response = await axios.head(url, {
    timeout: 8000,
    validateStatus: (s) => s === 200 || s === 404,
  });

  if (response.status !== 200) return "";

  // Çok küçük dosya Open Library'nin yer tutucusu olabilir
  const boyut = Number(response.headers["content-length"] || 0);
  if (boyut > 0 && boyut < 1000) return "";

  return url;
}

/** Kapak için kaynak zinciri: Google Books -> D&R -> Open Library */
async function fetchExternalCover(isbn) {
  try {
    const g = await getBookByISBN(isbn);
    if (g && String(g.coverUrl || "").trim()) return String(g.coverUrl).trim();
  } catch (_) {}
  try {
    const k = await getBookFromKasif(isbn);
    if (k && String(k.coverUrl || "").trim()) return String(k.coverUrl).trim();
  } catch (_) {}
  try {
    const o = await fetchOpenLibraryCover(isbn);
    if (o) return o;
  } catch (_) {}
  return "";
}

function normalizeStringArray(value) {
  if (!value) return [];

  if (Array.isArray(value)) {
    return value
      .map((item) => String(item).trim())
      .filter(Boolean);
  }

  if (typeof value === "string") {
    return value
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean);
  }

  return [];
}

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || "info",
  format: winston.format.combine(
    winston.format.timestamp({ format: "YYYY-MM-DD HH:mm:ss" }),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.simple()
      ),
    }),
  ],
});

const getBookByIsbn = async (req, res) => {
  const rawIsbn = req.params.isbn;
  const isbn = normalizeLookupIsbn(rawIsbn);

  if (!isbn) {
    return res.status(400).json({
      success: false,
      message: "Geçerli bir ISBN girilmedi",
    });
  }

  try {
    logger.info(`Fetching book details for ISBN: ${isbn}`);

    const cached = getIsbnFromCache(isbn);

    if (cached.hit) {
      if (cached.found) {
        return res.json({
          success: true,
          data: cached.data,
        });
      }

      return res.status(404).json({
        success: false,
        message: "Kitap bulunamadı",
      });
    }

    const localBookResult = await pool.query(
      `
      SELECT *
      FROM books
      WHERE isbn = $1
      ORDER BY book_name ASC
      `,
      [isbn]
    );

    if (localBookResult.rows.length > 0) {
      const rows = localBookResult.rows;

      const baseTitle = stripVolumeSuffix(rows[0].book_name || "");
      const volumes = rows
        .map((row) => ({
          volumeNo: extractVolumeNo(row.book_name),
          title: row.book_name || "",
        }))
        .filter((item) => item.volumeNo !== null)
        .sort((a, b) => a.volumeNo - b.volumeNo);

      const authors = normalizeStringArray(rows[0].book_writer);
      const categories = normalizeStringArray(rows[0].book_genre);

      // Katalogda kayıtlı ama kapağı boşsa: dış kaynaktan bir kez çek + kaydet
      let coverUrl = resolveCoverUrl(rows[0].cover_url);
      if (!coverUrl) {
        coverUrl = await fetchExternalCover(rows[0].isbn || isbn);
        if (coverUrl) {
          try {
            await pool.query(
              `UPDATE books SET cover_url = $1
               WHERE isbn = $2 AND (cover_url IS NULL OR cover_url = '')`,
              [coverUrl, rows[0].isbn || isbn]
            );
          } catch (_) {}
        }
      }

      const responseData = {
        title: baseTitle || rows[0].book_name || "",
        authors,
        publisher:
          rows[0].publisher && String(rows[0].publisher).trim() !== ""
            ? rows[0].publisher
            : "Bilinmiyor",
        categories,
        isbn: rows[0].isbn || isbn,
        isbn10: "",
        isbn13: rows[0].isbn || isbn,
        pageCount: Number(rows[0].page_count) || 0, // DB'den gelen sayfa sayısı
        coverUrl,
        isValilikBook: Boolean(rows[0].is_valilik_book),
        source: "local_db",
        physicalDescription: rows[0].page_count ? `${rows[0].page_count} sayfa` : "",
        volumeCount: volumes.length > 1 ? volumes.length : 0,
        hasVolumes: volumes.length > 1,
        volumes,
      };

      setIsbnCache(isbn, responseData, "local_db");

      return res.json({
        success: true,
        data: responseData,
      });
    }

    logger.info(`Book not found locally, querying external source for ISBN: ${isbn}`);

    let book = null;

    try {
      book = await getBookByISBN(isbn);
    } catch (externalError) {
      logger.error(`External ISBN lookup failed for ${isbn}`, {
        error: externalError.message,
        stack: externalError.stack,
      });

      deleteIsbnCache(isbn);

      return res.status(502).json({
        success: false,
        message: "Harici kitap servisine erişilemedi",
      });
    }

    if (!book) {
      // Google'da bulunamadı, Kaşif (Milli Kütüphane) dene
      logger.info(`Google'da bulunamadı, Kaşif deneniyor: ${isbn}`);
      try {
        book = await getBookFromKasif(isbn);
      } catch (kasifError) {
        logger.error(`Kaşif lookup failed for ${isbn}`, {
          error: kasifError.message,
        });
      }
    }

    if (!book) {
      setIsbnNotFoundCache(isbn, "not_found");

      return res.status(404).json({
        success: false,
        message: "Kitap bulunamadı",
      });
    }

    const bookSource = book.source || "google_books";

    const responseData = {
      title: book.title || "",
      authors: normalizeStringArray(book.authors),
      publisher: book.publisher || "Bilinmiyor",
      categories: normalizeStringArray(book.categories),
      isbn: normalizeLookupIsbn(book.isbn || isbn),
      isbn10: normalizeLookupIsbn(book.isbn10 || ""),
      isbn13: normalizeLookupIsbn(book.isbn13 || ""),
      pageCount: Number(book.pageCount) || 0,
      coverUrl: resolveCoverUrl(book.coverUrl),
      source: bookSource,
      physicalDescription: book.physicalDescription || "",
      volumeCount: Number(book.volumeCount) > 1 ? Number(book.volumeCount) : 0,
      hasVolumes: Boolean(book.hasVolumes),
      volumes: Array.isArray(book.volumes) ? book.volumes : [],
    };

    setIsbnCache(isbn, responseData, bookSource);

    return res.json({
      success: true,
      data: responseData,
    });
  } catch (error) {
    logger.error("Book service hatası:", {
      error: error.message,
      stack: error.stack,
    });

    return res.status(500).json({
      success: false,
      message: "Kitap bilgisi alınamadı",
    });
  }
};

const getAllBooks = async (req, res, next) => {
  try {
    const result = await pool.query("SELECT * FROM books ORDER BY book_id ASC");

    res.status(200).json({
      success: true,
      data: result.rows,
    });
  } catch (error) {
    next(error);
  }
};

const getBookById = async (req, res, next) => {
  try {
    const { id } = req.params;

    const result = await pool.query("SELECT * FROM books WHERE book_id = $1", [
      id,
    ]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Book not found",
      });
    }

    res.status(200).json({
      success: true,
      data: result.rows[0],
    });
  } catch (error) {
    next(error);
  }
};

const createBook = async (req, res) => {
  try {
    const {
      title,
      authors,
      publisher,
      categories,
      isbn: rawIsbn,
      volumeCount = 0,
      physicalDescription = "",
      pageCount = 0, // Request body'den sayfa sayısını alıyoruz
      coverUrl = "",
      isValilikBook = false, // Valilik kitabı mı? (ortak katalog alanı)
    } = req.body;

    const isbn = normalizeLookupIsbn(rawIsbn);
    const coverToStore = String(coverUrl || "").trim();
    const valilikFlag = isValilikBook === true || isValilikBook === "true";

    if (!title || !isbn) {
      return res.status(400).json({
        success: false,
        message: "Başlık ve ISBN zorunlu",
      });
    }

    const normalizedAuthors = normalizeStringArray(authors);
    const normalizedCategories = normalizeStringArray(categories);

    const authorsText = normalizedAuthors.join(", ");
    const categoriesText = normalizedCategories.join(", ");

    const parsedVolumeCount = Number(volumeCount) > 1 ? Number(volumeCount) : 0;

    const volumeTitles =
      parsedVolumeCount > 1
        ? Array.from(
            { length: parsedVolumeCount },
            (_, i) => `${title} - Cilt: ${i + 1}`
          )
        : [title];

    const createdBooks = [];
    const existingBooks = [];

    for (const volumeTitle of volumeTitles) {
      const existingBook = await pool.query(
        "SELECT * FROM books WHERE isbn = $1 AND book_name = $2 LIMIT 1",
        [isbn, volumeTitle]
      );

      if (existingBook.rows.length > 0) {
        existingBooks.push(existingBook.rows[0]);
        continue;
      }

      // page_count ve is_valilik_book sütunlarını sorguya ekledik
      const result = await pool.query(
        `
        INSERT INTO books (book_name, book_writer, book_genre, publisher, isbn, page_count, cover_url, is_valilik_book)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING *
        `,
        [volumeTitle, authorsText, categoriesText, publisher || "", isbn, Number(pageCount) || 0, coverToStore || null, valilikFlag]
      );

      createdBooks.push(result.rows[0]);
    }

    deleteIsbnCache(isbn);

    if (createdBooks.length === 0) {
      return res.status(409).json({
        success: false,
        message: "Bu kitabın tüm ciltleri zaten ana katalogda kayıtlı",
        alreadyExists: true,
        data: existingBooks,
      });
    }

    return res.status(201).json({
      success: true,
      message:
        volumeTitles.length > 1
          ? `${createdBooks.length} cilt ana kataloğa eklendi`
          : "Kitap ana kataloğa eklendi",
      data: createdBooks,
      meta: {
        title,
        isbn,
        physicalDescription,
        pageCount: Number(pageCount) || 0,
        volumeCount: parsedVolumeCount,
        hasVolumes: parsedVolumeCount > 1,
      },
    });
  } catch (error) {
    return res.status(500).json({
      success: false,
      message: "Kitap eklenemedi",
      error: error.message,
    });
  }
};

const updateBook = async (req, res, next) => {
  try {
    const { id } = req.params;
    const {
      book_name,
      book_writer,
      book_genre,
      book_quantity,
      book_available_quantity,
      page_count, // Güncelleme için eklendi
      is_valilik_book, // Valilik kitabı işareti (opsiyonel)
    } = req.body;

    const existing = await pool.query("SELECT * FROM books WHERE book_id = $1", [
      id,
    ]);

    if (existing.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Book not found",
      });
    }

    const current = existing.rows[0];

    const result = await pool.query(
      `UPDATE books
       SET book_name = $1,
           book_writer = $2,
           book_genre = $3,
           book_quantity = $4,
           book_available_quantity = $5,
           page_count = $6,
           is_valilik_book = $7
       WHERE book_id = $8
       RETURNING *`,
      [
        book_name ?? current.book_name,
        book_writer ?? current.book_writer,
        book_genre ?? current.book_genre,
        book_quantity ?? current.book_quantity,
        book_available_quantity ?? current.book_available_quantity,
        page_count ?? current.page_count,
        is_valilik_book ?? current.is_valilik_book,
        id,
      ]
    );

    if (current.isbn) {
      deleteIsbnCache(normalizeLookupIsbn(current.isbn));
    }
    if (result.rows[0]?.isbn) {
      deleteIsbnCache(normalizeLookupIsbn(result.rows[0].isbn));
    }

    res.status(200).json({
      success: true,
      message: "Book updated",
      data: result.rows[0],
    });
  } catch (error) {
    next(error);
  }
};

const deleteBook = async (req, res, next) => {
  try {
    const { id } = req.params;

    const result = await pool.query(
      "DELETE FROM books WHERE book_id = $1 RETURNING *",
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Book not found",
      });
    }

    if (result.rows[0]?.isbn) {
      deleteIsbnCache(normalizeLookupIsbn(result.rows[0].isbn));
    }

    res.status(200).json({
      success: true,
      message: "Book deleted",
    });
  } catch (error) {
    next(error);
  }
};

module.exports = {
  getAllBooks,
  getBookByIsbn,
  getBookById,
  createBook,
  updateBook,
  deleteBook,
};