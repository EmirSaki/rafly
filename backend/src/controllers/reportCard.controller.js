const path = require("path");
const fs = require("fs");
const PDFDocument = require("pdfkit");
const archiver = require("archiver");
const pool = require("../config/db");

// Karne başına ayrı bir PDF üretildiği için font her dokümanda yeniden
// ayrıştırılıyor. Tam NotoSans (614 KB) bunu ~79 ms'ye çıkarıyordu ve 618
// öğrencide istek zaman aşımına uğruyordu. Latin + Türkçe karakterlere
// indirgenmiş 10 KB'lık alt küme aynı görüntüyü verir, ayrıştırma ~2 ms'ye iner.
// Alt kümeyi üreten betik: tools/build-font-subset.js
const FONT_REGULAR = path.join(
  __dirname,
  "../../assets/fonts/NotoSans-Regular-Subset.ttf"
);
const FONT_BOLD = path.join(
  __dirname,
  "../../assets/fonts/NotoSans-Bold-Subset.ttf"
);

// Fontlar bir kez okunur; her karne için diskten tekrar okumak
// yüzlerce öğrencide gözle görülür yavaşlama yaratıyor.
let fontRegularBuffer = null;
let fontBoldBuffer = null;

function loadFonts() {
  if (!fontRegularBuffer) fontRegularBuffer = fs.readFileSync(FONT_REGULAR);
  if (!fontBoldBuffer) fontBoldBuffer = fs.readFileSync(FONT_BOLD);
}

const COLORS = {
  primary: "#1A3366",
  text: "#111827",
  muted: "#6B7280",
  border: "#E5E7EB",
  soft: "#F3F4F6",
  accent: "#16A34A",
};

/** "6A", "6/A", "11-C" → "6" ; "ÖĞRETMEN" → null */
function extractGrade(className) {
  if (!className) return null;
  const match = String(className).trim().match(/^(\d{1,2})/);
  return match ? match[1] : null;
}

/** "6A" → "6/A" ; harf içermeyenler olduğu gibi kalır */
function prettyClass(className) {
  const value = String(className ?? "").trim();
  const match = value.match(/^(\d{1,2})\s*[/\-.]?\s*([A-Za-zÇĞİÖŞÜçğıöşü]{1,3})$/);
  return match ? `${match[1]}/${match[2].toLocaleUpperCase("tr-TR")}` : value;
}

/** Dosya/klasör adında kullanılamayan karakterleri temizler. */
function safeName(value, fallback = "-") {
  const cleaned = String(value ?? "")
    .replace(/[\\/:*?"<>|]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return cleaned || fallback;
}

function formatDate(value) {
  if (!value) return "-";
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return "-";
  const two = (n) => String(n).padStart(2, "0");
  return `${two(date.getDate())}.${two(date.getMonth() + 1)}.${date.getFullYear()}`;
}

/**
 * Rekabet sıralaması: eşit okuma sayısına sahip öğrenciler aynı sırayı alır,
 * sonraki sıra atlar (1, 2, 2, 4). Sıfır kitap okuyanlar da sıralamaya girer.
 *
 * @returns Map<studentKey, {rank, total}>
 */
function computeRanks(students, countOf) {
  const sorted = [...students].sort((a, b) => countOf(b) - countOf(a));
  const result = new Map();

  let previousCount = null;
  let previousRank = 0;

  sorted.forEach((student, index) => {
    const count = countOf(student);
    const rank = count === previousCount ? previousRank : index + 1;
    previousCount = count;
    previousRank = rank;
    result.set(student.key, { rank, total: students.length });
  });

  return result;
}

/** Öğrenciyi tekil kılan anahtar. Aynı numara farklı seviyelerde olabiliyor. */
function studentKey(row) {
  if (row.student_id != null) return `id:${row.student_id}`;
  return `nl:${String(row.student_number ?? "").trim()}|${String(
    row.school_level ?? ""
  ).trim().toLowerCase()}`;
}

/**
 * Okulun tüm öğrencilerini, okudukları kitapları ve dört ayrı sıralamayı
 * hesaplar. Sıralamalar her zaman **okulun tamamı** üzerinden hesaplanır;
 * öğrenci filtresi yalnızca karnesi basılacak kişileri seçer, sıralamayı
 * daraltmaz.
 *
 * [period] verilirse yalnızca o aralıkta **iade edilmiş** kitaplar sayılır ve
 * sıralamalar da o aralığa göre hesaplanır. Böylece "bu dönem" karnesi
 * çıkarılabilir.
 */
async function buildReportData(schemaName, period = {}) {
  const studentsResult = await pool.query(`
    SELECT
      student_id,
      student_number,
      full_name,
      class_name,
      school_level
    FROM ${schemaName}.students
    ORDER BY full_name ASC
  `);

  const readParams = [];
  const readFilters = ["LOWER(COALESCE(sr.status, '')) = 'returned'"];

  if (period.startDate) {
    readParams.push(period.startDate);
    readFilters.push(`sr.returned_at >= $${readParams.length}::date`);
  }
  if (period.endDate) {
    readParams.push(period.endDate);
    // Bitiş günü dahil olsun diye ertesi günün başlangıcına kadar
    readFilters.push(
      `sr.returned_at < ($${readParams.length}::date + INTERVAL '1 day')`
    );
  }

  const readsResult = await pool.query(
    `
    SELECT
      sr.student_local_id,
      COALESCE(sr.student_number, st.student_number) AS student_number,
      st.school_level,
      b.book_name,
      b.isbn,
      sr.reserved_at,
      sr.returned_at
    FROM ${schemaName}.reservations sr
    JOIN public.books b ON b.book_id = sr.book_id
    LEFT JOIN ${schemaName}.students st
      ON sr.student_local_id IS NOT NULL
      AND st.student_id = sr.student_local_id
    WHERE ${readFilters.join(" AND ")}
    ORDER BY sr.returned_at ASC NULLS LAST, sr.reserved_at ASC
    `,
    readParams
  );

  const students = studentsResult.rows.map((row) => ({
    ...row,
    key: studentKey(row),
    grade: extractGrade(row.class_name),
    level: String(row.school_level ?? "").trim().toLowerCase(),
    books: [],
  }));

  const byId = new Map();
  const byNumberLevel = new Map();
  for (const student of students) {
    if (student.student_id != null) byId.set(String(student.student_id), student);
    byNumberLevel.set(
      `${String(student.student_number ?? "").trim()}|${student.level}`,
      student
    );
  }

  for (const read of readsResult.rows) {
    let student = null;

    if (read.student_local_id != null) {
      student = byId.get(String(read.student_local_id)) || null;
    }
    if (!student) {
      const level = String(read.school_level ?? "").trim().toLowerCase();
      student = byNumberLevel.get(
        `${String(read.student_number ?? "").trim()}|${level}`
      ) || null;
    }
    if (!student) continue; // kaydı bir öğrenciye bağlayamıyorsak sayma

    student.books.push({
      book_name: read.book_name,
      isbn: read.isbn,
      returned_at: read.returned_at,
      reserved_at: read.reserved_at,
    });
  }

  const countOf = (student) => student.books.length;

  // 1) Okul geneli
  const schoolRanks = computeRanks(students, countOf);

  // 2) Seviye içi
  const levelRanks = new Map();
  const byLevel = new Map();
  for (const student of students) {
    if (!byLevel.has(student.level)) byLevel.set(student.level, []);
    byLevel.get(student.level).push(student);
  }
  for (const group of byLevel.values()) {
    for (const [key, value] of computeRanks(group, countOf)) {
      levelRanks.set(key, value);
    }
  }

  // 3) Sınıf düzeyi içi (ör. tüm 6. sınıflar)
  const gradeRanks = new Map();
  const byGrade = new Map();
  for (const student of students) {
    if (!student.grade) continue;
    const gradeKey = `${student.level}|${student.grade}`;
    if (!byGrade.has(gradeKey)) byGrade.set(gradeKey, []);
    byGrade.get(gradeKey).push(student);
  }
  for (const group of byGrade.values()) {
    for (const [key, value] of computeRanks(group, countOf)) {
      gradeRanks.set(key, value);
    }
  }

  // 4) Şube içi (ör. 6/A)
  const classRanks = new Map();
  const byClass = new Map();
  for (const student of students) {
    const className = String(student.class_name ?? "").trim();
    if (!className) continue;
    const classKey = `${student.level}|${className}`;
    if (!byClass.has(classKey)) byClass.set(classKey, []);
    byClass.get(classKey).push(student);
  }
  for (const group of byClass.values()) {
    for (const [key, value] of computeRanks(group, countOf)) {
      classRanks.set(key, value);
    }
  }

  for (const student of students) {
    student.count = student.books.length;
    student.ranks = {
      school: schoolRanks.get(student.key) || null,
      level: levelRanks.get(student.key) || null,
      grade: gradeRanks.get(student.key) || null,
      class: classRanks.get(student.key) || null,
    };
  }

  return students;
}

// ─── PDF çizimi ───

function drawRankBox(doc, x, y, width, label, rankInfo) {
  const height = 58;

  doc.roundedRect(x, y, width, height, 6).fillAndStroke(COLORS.soft, COLORS.border);

  doc
    .fillColor(COLORS.muted)
    .font("NotoSans")
    .fontSize(7.5)
    .text(label, x + 8, y + 9, { width: width - 16, align: "center" });

  if (!rankInfo) {
    doc
      .fillColor(COLORS.muted)
      .font("NotoSans")
      .fontSize(13)
      .text("-", x + 8, y + 27, { width: width - 16, align: "center" });
    return;
  }

  doc
    .fillColor(COLORS.primary)
    .font("NotoSans-Bold")
    .fontSize(19)
    .text(String(rankInfo.rank), x + 8, y + 22, {
      width: width - 16,
      align: "center",
    });

  doc
    .fillColor(COLORS.muted)
    .font("NotoSans")
    .fontSize(7)
    .text(`/ ${rankInfo.total} öğrenci`, x + 8, y + 44, {
      width: width - 16,
      align: "center",
    });
}

/** Karne başlığında gösterilecek dönem metni. */
function periodLabel(period = {}) {
  const start = period.startDate ? formatDate(period.startDate) : null;
  const end = period.endDate ? formatDate(period.endDate) : null;

  if (start && end) return `${start} - ${end}`;
  if (start) return `${start} tarihinden itibaren`;
  if (end) return `${end} tarihine kadar`;
  return "Tüm zamanlar";
}

/** Tek öğrencinin karnesini hâlihazırda açık bir dokümana çizer. */
function drawReportCard(doc, student, schoolName, period = {}) {
  const left = doc.page.margins.left;
  const width = doc.page.width - doc.page.margins.left - doc.page.margins.right;

  // Başlık
  doc
    .fillColor(COLORS.primary)
    .font("NotoSans-Bold")
    .fontSize(15)
    .text(schoolName || "Okul", left, 40, { width, align: "center" });

  doc
    .fillColor(COLORS.text)
    .font("NotoSans-Bold")
    .fontSize(20)
    .text("Okuma Karnesi", left, doc.y + 4, { width, align: "center" });

  doc
    .fillColor(COLORS.primary)
    .font("NotoSans-Bold")
    .fontSize(9.5)
    .text(`Dönem: ${periodLabel(period)}`, left, doc.y + 5, {
      width,
      align: "center",
    });

  doc
    .fillColor(COLORS.muted)
    .font("NotoSans")
    .fontSize(8)
    .text(`Oluşturulma: ${formatDate(new Date())}`, left, doc.y + 2, {
      width,
      align: "center",
    });

  let y = doc.y + 14;
  doc.moveTo(left, y).lineTo(left + width, y).strokeColor(COLORS.primary).lineWidth(1.5).stroke();
  y += 16;

  // Öğrenci bilgileri
  doc.roundedRect(left, y, width, 62, 6).fillAndStroke("#FFFFFF", COLORS.border);

  doc
    .fillColor(COLORS.text)
    .font("NotoSans-Bold")
    .fontSize(15)
    .text(student.full_name || "-", left + 14, y + 12, { width: width - 28 });

  doc
    .fillColor(COLORS.muted)
    .font("NotoSans")
    .fontSize(10)
    .text(
      `Okul No: ${student.student_number ?? "-"}    ` +
        `Sınıf: ${prettyClass(student.class_name) || "-"}    ` +
        `Seviye: ${student.school_level || "-"}`,
      left + 14,
      y + 36,
      { width: width - 28 }
    );

  y += 78;

  // Okunan kitap sayısı
  doc.roundedRect(left, y, width, 52, 6).fillAndStroke("#F0FDF4", "#BBF7D0");
  doc
    .fillColor(COLORS.muted)
    .font("NotoSans")
    .fontSize(9)
    .text("Okuduğu Kitap Sayısı", left, y + 10, { width, align: "center" });
  doc
    .fillColor(COLORS.accent)
    .font("NotoSans-Bold")
    .fontSize(22)
    .text(String(student.count), left, y + 22, { width, align: "center" });

  y += 66;

  // Sıralamalar
  doc
    .fillColor(COLORS.text)
    .font("NotoSans-Bold")
    .fontSize(11)
    .text("Sıralamalar", left, y);
  y += 16;

  const gap = 8;
  const boxWidth = (width - gap * 3) / 4;

  // Hiç kitap okumamış öğrencide sıra gösterilmez: herkesin 0 olduğu bir
  // şubede eşitlikten "1." çıkıyor ve karnede yanıltıcı duruyor.
  const showRanks = student.count > 0;
  const rankOf = (key) => (showRanks ? student.ranks[key] : null);
  const gradeLabel = student.grade
    ? `${student.grade}. Sınıflar Arasında`
    : "Sınıf Düzeyinde";
  const classLabel = student.class_name
    ? `${prettyClass(student.class_name)} İçinde`
    : "Şube İçinde";

  drawRankBox(doc, left, y, boxWidth, "Okul Geneli", rankOf("school"));
  drawRankBox(
    doc,
    left + (boxWidth + gap),
    y,
    boxWidth,
    `${student.school_level || "Seviye"} Geneli`,
    rankOf("level")
  );
  drawRankBox(doc, left + (boxWidth + gap) * 2, y, boxWidth, gradeLabel, rankOf("grade"));
  drawRankBox(doc, left + (boxWidth + gap) * 3, y, boxWidth, classLabel, rankOf("class"));

  y += 58 + 4;

  if (!showRanks) {
    doc
      .fillColor(COLORS.muted)
      .font("NotoSans")
      .fontSize(8)
      .text(
        "Henüz tamamlanmış kitap kaydı olmadığı için sıralama gösterilmiyor.",
        left,
        y,
        { width }
      );
  }

  y += 16;

  // Okunan kitaplar
  doc
    .fillColor(COLORS.text)
    .font("NotoSans-Bold")
    .fontSize(11)
    .text("Okuduğu Kitaplar", left, y);
  y += 16;

  if (student.books.length === 0) {
    doc.roundedRect(left, y, width, 40, 6).fillAndStroke(COLORS.soft, COLORS.border);
    doc
      .fillColor(COLORS.muted)
      .font("NotoSans")
      .fontSize(10)
      .text("Bu dönemde tamamlanmış kitap kaydı yok.", left, y + 15, {
        width,
        align: "center",
      });
    return;
  }

  // Tablo başlığı
  const colNo = 26;
  const colDate = 78;
  const colBook = width - colNo - colDate;

  doc.rect(left, y, width, 20).fillAndStroke(COLORS.soft, COLORS.border);
  doc.fillColor(COLORS.muted).font("NotoSans-Bold").fontSize(8.5);
  doc.text("#", left + 6, y + 6, { width: colNo - 6 });
  doc.text("Kitap Adı", left + colNo, y + 6, { width: colBook - 6 });
  doc.text("İade", left + colNo + colBook, y + 6, { width: colDate - 6 });
  y += 20;

  const bottomLimit = doc.page.height - doc.page.margins.bottom - 24;

  const rowHeight = 17;

  for (let index = 0; index < student.books.length; index++) {
    const book = student.books[index];

    // Sayfaya sığmayan kitaplar tek satırda özetlenir; karne tek sayfa kalsın
    if (y + rowHeight > bottomLimit) {
      doc
        .fillColor(COLORS.muted)
        .font("NotoSans")
        .fontSize(8.5)
        .text(
          `... ve ${student.books.length - index} kitap daha`,
          left + 6,
          y + 4
        );
      break;
    }

    if (index % 2 === 1) {
      doc.rect(left, y, width, rowHeight).fill("#FAFAFA");
    }

    doc.fillColor(COLORS.text).font("NotoSans").fontSize(9);
    doc.text(String(index + 1), left + 6, y + 4.5, { width: colNo - 6 });
    doc.text(book.book_name || "-", left + colNo, y + 4.5, {
      width: colBook - 6,
      ellipsis: true,
      lineBreak: false,
    });
    doc
      .fillColor(COLORS.muted)
      .text(formatDate(book.returned_at), left + colNo + colBook, y + 4.5, {
        width: colDate - 6,
      });

    y += rowHeight;
  }
}

function newDocument() {
  loadFonts();
  const doc = new PDFDocument({ margin: 36, size: "A4", autoFirstPage: false });
  doc.registerFont("NotoSans", fontRegularBuffer);
  doc.registerFont("NotoSans-Bold", fontBoldBuffer);
  return doc;
}

function renderSingleCard(student, schoolName, period = {}) {
  return new Promise((resolve, reject) => {
    const doc = newDocument();
    const chunks = [];
    doc.on("data", (chunk) => chunks.push(chunk));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);

    doc.addPage();
    drawReportCard(doc, student, schoolName, period);
    doc.end();
  });
}

// ─── Uç nokta ───

const generateReportCards = async (req, res, next) => {
  try {
    const { schoolCode } = req.params;
    const { school_level, grade, class_name, format, startDate, endDate } =
      req.query;

    if (!/^\d+$/.test(String(schoolCode))) {
      return res.status(400).json({ success: false, message: "Geçersiz okul kodu" });
    }

    // Biçim doğru olsa da tarih geçersiz olabilir (ör. 2026-13-99);
    // takvimde gerçekten var mı diye de bakılır.
    const isDate = (value) => {
      const text = String(value).trim();
      if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return false;
      const [year, month, day] = text.split("-").map(Number);
      const date = new Date(Date.UTC(year, month - 1, day));
      return (
        date.getUTCFullYear() === year &&
        date.getUTCMonth() === month - 1 &&
        date.getUTCDate() === day
      );
    };

    const period = {};
    if (startDate && String(startDate).trim() !== "") {
      if (!isDate(startDate)) {
        return res.status(400).json({
          success: false,
          message: "Başlangıç tarihi geçerli bir tarih olmalı (YYYY-AA-GG)",
        });
      }
      period.startDate = String(startDate).trim();
    }
    if (endDate && String(endDate).trim() !== "") {
      if (!isDate(endDate)) {
        return res.status(400).json({
          success: false,
          message: "Bitiş tarihi geçerli bir tarih olmalı (YYYY-AA-GG)",
        });
      }
      period.endDate = String(endDate).trim();
    }

    if (period.startDate && period.endDate && period.startDate > period.endDate) {
      return res.status(400).json({
        success: false,
        message: "Başlangıç tarihi bitiş tarihinden sonra olamaz",
      });
    }

    const schoolResult = await pool.query(
      "SELECT * FROM public.schools WHERE school_code = $1 LIMIT 1",
      [schoolCode]
    );

    if (schoolResult.rows.length === 0) {
      return res.status(404).json({ success: false, message: "Okul bulunamadı" });
    }

    const school = schoolResult.rows[0];
    const schemaName = `school_${schoolCode}`;

    const allStudents = await buildReportData(schemaName, period);

    // Filtre yalnızca kimin karnesinin basılacağını belirler
    const wantedLevel = String(school_level ?? "").trim().toLowerCase();
    const wantedGrade = String(grade ?? "").trim();
    const wantedClass = String(class_name ?? "").trim().toLowerCase();

    const selected = allStudents.filter((student) => {
      if (wantedLevel && student.level !== wantedLevel) return false;
      if (wantedGrade && student.grade !== wantedGrade) return false;
      if (
        wantedClass &&
        String(student.class_name ?? "").trim().toLowerCase() !== wantedClass
      ) {
        return false;
      }
      return true;
    });

    if (selected.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Bu filtreye uyan öğrenci bulunamadı",
      });
    }

    // Farklı aralıkların çıktıları birbirini ezmesin diye dosya adı döneme göre
    // PDF üretmeden özet: panel "bu aralıkta kaç kitap" bilgisini karneyle
    // birebir aynı hesaptan gösterebilsin diye.
    if (String(format ?? "").toLowerCase() === "json") {
      const totalBooks = selected.reduce((sum, s) => sum + s.count, 0);
      return res.status(200).json({
        success: true,
        data: {
          period: {
            startDate: period.startDate ?? null,
            endDate: period.endDate ?? null,
            label: periodLabel(period),
          },
          studentCount: selected.length,
          readingStudentCount: selected.filter((s) => s.count > 0).length,
          totalBooks,
          classCount: new Set(
            selected.map((s) => String(s.class_name ?? "-"))
          ).size,
          topReaders: [...selected]
            .sort((a, b) => b.count - a.count)
            .slice(0, 5)
            .map((s) => ({
              student_number: s.student_number,
              full_name: s.full_name,
              class_name: s.class_name,
              school_level: s.school_level,
              count: s.count,
              schoolRank: s.ranks.school?.rank ?? null,
            })),
        },
      });
    }

    const stamp =
      period.startDate || period.endDate
        ? `${period.startDate || "baslangic"}_${period.endDate || "bugun"}`
        : new Date().toISOString().slice(0, 10);

    // Tek birleşik PDF
    if (String(format ?? "").toLowerCase() === "pdf") {
      res.setHeader("Content-Type", "application/pdf");
      res.setHeader(
        "Content-Disposition",
        `attachment; filename="karneler-${schoolCode}-${stamp}.pdf"`
      );

      const doc = newDocument();
      doc.pipe(res);

      const ordered = [...selected].sort(
        (a, b) =>
          String(a.class_name ?? "").localeCompare(String(b.class_name ?? ""), "tr") ||
          String(a.full_name ?? "").localeCompare(String(b.full_name ?? ""), "tr")
      );

      for (const student of ordered) {
        doc.addPage();
        drawReportCard(doc, student, school.school_name, period);
      }

      doc.end();
      return;
    }

    // Varsayılan: sınıflara göre klasörlenmiş ZIP
    res.setHeader("Content-Type", "application/zip");
    res.setHeader(
      "Content-Disposition",
      `attachment; filename="karneler-${schoolCode}-${stamp}.zip"`
    );

    const archive = archiver("zip", { zlib: { level: 6 } });
    archive.on("warning", (err) => console.warn("[REPORT_CARD_ZIP]", err));
    archive.on("error", (err) => {
      console.error("[REPORT_CARD_ZIP]", err);
      if (!res.headersSent) {
        res.status(500).json({ success: false, message: "Arşiv oluşturulamadı" });
      } else {
        res.destroy(err);
      }
    });
    archive.pipe(res);

    for (const student of selected) {
      const buffer = await renderSingleCard(student, school.school_name, period);

      const levelFolder = safeName(student.school_level, "seviye-yok");
      // "6/A" klasör adında kullanılamaz; safeName'e girmeden önce tireye çevrilir
      const classFolder = safeName(
        prettyClass(student.class_name).replace("/", "-"),
        "sinif-yok"
      );
      const fileName = safeName(
        `${student.student_number ?? "no-yok"} - ${student.full_name ?? "isimsiz"}`,
        "ogrenci"
      );

      archive.append(buffer, {
        name: `${levelFolder}/${classFolder}/${fileName}.pdf`,
      });
    }

    await archive.finalize();
  } catch (error) {
    next(error);
  }
};

module.exports = {
  generateReportCards,
  // veritabanı olmadan test edilebilsin diye dışa açık
  renderSingleCard,
  computeRanks,
  extractGrade,
  prettyClass,
};
