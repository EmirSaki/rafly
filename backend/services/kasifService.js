const axios = require("axios");
const cheerio = require("cheerio");

const HTTP_TIMEOUT = 12000;

function cleanText(value) {
  return String(value || "").replace(/\s+/g, " ").trim();
}

function normalizeIsbn(value) {
  return String(value || "")
    .replace(/[^0-9Xx]/g, "")
    .toUpperCase()
    .trim();
}

// D&R JSON-LD'si bazen string içinde kaçışsız kontrol karakteri içerir ve
// JSON.parse patlar. Önce ham dene, olmazsa kontrol karakterlerini temizle.
function safeParseJsonLd(html) {
  if (!html) return null;
  try {
    return JSON.parse(html);
  } catch {}
  try {
    return JSON.parse(html.replace(/[\x00-\x1F]/g, " "));
  } catch {}
  return null;
}

// ═══════════════════════════════════════════════════════
// 1) Open Library API
// ═══════════════════════════════════════════════════════

async function fetchFromOpenLibrary(isbn) {
  console.log(`[OPENLIBRARY] Aranıyor: ${isbn}`);
  try {
    const editionRes = await axios.get(
      `https://openlibrary.org/isbn/${isbn}.json`,
      { timeout: HTTP_TIMEOUT }
    );
    const edition = editionRes.data;
    if (!edition || !edition.title) return null;

    // Yazar
    const authors = [];
    if (Array.isArray(edition.authors)) {
      for (const ref of edition.authors.slice(0, 3)) {
        if (!ref.key) continue;
        try {
          const r = await axios.get(`https://openlibrary.org${ref.key}.json`, { timeout: HTTP_TIMEOUT });
          if (r.data?.name) authors.push(cleanText(r.data.name));
        } catch {}
      }
    }

    // Kategori
    const categories = [];
    if (Array.isArray(edition.works) && edition.works.length > 0) {
      try {
        const r = await axios.get(`https://openlibrary.org${edition.works[0].key}.json`, { timeout: HTTP_TIMEOUT });
        if (Array.isArray(r.data?.subjects)) {
          categories.push(...r.data.subjects.slice(0, 5).map(s => cleanText(s)).filter(Boolean));
        }
      } catch {}
    }

    const publishers = Array.isArray(edition.publishers) ? edition.publishers : [];
    const isbn10arr = Array.isArray(edition.isbn_10) ? edition.isbn_10 : [];
    const isbn13arr = Array.isArray(edition.isbn_13) ? edition.isbn_13 : [];

    const result = {
      title: cleanText(edition.full_title || edition.title),
      authors,
      publisher: publishers.length > 0 ? cleanText(publishers[0]) : "Bilinmiyor",
      categories,
      isbn: (isbn13arr[0] && normalizeIsbn(isbn13arr[0])) || (isbn10arr[0] && normalizeIsbn(isbn10arr[0])) || isbn,
      isbn10: isbn10arr[0] ? normalizeIsbn(isbn10arr[0]) : "",
      isbn13: isbn13arr[0] ? normalizeIsbn(isbn13arr[0]) : "",
      pageCount: Number(edition.number_of_pages) || 0,
      coverUrl:
        Array.isArray(edition.covers) && edition.covers[0] > 0
          ? `https://covers.openlibrary.org/b/id/${edition.covers[0]}-L.jpg`
          : "",
      source: "openlibrary",
    };

    console.log(`[OPENLIBRARY] Bulundu: "${result.title}"`);
    return result;
  } catch (error) {
    if (error.response?.status === 404) {
      console.log(`[OPENLIBRARY] Bulunamadı: ${isbn}`);
    } else {
      console.error(`[OPENLIBRARY_ERROR] ${isbn}: ${error.message}`);
    }
    return null;
  }
}

// ═══════════════════════════════════════════════════════
// 2) D&R Scraper (JSON-LD)
// ═══════════════════════════════════════════════════════

async function fetchFromDR(isbn) {
  console.log(`[DR] Aranıyor: ${isbn}`);
  try {
    const res = await axios.get(`https://www.dr.com.tr/search?q=${isbn}`, {
      timeout: HTTP_TIMEOUT,
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "tr-TR,tr;q=0.9",
      },
      maxRedirects: 5,
    });

    const $ = cheerio.load(res.data);

    // JSON-LD'den Book tipini bul
    let bookData = null;
    $('script[type="application/ld+json"]').each((_i, el) => {
      const json = safeParseJsonLd($(el).html());
      if (!json) return;
      const types = Array.isArray(json["@type"]) ? json["@type"] : [json["@type"]];
      if (types.includes("Book") || types.includes("Product")) {
        bookData = json;
      }
    });

    if (!bookData || !bookData.name) {
      console.log(`[DR] JSON-LD bulunamadı: ${isbn}`);
      return null;
    }

    // ISBN kontrolü — doğru kitap mı?
    const bookIsbn = normalizeIsbn(bookData.gtin13 || bookData.isbn || "");
    if (bookIsbn && bookIsbn !== isbn && bookIsbn.length >= 10) {
      console.log(`[DR] ISBN uyuşmazlığı: beklenen=${isbn}, gelen=${bookIsbn}`);
      return null;
    }

    // Yazar
    const authors = [];
    if (bookData.author) {
      if (Array.isArray(bookData.author)) {
        bookData.author.forEach(a => {
          if (a.name) authors.push(cleanText(a.name));
        });
      } else if (bookData.author.name) {
        authors.push(cleanText(bookData.author.name));
      }
    }
    // Sayfadaki yazar linklerinden de çek (çevirmen hariç)
    if (authors.length === 0) {
      $('a[href*="/yazar/"]').each((_i, el) => {
        const name = cleanText($(el).text());
        if (name && name !== "Yazarlar" && !authors.includes(name)) {
          authors.push(name);
        }
      });
    }

    // Yayıncı
    let publisher = "Bilinmiyor";
    if (bookData.publisher?.name) {
      publisher = cleanText(bookData.publisher.name);
    }
    if (publisher === "Bilinmiyor") {
      $('a[href*="/yayinevi/"]').each((_i, el) => {
        const name = cleanText($(el).text());
        if (name && name.length > 1) {
          publisher = name;
          return false;
        }
      });
    }

    // Sayfa sayısı
    const pageCount = Number(bookData.numberOfPages) || 0;

    // Kapak görseli (JSON-LD image alanı: string, dizi ya da {url} olabilir)
    let coverUrl = "";
    const img = bookData.image;
    if (typeof img === "string") {
      coverUrl = img;
    } else if (Array.isArray(img) && img.length > 0) {
      coverUrl = typeof img[0] === "string" ? img[0] : cleanText(img[0]?.url);
    } else if (img && typeof img === "object") {
      coverUrl = cleanText(img.url);
    }
    coverUrl = coverUrl.replace(/^http:\/\//i, "https://");

    const result = {
      title: cleanText(bookData.name),
      authors,
      publisher,
      categories: [],
      isbn: bookIsbn || isbn,
      isbn10: "",
      isbn13: bookIsbn || isbn,
      pageCount,
      coverUrl,
      source: "dr_com_tr",
    };

    console.log(`[DR] Bulundu: "${result.title}" - ${authors.join(", ") || "?"} (${pageCount} sayfa)`);
    return result;
  } catch (error) {
    console.error(`[DR_ERROR] ${isbn}: ${error.message}`);
    return null;
  }
}

// ═══════════════════════════════════════════════════════
// Ana fonksiyon: Zincir halinde dene
// ═══════════════════════════════════════════════════════

async function getBookFromKasif(isbn) {
  const cleanIsbn = normalizeIsbn(isbn);
  if (!cleanIsbn) return null;

  // 1) D&R (Türkçe kitaplarda en güçlü)
  const drResult = await fetchFromDR(cleanIsbn);
  if (drResult) return drResult;

  // 2) Open Library (uluslararası yedek)
  const olResult = await fetchFromOpenLibrary(cleanIsbn);
  if (olResult) return olResult;

  console.log(`[BOOK_LOOKUP] Hiçbir kaynakta bulunamadı: ${cleanIsbn}`);
  return null;
}

module.exports = { getBookFromKasif };
