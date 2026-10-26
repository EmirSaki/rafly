const pool = require("../config/db");
const ExcelJS = require("exceljs");
const PDFDocument = require("pdfkit");
const path = require("path");
const fs = require("fs");

const {
  getSchoolBooksFromCache,
  setSchoolBooksCache,
  invalidateSchoolBooksCache,
  deleteIsbnCache,
} = require("../../services/cache.service");

function normalizeIsbn(value = "") {
  return String(value).replace(/[^0-9Xx]/g, "").toUpperCase().trim();
}

// Sadece kayıtlı (gerçekten eşleşmiş) kapağı döndürür. Blind ISBN->URL yok.
function resolveCoverUrl(stored) {
  return String(stored || "").trim();
}

// Raf adı: boşlukları kırp, 100 karakterle sınırla, boşsa null döndür
function normalizeShelf(value) {
  if (value === undefined || value === null) return null;
  const trimmed = String(value).trim().slice(0, 100);
  return trimmed === "" ? null : trimmed;
}

// Çoklu raf girişini normalize eder: kitabın bulunduğu raf ETİKETLERİ.
// Raf başına adet tutulmaz. Giriş string listesi (["A2","B4"]) veya
// nesne listesi ([{shelf:"A2"}]) olabilir; boşlar atılır, tekilleştirilir.
function normalizeShelfList(value) {
  if (!Array.isArray(value)) return [];
  const seen = new Set();
  const labels = [];
  for (const item of value) {
    const raw = item && typeof item === "object" ? (item.shelf ?? item.name) : item;
    const shelf = normalizeShelf(raw);
    if (!shelf || seen.has(shelf)) continue;
    seen.add(shelf);
    labels.push(shelf);
  }
  return labels;
}

// book_inventory geriye dönük uyum için tek "shelf" değeri tuttuğundan,
// raf etiket listesinden ilk etiketi döndürür.
function primaryShelf(shelfLabels) {
  return shelfLabels.length > 0 ? shelfLabels[0] : null;
}

// Kitabın bulunduğu raf etiketlerini okur (string listesi).
async function fetchShelfLabels(runner, schemaName, bookId) {
  const result = await runner.query(
    `SELECT shelf
     FROM ${schemaName}.book_shelf_locations
     WHERE book_id = $1
     ORDER BY shelf ASC`,
    [bookId]
  );
  return result.rows.map((r) => r.shelf);
}

function normalizeTurkishSearch(value = "") {
  return String(value)
    .toLowerCase()
    .replace(/ı/g, "i")
    .replace(/İ/g, "i")
    .replace(/ş/g, "s")
    .replace(/Ş/g, "s")
    .replace(/ğ/g, "g")
    .replace(/Ğ/g, "g")
    .replace(/ü/g, "u")
    .replace(/Ü/g, "u")
    .replace(/ö/g, "o")
    .replace(/Ö/g, "o")
    .replace(/ç/g, "c")
    .replace(/Ç/g, "c")
    .trim();
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

function buildVolumeTitles(title, volumeCount) {
  if (!volumeCount || volumeCount <= 1) {
    return [title];
  }

  return Array.from(
    { length: volumeCount },
    (_, i) => `${title} - Cilt: ${i + 1}`
  );
}

// pageCount parametresi eklendi
async function findOrCreateBook({
  client,
  title,
  authorsText,
  categoriesText,
  publisher,
  isbn,
  pageCount = 0,
  coverUrl = "",
  isValilikBook = false,
}) {
  const coverToStore = String(coverUrl || "").trim() || null;
  const valilikFlag = isValilikBook === true || isValilikBook === "true";

  let bookResult = await client.query(
    "SELECT * FROM books WHERE isbn = $1 AND book_name = $2 LIMIT 1",
    [isbn, title]
  );

  if (bookResult.rows.length === 0) {
    bookResult = await client.query(
      `
      INSERT INTO books (book_name, book_writer, book_genre, publisher, isbn, page_count, cover_url, is_valilik_book)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      RETURNING *
      `,
      [title, authorsText, categoriesText, publisher || "", isbn, Number(pageCount) || 0, coverToStore, valilikFlag]
    );
  } else {
    // Kayıt zaten varsa: düzenleme ekranından gelen bilgilerle güncelle.
    // cover_url kuralları:
    //   - yeni kapak boşsa mevcut kapağı KORU (COALESCE)
    //   - mevcut kapak ELLE yüklenmişse (kendi kovamızda duruyorsa) asla
    //     üzerine yazma: öğretmen bilerek o fotoğrafı koymuş, dışarıdan
    //     gelen otomatik kapak onu ezmemeli
    bookResult = await client.query(
      `
      UPDATE books
      SET book_writer = $2,
          book_genre = $3,
          publisher = $4,
          page_count = $5,
          cover_url = CASE
            WHEN COALESCE(cover_url, '') LIKE '%/library-app-492714-kapaklar/%'
              THEN cover_url
            ELSE COALESCE($6, cover_url)
          END,
          is_valilik_book = (COALESCE(is_valilik_book, FALSE) OR $7)
      WHERE book_id = $1
      RETURNING *
      `,
      [
        bookResult.rows[0].book_id,
        authorsText,
        categoriesText,
        publisher || "",
        Number(pageCount) || 0,
        coverToStore,
        valilikFlag,
      ]
    );
  }

  return bookResult.rows[0];
}

async function getSchoolBooksRaw(schoolCode, search = "") {
  if (!/^\d+$/.test(String(schoolCode))) {
    throw new Error("Geçersiz okul kodu");
  }

  const schoolCheck = await pool.query(
    "SELECT * FROM schools WHERE school_code = $1 LIMIT 1",
    [schoolCode]
  );

  if (schoolCheck.rows.length === 0) {
    const err = new Error("Okul bulunamadı");
    err.statusCode = 404;
    throw err;
  }

  const schemaName = `school_${schoolCode}`;
  const searchTerm = normalizeTurkishSearch(search || "");

  const whereClause = searchTerm
    ? `
        WHERE
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
          public.immutable_unaccent(lower(b.book_name)),
          'ı','i'),'ş','s'),'ğ','g'),'ü','u'),'ö','o'),'ç','c')
        ILIKE $1
        OR
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
          public.immutable_unaccent(lower(b.book_writer)),
          'ı','i'),'ş','s'),'ğ','g'),'ü','u'),'ö','o'),'ç','c')
        ILIKE $1
      `
    : "";

const params = searchTerm ? [`%${searchTerm}%`] : [];

  // b.page_count eklendi
  const query = `
    SELECT
      b.book_id,
      b.book_name AS title,
      b.page_count,
      CASE
        WHEN b.book_writer IS NULL OR b.book_writer = '' THEN ARRAY[]::text[]
        ELSE string_to_array(b.book_writer, ', ')
      END AS authors,
      b.publisher,
      CASE
        WHEN b.book_genre IS NULL OR b.book_genre = '' THEN ARRAY[]::text[]
        ELSE string_to_array(b.book_genre, ', ')
      END AS categories,
      b.isbn,
      b.cover_url,
      b.is_valilik_book,
      bi.quantity,
      bi.available_quantity,
      bi.shelf,
      COALESCE((
        SELECT json_agg(sl.shelf ORDER BY sl.shelf)
        FROM ${schemaName}.book_shelf_locations sl
        WHERE sl.book_id = b.book_id
      ), '[]'::json) AS shelves
    FROM ${schemaName}.book_inventory bi
    INNER JOIN public.books b ON b.book_id = bi.book_id
    ${whereClause}
    ORDER BY b.book_name ASC
  `;

  const result = await pool.query(query, params);
  return result.rows;
}

const accessSchool = async (req, res, next) => {
  try {
    const { schoolCode } = req.body;

    if (!schoolCode) {
      return res.status(400).json({
        success: false,
        message: "schoolCode zorunlu",
      });
    }

    if (!/^\d+$/.test(String(schoolCode))) {
      return res.status(400).json({
        success: false,
        message: "Geçersiz okul kodu",
      });
    }

    const result = await pool.query(
      "SELECT * FROM schools WHERE school_code = $1 LIMIT 1",
      [schoolCode]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Okul bulunamadı",
      });
    }

    const school = result.rows[0];

    return res.status(200).json({
      success: true,
      data: {
        schoolId: school.school_id,
        schoolCode: school.school_code,
        schoolName: school.school_name,
        schemaName: `school_${school.school_code}`,
      },
    });
  } catch (error) {
    next(error);
  }
};

const getSchoolBooks = async (req, res, next) => {
  try {
    const { schoolCode } = req.params;
    const { page = 1, limit = 30, search = "" } = req.query;

    if (!/^\d+$/.test(String(schoolCode))) {
      return res.status(400).json({
        success: false,
        message: "Geçersiz okul kodu",
      });
    }

    const parsedPage = Math.max(parseInt(page, 10) || 1, 1);
    const parsedLimit = Math.max(parseInt(limit, 10) || 30, 1);
    const offset = (parsedPage - 1) * parsedLimit;
    const searchTerm = normalizeTurkishSearch(search || "");

    const cached = getSchoolBooksFromCache({
      schoolCode,
      page: parsedPage,
      limit: parsedLimit,
      search: searchTerm,
    });

    if (cached) {
      return res.status(200).json(cached);
    }

    const schoolCheck = await pool.query(
      "SELECT * FROM schools WHERE school_code = $1 LIMIT 1",
      [schoolCode]
    );

    if (schoolCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Okul bulunamadı",
      });
    }

    const schemaName = `school_${schoolCode}`;

  const whereClause = searchTerm
    ? `
      WHERE
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
          public.immutable_unaccent(lower(b.book_name)),
          'ı','i'),'ş','s'),'ğ','g'),'ü','u'),'ö','o'),'ç','c')
        ILIKE $1
        OR
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
          public.immutable_unaccent(lower(b.book_writer)),
          'ı','i'),'ş','s'),'ğ','g'),'ü','u'),'ö','o'),'ç','c')
        ILIKE $1
    `
    : "";

    const countParams = searchTerm ? [`%${searchTerm}%`] : [];
    const dataParams = searchTerm
      ? [`%${searchTerm}%`, parsedLimit, offset]
      : [parsedLimit, offset];

    const countQuery = `
      SELECT COUNT(*)::int AS total
      FROM ${schemaName}.book_inventory bi
      INNER JOIN public.books b ON b.book_id = bi.book_id
      ${whereClause}
    `;

    const totalQuantityQuery = `
      SELECT COALESCE(SUM(bi.quantity), 0)::int AS total_quantity
      FROM ${schemaName}.book_inventory bi
      INNER JOIN public.books b ON b.book_id = bi.book_id
      ${whereClause}
    `;

    // b.page_count eklendi
    const dataQuery = `
      SELECT
        b.book_id,
        b.book_name AS title,
        b.page_count,
        CASE
          WHEN b.book_writer IS NULL OR b.book_writer = '' THEN ARRAY[]::text[]
          ELSE string_to_array(b.book_writer, ', ')
        END AS authors,
        b.publisher,
        CASE
          WHEN b.book_genre IS NULL OR b.book_genre = '' THEN ARRAY[]::text[]
          ELSE string_to_array(b.book_genre, ', ')
        END AS categories,
        b.isbn,
        b.cover_url,
        b.is_valilik_book,
        bi.quantity,
        bi.available_quantity,
        bi.shelf,
        COALESCE((
          SELECT json_agg(sl.shelf ORDER BY sl.shelf)
          FROM ${schemaName}.book_shelf_locations sl
          WHERE sl.book_id = b.book_id
        ), '[]'::json) AS shelves
      FROM ${schemaName}.book_inventory bi
      INNER JOIN public.books b ON b.book_id = bi.book_id
      ${whereClause}
      ORDER BY b.book_name ASC
      LIMIT $${searchTerm ? 2 : 1}
      OFFSET $${searchTerm ? 3 : 2}
    `;

    const countResult = await pool.query(countQuery, countParams);
    const totalQuantityResult = await pool.query(totalQuantityQuery, countParams);
    const dataResult = await pool.query(dataQuery, dataParams);

    const total = countResult.rows[0]?.total || 0;
    const totalPages = Math.ceil(total / parsedLimit);
    const totalQuantity = totalQuantityResult.rows[0]?.total_quantity || 0;

    const responsePayload = {
      success: true,
      data: dataResult.rows.map((row) => ({
        ...row,
        isbn: normalizeIsbn(row.isbn || ""),
        authors: normalizeStringArray(row.authors),
        categories: normalizeStringArray(row.categories),
        cover_url: resolveCoverUrl(row.cover_url),
      })),
      summary: {
        totalQuantity,
      },
      pagination: {
        page: parsedPage,
        limit: parsedLimit,
        total,
        totalPages,
        hasNextPage: parsedPage < totalPages,
        hasPrevPage: parsedPage > 1,
      },
      filters: {
        search: searchTerm,
      },
    };

    setSchoolBooksCache(
      {
        schoolCode,
        page: parsedPage,
        limit: parsedLimit,
        search: searchTerm,
      },
      responsePayload
    );

    return res.status(200).json(responsePayload);
  } catch (error) {
    next(error);
  }
};

const getSchoolBookByIsbn = async (req, res, next) => {
  try {
    const { schoolCode, isbn } = req.params;

    if (!/^\d+$/.test(String(schoolCode))) {
      return res.status(400).json({
        success: false,
        message: "Geçersiz okul kodu",
      });
    }

    const normalizedIsbn = normalizeIsbn(isbn);

    if (!normalizedIsbn) {
      return res.status(400).json({
        success: false,
        message: "Geçerli bir ISBN girilmedi",
      });
    }

    const schoolCheck = await pool.query(
      "SELECT * FROM schools WHERE school_code = $1 LIMIT 1",
      [schoolCode]
    );

    if (schoolCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Okul bulunamadı",
      });
    }

    const schemaName = `school_${schoolCode}`;

    const result = await pool.query(
      `
      SELECT
        b.book_id,
        b.book_name AS title,
        b.page_count,
        CASE
          WHEN b.book_writer IS NULL OR b.book_writer = '' THEN ARRAY[]::text[]
          ELSE string_to_array(b.book_writer, ', ')
        END AS authors,
        b.publisher,
        CASE
          WHEN b.book_genre IS NULL OR b.book_genre = '' THEN ARRAY[]::text[]
          ELSE string_to_array(b.book_genre, ', ')
        END AS categories,
        b.isbn,
        b.cover_url,
        b.is_valilik_book,
        bi.quantity,
        bi.available_quantity,
        bi.shelf,
        COALESCE((
          SELECT json_agg(sl.shelf ORDER BY sl.shelf)
          FROM ${schemaName}.book_shelf_locations sl
          WHERE sl.book_id = b.book_id
        ), '[]'::json) AS shelves
      FROM ${schemaName}.book_inventory bi
      INNER JOIN public.books b ON b.book_id = bi.book_id
      WHERE b.isbn = $1
      ORDER BY b.book_name ASC
      LIMIT 1
      `,
      [normalizedIsbn]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Kitap bu okulun envanterinde bulunamadı",
      });
    }

    const row = result.rows[0];

    return res.status(200).json({
      success: true,
      data: {
        ...row,
        isbn: normalizeIsbn(row.isbn || ""),
        authors: normalizeStringArray(row.authors),
        categories: normalizeStringArray(row.categories),
        cover_url: resolveCoverUrl(row.cover_url),
        pageCount: Number(row.page_count) || 0,
        source: "school_db",
      },
    });
  } catch (error) {
    next(error);
  }
};

const getSchoolBookDetail = async (req, res, next) => {
  try {
    const { schoolCode, bookId } = req.params;

    if (!/^\d+$/.test(String(schoolCode)) || !/^\d+$/.test(String(bookId))) {
      return res.status(400).json({
        success: false,
        message: "Geçersiz parametre",
      });
    }

    const schoolCheck = await pool.query(
      "SELECT * FROM schools WHERE school_code = $1 LIMIT 1",
      [schoolCode]
    );

    if (schoolCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Okul bulunamadı",
      });
    }

    const schemaName = `school_${schoolCode}`;

    const result = await pool.query(
      `
      SELECT
        b.book_id,
        b.book_name AS title,
        b.page_count,
        CASE
          WHEN b.book_writer IS NULL OR b.book_writer = '' THEN ARRAY[]::text[]
          ELSE string_to_array(b.book_writer, ', ')
        END AS authors,
        b.publisher,
        CASE
          WHEN b.book_genre IS NULL OR b.book_genre = '' THEN ARRAY[]::text[]
          ELSE string_to_array(b.book_genre, ', ')
        END AS categories,
        b.isbn,
        b.cover_url,
        b.is_valilik_book,
        bi.quantity,
        bi.available_quantity,
        bi.shelf,
        COALESCE((
          SELECT json_agg(sl.shelf ORDER BY sl.shelf)
          FROM ${schemaName}.book_shelf_locations sl
          WHERE sl.book_id = b.book_id
        ), '[]'::json) AS shelves
      FROM ${schemaName}.book_inventory bi
      INNER JOIN public.books b ON b.book_id = bi.book_id
      WHERE b.book_id = $1
      LIMIT 1
      `,
      [bookId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Kitap okul envanterinde bulunamadı",
      });
    }

    const row = result.rows[0];

    return res.status(200).json({
      success: true,
      data: {
        ...row,
        isbn: normalizeIsbn(row.isbn || ""),
        authors: normalizeStringArray(row.authors),
        categories: normalizeStringArray(row.categories),
        cover_url: resolveCoverUrl(row.cover_url),
      },
    });
  } catch (error) {
    next(error);
  }
};

const addBookToSchoolInventory = async (req, res, next) => {
  const client = await pool.connect();

  try {
    const { schoolCode } = req.params;
    const {
      title,
      authors,
      publisher,
      categories,
      isbn,
      quantity,
      increaseQuantity = false,
      volumeCount = 0,
      pageCount = 0, // Request body'den alınıyor
      shelf,
      coverUrl = "",
      isValilikBook = false, // Valilik kitabı mı? (ortak katalog alanı)
    } = req.body;

    // Sadece app'in gönderdiği gerçek kapağı sakla (yoksa boş)
    const coverToStore = String(coverUrl || "").trim();

    const normalizedShelf = normalizeShelf(shelf);

    if (!/^\d+$/.test(String(schoolCode))) {
      return res.status(400).json({
        success: false,
        message: "Geçersiz okul kodu",
      });
    }

    const normalizedIsbn = normalizeIsbn(isbn);

    if (!title || !normalizedIsbn) {
      return res.status(400).json({
        success: false,
        message: "Başlık ve ISBN zorunlu",
      });
    }

    const schoolCheck = await client.query(
      "SELECT * FROM schools WHERE school_code = $1 LIMIT 1",
      [schoolCode]
    );

    if (schoolCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Okul bulunamadı",
      });
    }

    const schemaName = `school_${schoolCode}`;
    const normalizedAuthors = normalizeStringArray(authors);
    const normalizedCategories = normalizeStringArray(categories);

    const authorsText = normalizedAuthors.join(", ");
    const categoriesText = normalizedCategories.join(", ");
    const qty = Number(quantity) > 0 ? Number(quantity) : 1;
    const parsedVolumeCount = Number(volumeCount) > 1 ? Number(volumeCount) : 0;
    const volumeTitles = buildVolumeTitles(title, parsedVolumeCount);

    await client.query("BEGIN");

    const preparedVolumes = [];

    for (const volumeTitle of volumeTitles) {
      // pageCount parametresi eklendi
      const book = await findOrCreateBook({
        client,
        title: volumeTitle,
        authorsText,
        categoriesText,
        publisher,
        isbn: normalizedIsbn,
        pageCount,
        coverUrl: coverToStore,
        isValilikBook,
      });

      const existingInventory = await client.query(
        `
        SELECT * FROM ${schemaName}.book_inventory
        WHERE book_id = $1
        LIMIT 1
        `,
        [book.book_id]
      );

      preparedVolumes.push({
        book,
        volumeTitle,
        existingInventory:
          existingInventory.rows.length > 0 ? existingInventory.rows[0] : null,
      });
    }

    const existingVolumes = preparedVolumes
      .filter((item) => item.existingInventory)
      .map((item) => ({
        bookId: item.book.book_id,
        title: item.volumeTitle,
        inventory: item.existingInventory,
      }));

    if (existingVolumes.length > 0 && !increaseQuantity) {
      await client.query("ROLLBACK");
      return res.status(409).json({
        success: false,
        alreadyExistsInSchool: true,
        message:
          "Bu eserin bazı ciltleri okul envanterinde zaten var. Adet artırılsın mı?",
        data: existingVolumes,
      });
    }

    const createdOrUpdated = [];

    for (const item of preparedVolumes) {
      const { book, volumeTitle, existingInventory } = item;

      if (existingInventory) {
        // Toplam adet ve available artar. Rafı EZMİYORUZ: yeni raf ayrı bir
        // kayıt olarak eklenir, aynı rafsa adedi artar (aşağıda upsert).
        const updated = await client.query(
          `
          UPDATE ${schemaName}.book_inventory
          SET quantity = quantity + $2,
              available_quantity = available_quantity + $2,
              shelf = COALESCE(shelf, $3)
          WHERE book_id = $1
          RETURNING *
          `,
          [book.book_id, qty, normalizedShelf]
        );

        createdOrUpdated.push({
          type: "updated",
          book_id: book.book_id,
          title: volumeTitle,
          inventory: updated.rows[0],
        });
      } else {
        const inserted = await client.query(
          `
          INSERT INTO ${schemaName}.book_inventory
          (book_id, quantity, available_quantity, shelf)
          VALUES ($1, $2, $2, $3)
          RETURNING *
          `,
          [book.book_id, qty, normalizedShelf]
        );

        createdOrUpdated.push({
          type: "created",
          book_id: book.book_id,
          title: volumeTitle,
          inventory: inserted.rows[0],
        });
      }

      // Raf etiketi: raf belirtildiyse kitabın bulunduğu raflara ekle.
      // Zaten varsa dokunma (adet tutulmaz, sadece etiket).
      if (normalizedShelf) {
        await client.query(
          `
          INSERT INTO ${schemaName}.book_shelf_locations (book_id, shelf)
          VALUES ($1, $2)
          ON CONFLICT (book_id, shelf) DO NOTHING
          `,
          [book.book_id, normalizedShelf]
        );
      }
    }

    await client.query("COMMIT");
    invalidateSchoolBooksCache(schoolCode);
    deleteIsbnCache(normalizedIsbn);

    const createdCount = createdOrUpdated.filter((x) => x.type === "created").length;
    const updatedCount = createdOrUpdated.filter((x) => x.type === "updated").length;

    return res.status(201).json({
      success: true,
      message:
        volumeTitles.length > 1
          ? `${createdCount} cilt eklendi, ${updatedCount} cilt güncellendi`
          : updatedCount > 0
            ? "Kitap adedi artırıldı"
            : "Kitap okul envanterine eklendi",
      data: createdOrUpdated,
    });
  } catch (error) {
    await client.query("ROLLBACK");
    next(error);
  } finally {
    client.release();
  }
};

const updateSchoolBookQuantity = async (req, res, next) => {
  try {
    const { schoolCode, bookId } = req.params;
    const { quantity, authors, publisher, categories, page_count, shelf, shelves, is_valilik_book } =
      req.body;
    // Başlık hem book_name hem title anahtarıyla gelebilir
    const book_name = req.body.book_name ?? req.body.title;

    // Çoklu raf: shelves gönderildiyse kitabın raf ETİKETLERİ tam olarak
    // bununla değiştirilir. Raf başına adet tutulmaz; toplam adet (quantity)
    // bundan bağımsızdır.
    const shelvesProvided = Array.isArray(shelves);
    const normalizedShelfList = normalizeShelfList(shelves);

    // Tek raf alanı (geriye dönük uyum). shelves varsa onun ilk etiketini kullan.
    const shelfProvided = shelvesProvided || shelf !== undefined;
    const normalizedShelf = shelvesProvided
      ? primaryShelf(normalizedShelfList)
      : normalizeShelf(shelf);

    if (!/^\d+$/.test(String(schoolCode)) || !/^\d+$/.test(String(bookId))) {
      return res.status(400).json({
        success: false,
        message: "Geçersiz parametre",
      });
    }

    // Toplam adet her zaman body'deki quantity'dir (raflardan bağımsız).
    const parsedQuantity = Number(quantity);

    if (!Number.isInteger(parsedQuantity) || parsedQuantity < 0) {
      return res.status(400).json({
        success: false,
        message: "quantity 0 veya daha büyük bir tam sayı olmalı",
      });
    }

    const schoolCheck = await pool.query(
      "SELECT * FROM schools WHERE school_code = $1 LIMIT 1",
      [schoolCode]
    );

    if (schoolCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Okul bulunamadı",
      });
    }

    const schemaName = `school_${schoolCode}`;

    const existingInventory = await pool.query(
      `
      SELECT * FROM ${schemaName}.book_inventory
      WHERE book_id = $1
      LIMIT 1
      `,
      [bookId]
    );

    if (existingInventory.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Kitap okul envanterinde bulunamadı",
      });
    }

    const inventory = existingInventory.rows[0];
    const loanedCount = Math.max(
      0,
      Number(inventory.quantity) - Number(inventory.available_quantity)
    );

    if (parsedQuantity < loanedCount) {
      return res.status(400).json({
        success: false,
        message: `Şu an ${loanedCount} adet ödünçte. Toplam adet bundan az olamaz.`,
      });
    }

    const hasBookUpdate =
      authors !== undefined ||
      publisher !== undefined ||
      categories !== undefined ||
      page_count !== undefined ||
      is_valilik_book !== undefined ||
      (book_name !== undefined && String(book_name).trim() !== "");

    if (hasBookUpdate) {
      const current = await pool.query(
        "SELECT * FROM books WHERE book_id = $1",
        [bookId]
      );

      if (current.rows.length > 0) {
        const cur = current.rows[0];
        const newWriter =
          authors !== undefined
            ? normalizeStringArray(authors).join(", ")
            : cur.book_writer;
        const newGenre =
          categories !== undefined
            ? normalizeStringArray(categories).join(", ")
            : cur.book_genre;
        const newPublisher =
          publisher !== undefined ? publisher : cur.publisher;
        const newPageCount =
          page_count !== undefined ? Number(page_count) || 0 : cur.page_count;
        const newValilik =
          is_valilik_book !== undefined
            ? is_valilik_book === true || is_valilik_book === "true"
            : cur.is_valilik_book;
        const newBookName =
          book_name !== undefined && String(book_name).trim() !== ""
            ? String(book_name).trim()
            : cur.book_name;

        await pool.query(
          `UPDATE books
           SET book_name = $1,
               book_writer = $2,
               book_genre = $3,
               publisher = $4,
               page_count = $5,
               is_valilik_book = $6
           WHERE book_id = $7`,
          [newBookName, newWriter, newGenre, newPublisher, newPageCount, newValilik, bookId]
        );

        if (cur.isbn) {
          const { deleteIsbnCache } = require("../../services/cache.service");
          deleteIsbnCache(normalizeIsbn(cur.isbn));
        }
      }
    }

    const client = await pool.connect();
    let updated;
    try {
      await client.query("BEGIN");

      updated = await client.query(
        `
        UPDATE ${schemaName}.book_inventory
        SET quantity = $2,
            available_quantity = GREATEST(0, $2::int - $3::int),
            shelf = CASE WHEN $4::boolean THEN $5 ELSE shelf END
        WHERE book_id = $1
        RETURNING *
        `,
        [bookId, parsedQuantity, loanedCount, shelfProvided, normalizedShelf]
      );

      // Çoklu raf etiketleri gönderildiyse tam olarak bununla değiştir.
      if (shelvesProvided) {
        await client.query(
          `DELETE FROM ${schemaName}.book_shelf_locations WHERE book_id = $1`,
          [bookId]
        );
        for (const label of normalizedShelfList) {
          await client.query(
            `INSERT INTO ${schemaName}.book_shelf_locations (book_id, shelf)
             VALUES ($1, $2)
             ON CONFLICT (book_id, shelf) DO NOTHING`,
            [bookId, label]
          );
        }
      }

      await client.query("COMMIT");
    } catch (txError) {
      await client.query("ROLLBACK");
      throw txError;
    } finally {
      client.release();
    }

    invalidateSchoolBooksCache(schoolCode);

    return res.status(200).json({
      success: true,
      message: "Kitap bilgileri güncellendi",
      data: {
        ...updated.rows[0],
        shelves: await fetchShelfLabels(pool, schemaName, bookId),
      },
    });
  } catch (error) {
    next(error);
  }
};

const deleteSchoolBookFromInventory = async (req, res, next) => {
  try {
    const { schoolCode, bookId } = req.params;

    if (!/^\d+$/.test(String(schoolCode)) || !/^\d+$/.test(String(bookId))) {
      return res.status(400).json({
        success: false,
        message: "Geçersiz parametre",
      });
    }

    const schoolCheck = await pool.query(
      "SELECT * FROM schools WHERE school_code = $1 LIMIT 1",
      [schoolCode]
    );

    if (schoolCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Okul bulunamadı",
      });
    }

    const schemaName = `school_${schoolCode}`;

    await pool.query(
      `DELETE FROM ${schemaName}.book_shelf_locations WHERE book_id = $1`,
      [bookId]
    );

    const deleted = await pool.query(
      `
      DELETE FROM ${schemaName}.book_inventory
      WHERE book_id = $1
      RETURNING *
      `,
      [bookId]
    );

    if (deleted.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Kitap okul envanterinde bulunamadı",
      });
    }

    invalidateSchoolBooksCache(schoolCode);

    return res.status(200).json({
      success: true,
      message: "Kitap sadece bu okulun envanterinden silindi",
    });
  } catch (error) {
    next(error);
  }
};

const exportSchoolBooks = async (req, res, next) => {
  try {
    const { schoolCode } = req.params;
    const { format = "excel", search = "" } = req.query;

    const books = await getSchoolBooksRaw(schoolCode, search);

    if (format === "excel") {
      const workbook = new ExcelJS.Workbook();
      const sheet = workbook.addWorksheet("Kitaplar");

      sheet.columns = [
        { header: "Kitap Adı", key: "title", width: 40 },
        { header: "Yazar", key: "authors", width: 30 },
        { header: "Tür", key: "categories", width: 25 },
        { header: "Yayınevi", key: "publisher", width: 25 },
        { header: "ISBN", key: "isbn", width: 20 },
        { header: "Raf", key: "shelf", width: 15 },
        { header: "Valilik Kitabı", key: "valilik", width: 14 },
        { header: "Adet", key: "quantity", width: 10 },
        { header: "Sayfa", key: "pageCount", width: 10 }, // Excel'e sayfa sütunu da eklendi
      ];

      sheet.getRow(1).font = { bold: true };

      books.forEach((b) => {
        sheet.addRow({
          title: b.title || "",
          authors: normalizeStringArray(b.authors).join(", "),
          categories: normalizeStringArray(b.categories).join(", "),
          publisher: b.publisher || "",
          isbn: normalizeIsbn(b.isbn || ""),
          shelf: (Array.isArray(b.shelves) && b.shelves.length > 0
            ? b.shelves.join(", ")
            : (b.shelf || "").toString().trim()),
          valilik: b.is_valilik_book ? "Evet" : "Hayır",
          quantity: b.quantity ?? 0,
          pageCount: b.page_count ?? 0,
        });
      });

      res.setHeader(
        "Content-Type",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      );
      res.setHeader(
        "Content-Disposition",
        `attachment; filename="kitap-listesi-${schoolCode}.xlsx"`
      );

      await workbook.xlsx.write(res);
      return res.end();
    }

    if (format === "pdf") {
      const fontRegular = path.join(__dirname, "../../assets/fonts/NotoSans-Regular.ttf");
      const fontBold = path.join(__dirname, "../../assets/fonts/NotoSans-Bold.ttf");

      const doc = new PDFDocument({ margin: 30, size: "A4" });

      doc.registerFont("NotoSans", fontRegular);
      doc.registerFont("NotoSans-Bold", fontBold);

      res.setHeader("Content-Type", "application/pdf");
      res.setHeader(
        "Content-Disposition",
        `attachment; filename="kitap-listesi-${schoolCode}.pdf"`
      );

      doc.pipe(res);

      doc.font("NotoSans-Bold").fontSize(18).text(`Kitap Listesi - ${schoolCode}`, { align: "center" });
      doc.moveDown();

      books.forEach((b, i) => {
        const authorsText = normalizeStringArray(b.authors).join(", ") || "-";
        const categoriesText = normalizeStringArray(b.categories).join(", ") || "-";
        const shelfText = (b.shelf || "").toString().trim() || "-";
        const valilikText = b.is_valilik_book ? "Evet" : "Hayır";

        doc
          .font("NotoSans-Bold").fontSize(11).text(`${i + 1}. ${b.title || "-"}`)
          .font("NotoSans").fontSize(10)
          .text(`Yazar: ${authorsText}`)
          .text(`Tür: ${categoriesText}`)
          .text(`Yayınevi: ${b.publisher || "-"}`)
          .text(`ISBN: ${normalizeIsbn(b.isbn || "") || "-"}`)
          .text(`Raf: ${shelfText} | Valilik Kitabı: ${valilikText}`)
          .text(`Adet: ${b.quantity ?? 0} | Sayfa: ${b.page_count ?? 0}`)
          .moveDown();
      });

      doc.end();
      return;
    }

    return res.status(400).json({
      success: false,
      message: "Geçersiz format. 'excel' veya 'pdf' kullan.",
    });
  } catch (error) {
    next(error);
  }
};

const uploadSchoolLogo = async (req, res, next) => {
  try {
    const { schoolCode } = req.params;

    if (!/^\d+$/.test(String(schoolCode))) {
      return res.status(400).json({ success: false, message: "Geçersiz okul kodu" });
    }

    if (!req.file) {
      return res.status(400).json({ success: false, message: "Logo dosyası gerekli" });
    }

    const schoolCheck = await pool.query(
      "SELECT * FROM schools WHERE school_code = $1 LIMIT 1",
      [schoolCode]
    );

    if (schoolCheck.rows.length === 0) {
      return res.status(404).json({ success: false, message: "Okul bulunamadı" });
    }

    // Store as base64 data URI
    const mimeType = req.file.mimetype || "image/png";
    const base64 = req.file.buffer.toString("base64");
    const dataUri = `data:${mimeType};base64,${base64}`;

    await pool.query(
      "UPDATE schools SET logo_url = $1 WHERE school_code = $2",
      [dataUri, schoolCode]
    );

    return res.status(200).json({
      success: true,
      message: "Okul logosu güncellendi",
      data: { logo_url: dataUri },
    });
  } catch (error) {
    next(error);
  }
};

const getSchoolLogo = async (req, res, next) => {
  try {
    const { schoolCode } = req.params;

    if (!/^\d+$/.test(String(schoolCode))) {
      return res.status(400).json({ success: false, message: "Geçersiz okul kodu" });
    }

    const result = await pool.query(
      "SELECT logo_url FROM schools WHERE school_code = $1 LIMIT 1",
      [schoolCode]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: "Okul bulunamadı" });
    }

    const logoUrl = result.rows[0].logo_url;

    return res.status(200).json({
      success: true,
      data: { logo_url: logoUrl || null },
    });
  } catch (error) {
    next(error);
  }
};

const deleteSchoolLogo = async (req, res, next) => {
  try {
    const { schoolCode } = req.params;

    if (!/^\d+$/.test(String(schoolCode))) {
      return res.status(400).json({ success: false, message: "Geçersiz okul kodu" });
    }

    const schoolCheck = await pool.query(
      "SELECT * FROM schools WHERE school_code = $1 LIMIT 1",
      [schoolCode]
    );

    if (schoolCheck.rows.length === 0) {
      return res.status(404).json({ success: false, message: "Okul bulunamadı" });
    }

    await pool.query(
      "UPDATE schools SET logo_url = NULL WHERE school_code = $1",
      [schoolCode]
    );

    return res.status(200).json({
      success: true,
      message: "Okul logosu silindi",
    });
  } catch (error) {
    next(error);
  }
};

module.exports = {
  accessSchool,
  getSchoolBooks,
  getSchoolBookByIsbn,
  getSchoolBookDetail,
  addBookToSchoolInventory,
  updateSchoolBookQuantity,
  deleteSchoolBookFromInventory,
  exportSchoolBooks,
  uploadSchoolLogo,
  getSchoolLogo,
  deleteSchoolLogo,
};