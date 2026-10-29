const pool = require("../config/db");
const bcrypt = require("bcrypt");
const jwt = require("jsonwebtoken");
const { ensureStudentsUniqueIndex } = require("../config/studentsIndex");
const ExcelJS = require("exceljs");
const XLSX = require("xlsx");
const crypto = require("crypto");
const { sendStudentPasswordEmail } = require("../utils/mailer");

// Tüm öğrenciler için sabit giriş şifresi. Mail ile şifre alma kaldırıldı;
// öğrenciler okul kodu + seviye + numara + bu şifre ile giriş yapar.
const STUDENT_PASSWORD = "1234";

// Belirsiz karakter içermeyen (0/O, 1/I/l yok) okunaklı şifre üretir
function generateStudentPassword(len = 6) {
  const alphabet = "ABCDEFGHJKLMNPRSTUVYZ23456789";
  let out = "";
  for (let i = 0; i < len; i++) {
    out += alphabet[crypto.randomInt(0, alphabet.length)];
  }
  return out;
}

// E-postayı maskele: ornek@mail.com -> or***@mail.com
function maskEmail(email) {
  const [user, domain] = String(email || "").split("@");
  if (!domain) return email;
  const visible = user.slice(0, Math.min(2, user.length));
  const stars = "*".repeat(Math.max(1, user.length - visible.length));
  return `${visible}${stars}@${domain}`;
}

function signStudentToken(user) {
  return jwt.sign(
    {
      user_id: user.user_id,
      school_id: user.school_id,
      school_code: user.school_code,
      role: user.user_role,
      student_number: user.student_id,
      school_level: user.school_level || null,
    },
    process.env.JWT_SECRET || "dev_secret",
    { expiresIn: "7d" }
  );
}

const registerStudent = async (req, res, next) => {
  const client = await pool.connect();

  try {
    const {
      schoolCode,
      user_name,
      user_surname,
      student_number,
      password,
      user_class,
      user_class_code,
      school_level,
    } = req.body;

    if (
      !schoolCode ||
      !user_name ||
      !user_surname ||
      !student_number ||
      !password ||
      !user_class ||
      !user_class_code
    ) {
      return res.status(400).json({
        success: false,
        message:
          "schoolCode, user_name, user_surname, student_number, password, user_class ve user_class_code zorunlu",
      });
    }

    await client.query("BEGIN");

    const schemaName = `school_${schoolCode}`;

    // Schema'nın var olup olmadığını kontrol et
    const schemaCheck = await client.query(
      `
      SELECT schema_name
      FROM information_schema.schemata
      WHERE schema_name = $1
      `,
      [schemaName]
    );

    if (schemaCheck.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({
        success: false,
        message: "Okul bulunamadı",
      });
    }

    // public.schools'dan okul bilgisini al (public tablosunda kayıt varsa)
    const schoolResult = await client.query(
      "SELECT school_id, school_code FROM public.schools WHERE school_code = $1 LIMIT 1",
      [schoolCode]
    );

    let school;
    if (schoolResult.rows.length > 0) {
      school = schoolResult.rows[0];
    } else {
      // public.schools'da kayıt yoksa, oluştur
      const createSchool = await client.query(
        "INSERT INTO public.schools (school_code, school_name) VALUES ($1, $2) ON CONFLICT (school_code) DO UPDATE SET school_name = EXCLUDED.school_name RETURNING *",
        [schoolCode, `School ${schoolCode}`]
      );
      school = createSchool.rows[0];
    }
    const fullName = `${user_name} ${user_surname}`.trim();
    const normalizedLevel =
      school_level && String(school_level).trim() !== ""
        ? String(school_level).trim().toLowerCase().normalize("NFC")
        : null;

    await client.query(`
      ALTER TABLE ${schemaName}.students
      ADD COLUMN IF NOT EXISTS class_code VARCHAR(50)
    `);

    await client.query(`
      ALTER TABLE ${schemaName}.students
      ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)
    `);

    // users tablolarına school_level sütunu ekle
    await client.query(`
      ALTER TABLE public.users
      ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)
    `);
    await client.query(`
      ALTER TABLE ${schemaName}.users
      ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)
    `);

    // "diğer" seviyesinde öğrenci numarasını backend üretir:
    // client'ın gönderdiği numarayı yok say. Numara her zaman 10000'den
    // başlar: 10000'den itibaren BOŞ olan ilk numara atanır (10000, 10001,
    // ...). Böylece okulda eski/anormal yüksek numaralar olsa bile yeni
    // "diğer" öğrenciler 10000'den gider.
    let effectiveStudentNumber = String(student_number).trim();

    if (normalizedLevel === "diğer") {
      // Aynı anda iki "diğer" kaydının aynı numarayı almasını engelle
      await client.query("SELECT pg_advisory_xact_lock(hashtext($1))", [
        `${schemaName}:diger_student_number`,
      ]);

      const nextNoResult = await client.query(
        `
        WITH nums AS (
          SELECT (student_number)::bigint AS n
          FROM ${schemaName}.students
          WHERE LOWER(COALESCE(school_level, '')) = 'diğer'
            AND student_number ~ '^[0-9]+$'
            AND (student_number)::bigint >= 10000
        )
        SELECT MIN(c) AS next_no
        FROM (
          SELECT 10000::bigint AS c
          WHERE NOT EXISTS (SELECT 1 FROM nums WHERE n = 10000)
          UNION ALL
          SELECT n + 1
          FROM nums
          WHERE NOT EXISTS (SELECT 1 FROM nums n2 WHERE n2.n = nums.n + 1)
        ) candidates
        `
      );

      effectiveStudentNumber = String(nextNoResult.rows[0].next_no || 10000);
    }

    const hashedPassword = await bcrypt.hash(String(password), 10);

    // Aynı numara + seviye kombinasyonuna göre kullanıcı ara
    const existingUserParams = [school.school_id, effectiveStudentNumber];
    let existingUserQuery = `
      SELECT *
      FROM public.users
      WHERE school_id = $1
        AND user_role = 'student'
        AND student_id = $2
    `;
    if (normalizedLevel) {
      existingUserQuery += ` AND LOWER(COALESCE(school_level, '')) = $3`;
      existingUserParams.push(normalizedLevel);
    } else {
      existingUserQuery += ` AND (school_level IS NULL OR school_level = '')`;
    }
    existingUserQuery += ` LIMIT 1`;

    const existingUser = await client.query(existingUserQuery, existingUserParams);

    let createdUser;

    if (existingUser.rows.length > 0) {
      const userUpdate = await client.query(
        `
        UPDATE public.users
        SET user_name = $1,
            user_surname = $2,
            user_class = $3,
            user_class_code = $4,
            password = $5,
            plain_password = $7,
            school_level = $8
        WHERE user_id = $6
        RETURNING
          user_id,
          user_name,
          user_surname,
          user_role,
          student_id,
          user_class,
          user_class_code,
          school_id,
          school_level
        `,
        [
          user_name,
          user_surname,
          user_class,
          user_class_code,
          hashedPassword,
          existingUser.rows[0].user_id,
          String(password),
          normalizedLevel,
        ]
      );

      createdUser = userUpdate.rows[0];
    } else {
      const userInsert = await client.query(
        `
        INSERT INTO public.users
        (
          user_name,
          user_surname,
          user_role,
          student_id,
          user_class,
          user_class_code,
          school_id,
          email,
          password,
          plain_password,
          school_level
        )
        VALUES ($1, $2, 'student', $3, $4, $5, $6, NULL, $7, $8, $9)
        RETURNING
          user_id,
          user_name,
          user_surname,
          user_role,
          student_id,
          user_class,
          user_class_code,
          school_id,
          school_level
        `,
        [
          user_name,
          user_surname,
          effectiveStudentNumber,
          user_class,
          user_class_code,
          school.school_id,
          hashedPassword,
          String(password),
          normalizedLevel,
        ]
      );

      createdUser = userInsert.rows[0];
    }

    await client.query(
      `
      INSERT INTO ${schemaName}.users
      (
        user_id,
        user_name,
        user_surname,
        email,
        password,
        user_role,
        student_id,
        user_class,
        user_class_code,
        school_id,
        school_level
      )
      VALUES ($1, $2, $3, '', $4, 'student', $5, $6, $7, $8, $9)
      ON CONFLICT (user_id) DO UPDATE SET
        user_name = EXCLUDED.user_name,
        user_surname = EXCLUDED.user_surname,
        password = EXCLUDED.password,
        student_id = EXCLUDED.student_id,
        user_class = EXCLUDED.user_class,
        user_class_code = EXCLUDED.user_class_code,
        school_id = EXCLUDED.school_id,
        school_level = EXCLUDED.school_level
      `,
      [
        createdUser.user_id,
        createdUser.user_name,
        createdUser.user_surname,
        hashedPassword,
        effectiveStudentNumber,
        user_class,
        user_class_code,
        school.school_id,
        normalizedLevel,
      ]
    );

    // students tablosunda numara + seviye birlikte unique olmalı
    await client.query(
      `
      WITH updated AS (
        UPDATE ${schemaName}.students
        SET full_name = $2,
            class_name = $3,
            class_code = $4
        WHERE student_number = $1
          AND LOWER(COALESCE(school_level, '')) = LOWER(COALESCE($5, ''))
        RETURNING student_id
      )
      INSERT INTO ${schemaName}.students
      (
        student_number,
        full_name,
        class_name,
        class_code,
        school_level
      )
      SELECT $1, $2, $3, $4, $5
      WHERE NOT EXISTS (SELECT 1 FROM updated)
      `,
      [effectiveStudentNumber, fullName, user_class, user_class_code, normalizedLevel]
    );

    await client.query("COMMIT");

    const token = signStudentToken({
      ...createdUser,
      school_code: school.school_code,
    });

    return res.status(201).json({
      success: true,
      message: "Öğrenci kaydı oluşturuldu",
      token,
      data: {
        ...createdUser,
        school_code: school.school_code,
        school_name: school.school_name,
      },
    });
  } catch (error) {
    await client.query("ROLLBACK");
    next(error);
  } finally {
    client.release();
  }
};

function normalizeCell(value) {
  return String(value ?? "")
    .trim()
    .replace(/\s+/g, " ");
}

function normalizeHeader(value) {
  return normalizeCell(value)
    .toLocaleLowerCase("tr-TR")
    .replace(/ı/g, "i")
    .replace(/İ/g, "i")
    .replace(/ğ/g, "g")
    .replace(/ü/g, "u")
    .replace(/ş/g, "s")
    .replace(/ö/g, "o")
    .replace(/ç/g, "c");
}

function getSchoolLevelByGrade(grade) {
  const n = Number(grade);

  if (n >= 1 && n <= 4) return "ilkokul";
  if (n >= 5 && n <= 8) return "ortaokul";
  if (n >= 9 && n <= 12) return "lise";

  return null;
}

function extractPreparationClassInfo(text) {
  const normalizedText = normalizeHeader(text).replace(/[_-]+/g, " ");

  if (!normalizedText.includes("hazirlik")) {
    return null;
  }

  const match = normalizedText.match(
    /hazirlik\s*(?:sinifi)?\s*(?:\/\s*)?([a-z])(?:\s*subesi)?/
  );

  if (!match) {
    return null;
  }

  const branch = String(match[1]).toLocaleUpperCase("tr-TR");

  return {
    grade: null,
    branch,
    className: `HAZIRLIK-${branch}`,
    schoolLevel: "hazırlık",
  };
}

function extractClassInfo(rows, originalFileName = "") {
  const fileClassInfo = extractPreparationClassInfo(originalFileName);

  if (fileClassInfo) {
    return fileClassInfo;
  }

  const firstRowsText = rows
    .slice(0, 15)
    .map((row) => row.map(normalizeCell).join(" "))
    .join(" ");

  const preparationClassInfo = extractPreparationClassInfo(firstRowsText);

  if (preparationClassInfo) {
    return preparationClassInfo;
  }

  const match = firstRowsText.match(
    /(\d{1,2})\s*\.?\s*Sınıf[\s\S]*?\/\s*([A-ZÇĞİÖŞÜ])\s*Şubesi/i
  );

  if (!match) {
    throw new Error("Sınıf bilgisi bulunamadı. Örnek format: 5. Sınıf / A Şubesi");
  }

  const grade = Number(match[1]);
  const branch = String(match[2]).toLocaleUpperCase("tr-TR");
  const schoolLevel = getSchoolLevelByGrade(grade);

  if (!schoolLevel) {
    throw new Error(`Geçersiz sınıf seviyesi: ${grade}`);
  }

  return {
    grade,
    branch,
    className: `${grade}${branch}`,
    schoolLevel,
  };
}

// Yeni .xlsx dosyalari ZIP tabanlidir ve "PK" (0x50 0x4B) ile baslar.
// Eski .xls (Excel 97-2003) OLE bicimidir; ExcelJS bunu okuyamaz, JSZip
// "Can't find end of central directory" hatasi verir. Bu yuzden bicimi
// uzantiya degil, icerigin ilk baytlarina bakarak belirleyip .xls/.csv
// dosyalarini SheetJS ile okuyoruz.
function isXlsxZipBuffer(buffer) {
  return (
    Buffer.isBuffer(buffer) &&
    buffer.length >= 2 &&
    buffer[0] === 0x50 &&
    buffer[1] === 0x4b
  );
}

async function readRowsFromWorkbook(buffer) {
  const rows = [];

  if (isXlsxZipBuffer(buffer)) {
    // .xlsx -> mevcut ExcelJS yolu (davranis aynen korunur)
    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.load(buffer);
    const sheet = workbook.worksheets[0];

    if (!sheet) {
      throw new Error("Excel dosyasında sayfa bulunamadı");
    }

    sheet.eachRow((row, rowNumber) => {
      const values = [];

      row.eachCell({ includeEmpty: true }, (cell, colNumber) => {
        const source = cell.isMerged ? cell.master : cell;
        values[colNumber - 1] = source.value == null ? "" : source.text || source.value || "";
      });

      if (values.some((value) => normalizeCell(value) !== "")) {
        values.sourceRowNumber = rowNumber;
        rows.push(values);
      }
    });

    return rows;
  }

  // .xls (eski Excel), .csv veya benzeri -> SheetJS
  const workbook = XLSX.read(buffer, { type: "buffer" });
  const sheetName = workbook.SheetNames[0];

  if (!sheetName) {
    throw new Error("Excel dosyasında sayfa bulunamadı");
  }

  const sheet = workbook.Sheets[sheetName];
  const mergedCellsByRow = new Map();
  for (const merge of sheet['!merges'] || []) {
    // Resolve horizontal merged cells just as Excel displays them. Do not
    // propagate student identities into subsequent rows of a vertical merge.
    const rowMerges = mergedCellsByRow.get(merge.s.r) || [];
    rowMerges.push(merge);
    mergedCellsByRow.set(merge.s.r, rowMerges);
  }
  const matrix = XLSX.utils.sheet_to_json(sheet, {
    header: 1,
    defval: "",
    blankrows: true,
    range: 0,
    raw: false,
  });

  for (const [rowIndex, rawRow] of matrix.entries()) {
    const values = (rawRow || []).map((value) => (value == null ? "" : value));
    values.mergedCells = mergedCellsByRow.get(rowIndex) || [];

    if (values.some((value) => normalizeCell(value) !== "")) {
      values.sourceRowNumber = rowIndex + 1;
      rows.push(values);
    }
  }

  return rows;
}

async function parseStudentsFromWorkbook(buffer, originalFileName = "", { strict = false } = {}) {
  if (strict) {
    const book = XLSX.read(buffer, { type: 'buffer', bookSheets: true });
    if (book.SheetNames.length !== 1) throw new Error('Sınıf atlatma için her dosya tek çalışma sayfası içermelidir. Her sınıfı ayrı dosya olarak yükleyin.');
  }
  const rows = await readRowsFromWorkbook(buffer);

  const { className, schoolLevel } = extractClassInfo(rows, originalFileName);

  const headerRowIndex = rows.findIndex((row) =>
    row.some((cell) => normalizeHeader(cell).includes("ogrenci no"))
  );

  if (headerRowIndex === -1) {
    throw new Error("Öğrenci No başlığı bulunamadı");
  }

  const headerRow = rows[headerRowIndex].map(normalizeHeader);

  const studentNumberIndex = headerRow.findIndex((h) =>
    h.includes("ogrenci no")
  );

  const nameIndex = headerRow.findIndex((h) =>
    h === "adi" || (h.includes("adi") && !h.includes("soyadi"))
  );

  const surnameIndex = headerRow.findIndex((h) =>
    h === "soyadi" || h.includes("soyadi")
  );

  if (studentNumberIndex === -1 || nameIndex === -1 || surnameIndex === -1) {
    throw new Error("Öğrenci No, Adı veya Soyadı sütunu bulunamadı");
  }

  const students = [];

  for (let i = headerRowIndex + 1; i < rows.length; i++) {
    const row = rows[i];

    const valueAt = (column) => {
      const merge = (row.mergedCells || []).find(({ s, e }) => s.c <= column && e.c >= column);
      return normalizeCell(row[merge ? merge.s.c : column]);
    };
    const studentNumber = valueAt(studentNumberIndex);
    const name = valueAt(nameIndex);
    const surname = valueAt(surnameIndex);
    const sourceRowNumber = row.sourceRowNumber || i + 1;

    // e-Okul lists include gender totals below the student table.
    // Recognize that footer explicitly so incomplete students still fail validation.
    const footerLabels = row.map(normalizeHeader);
    if (['kiz ogrenci sayisi', 'erkek ogrenci sayisi', 'toplam ogrenci sayisi']
          .every((label) => footerLabels.some((cell) => cell.startsWith(label)))) {
      continue;
    }

    if (!studentNumber || !name || !surname) {
      if (strict && (/^\d+$/.test(studentNumber) || name || surname)) throw new Error(`${sourceRowNumber}. satırda öğrenci numarası, ad veya soyad eksik.`);
      continue;
    }
    if (strict && !/^\d+$/.test(studentNumber)) throw new Error(`${sourceRowNumber}. satırda geçersiz öğrenci numarası.`);

    students.push({
      student_number: studentNumber,
      full_name: `${name} ${surname}`.trim(),
      class_name: className,
      class_code: className,
      school_level: schoolLevel,
    });
  }

  if (students.length === 0) {
    throw new Error("Excel içinde aktarılacak öğrenci bulunamadı");
  }

  return students;
}

// Ayni ogrenciyi (ayni AD SOYAD + NUMARA) farkli sinif/seviyede tutan eski
// kayitlari (ornegin hocanin elle ekledigi mukerrer kaydi) yeni listedeki kayda
// BIRLESTIRIR:
//   1) Yeni anahtarli (seviye+sinif+numara) satiri ekler/gunceller  -> "survivor"
//   2) Ayni ad soyad + numaraya sahip eski satirlarin odunc/rezervasyon
//      gecmisini ve giris/sifre kaydini survivor'a tasir
//   3) Eski mukerrer satirlari siler
// Boylece listede tek (yeni) kayit gorunur; ogrencinin sifresi ve gecmisi korunur.
// NOT: reservations.student_local_id ve users.user_id FK'leri ON DELETE CASCADE
// oldugu icin, silmeden ONCE tasima yapmak sart.
async function upsertStudentWithMerge(client, schemaName, student) {
  const { student_number, full_name, class_name, class_code, school_level } = student;

  // 1) Hedef (survivor) satiri: yeni anahtarla ekle veya guncelle
  const survivorRes = await client.query(
    `
    INSERT INTO ${schemaName}.students
      (student_number, full_name, class_name, class_code, school_level)
    VALUES ($1, $2, $3, $4, $5)
    ON CONFLICT (school_level, class_name, student_number) WHERE archived_at IS NULL
    DO UPDATE SET
      full_name = EXCLUDED.full_name,
      class_code = EXCLUDED.class_code,
      archived_at = NULL
    RETURNING student_id
    `,
    [student_number, full_name, class_name, class_code, school_level]
  );
  const survivorId = survivorRes.rows[0].student_id;

  // 2) Ayni numara + ayni ad soyad (bosluk/buyuk-kucuk duyarsiz) olan, ama
  //    survivor'dan farkli eski satirlar
  const dupRes = await client.query(
    `
    SELECT student_id, school_level
    FROM ${schemaName}.students
    WHERE student_number = $1
      AND LOWER(BTRIM(REGEXP_REPLACE(full_name, '\\s+', ' ', 'g')))
        = LOWER(BTRIM(REGEXP_REPLACE($2, '\\s+', ' ', 'g')))
      AND student_id <> $3
    `,
    [student_number, full_name, survivorId]
  );

  if (dupRes.rows.length === 0) {
    return;
  }

  // survivor'in mevcut giris kullanicisi (varsa)
  const survivorUserRes = await client.query(
    `SELECT user_id FROM ${schemaName}.users
     WHERE user_role = 'student' AND student_id = $1
       AND LOWER(COALESCE(school_level, '')) = LOWER(COALESCE($2, ''))
     LIMIT 1`,
    [student_number, school_level]
  );
  let survivorUserId = survivorUserRes.rows[0] ? survivorUserRes.rows[0].user_id : null;

  for (const dup of dupRes.rows) {
    // 2a) Gecmisi koru: eski satira bagli rezervasyonlari survivor satirina tasi
    //     (student_local_id CASCADE oldugu icin silmeden once sart)
    await client.query(
      `UPDATE ${schemaName}.reservations
       SET student_local_id = $1
       WHERE student_local_id = $2`,
      [survivorId, dup.student_id]
    );

    // 2b) Eski satirin giris/sifre kaydi
    const dupUserRes = await client.query(
      `SELECT user_id FROM ${schemaName}.users
       WHERE user_role = 'student' AND student_id = $1
         AND LOWER(COALESCE(school_level, '')) = LOWER(COALESCE($2, ''))
       LIMIT 1`,
      [student_number, dup.school_level]
    );
    const dupUserId = dupUserRes.rows[0] ? dupUserRes.rows[0].user_id : null;

    if (dupUserId) {
      if (!survivorUserId) {
        // survivor'in kullanicisi yok -> eski kullaniciyi yeni anahtara tasi.
        // Sifre, user_id ve ona bagli tum rezervasyonlar oldugu gibi korunur.
        await client.query(
          `UPDATE ${schemaName}.users
           SET school_level = $1, user_class = $2, user_class_code = $3
           WHERE user_id = $4`,
          [school_level, class_name, class_code, dupUserId]
        );
        await client.query(
          `UPDATE public.users
           SET school_level = $1, user_class = $2, user_class_code = $3
           WHERE user_id = $4`,
          [school_level, class_name, class_code, dupUserId]
        );
        survivorUserId = dupUserId;
      } else if (dupUserId !== survivorUserId) {
        // Hem survivor hem eski kayit ayri giris hesabina sahip:
        // eski hesabin rezervasyonlarini survivor hesabina tasi, sonra eski hesabi sil.
        await client.query(
          `UPDATE ${schemaName}.reservations SET user_id = $1 WHERE user_id = $2`,
          [survivorUserId, dupUserId]
        );
        await client.query(
          `UPDATE public.reservations SET user_id = $1 WHERE user_id = $2`,
          [survivorUserId, dupUserId]
        );
        // public.users silinince ${schemaName}.users (ON DELETE CASCADE) de silinir
        await client.query(`DELETE FROM public.users WHERE user_id = $1`, [dupUserId]);
      }
    }

    // 2c) Eski mukerrer roster satirini sil
    await client.query(
      `DELETE FROM ${schemaName}.students WHERE student_id = $1`,
      [dup.student_id]
    );
  }

  // 3) Hayatta kalan giris kaydini yeni listedeki sinif/seviye ile senkronla
  //    (ayni seviyede yalnizca sinif degisen durumda user_class'i da guncel tutar)
  if (survivorUserId) {
    await client.query(
      `UPDATE ${schemaName}.users
       SET school_level = $1, user_class = $2, user_class_code = $3
       WHERE user_id = $4`,
      [school_level, class_name, class_code, survivorUserId]
    );
    await client.query(
      `UPDATE public.users
       SET school_level = $1, user_class = $2, user_class_code = $3
       WHERE user_id = $4`,
      [school_level, class_name, class_code, survivorUserId]
    );
  }
}

const importStudentsFromExcel = async (req, res, next) => {
  const client = await pool.connect();

  try {
    const { schoolCode } = req.query;

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

    if (!req.file) {
      return res.status(400).json({
        success: false,
        message: "Excel dosyası zorunlu",
      });
    }

    const schemaName = `school_${schoolCode}`;
    const students = await parseStudentsFromWorkbook(
      req.file.buffer,
      req.file.originalname
    );

    await client.query("BEGIN");

    const schemaCheck = await client.query(
      `
      SELECT schema_name
      FROM information_schema.schemata
      WHERE schema_name = $1
      `,
      [schemaName]
    );

    if (schemaCheck.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({
        success: false,
        message: "Okul bulunamadı",
      });
    }

    await client.query(`
      ALTER TABLE ${schemaName}.students
      ADD COLUMN IF NOT EXISTS class_code VARCHAR(50)
    `);

    await client.query(`
      ALTER TABLE ${schemaName}.students
      ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)
    `);

    // Benzersizlik (seviye+sinif+numara) yalnizca AKTIF ogrencilere uygulanir;
    // arsivli "Eski Ogrenciler" haric (kismi unique index). ON CONFLICT bu index'i
    // "WHERE archived_at IS NULL" ile hedefler.
    await ensureStudentsUniqueIndex(client, schemaName);

    let insertedOrUpdatedCount = 0;

    for (const student of students) {
      // Ekle/guncelle + ayni ad soyad + numaraya sahip eski mukerrer kayitlari
      // (farkli sinif/seviye) bu yeni kayda birlestir (sifre + gecmis korunur).
      await upsertStudentWithMerge(client, schemaName, student);

      insertedOrUpdatedCount++;
    }

    await client.query("COMMIT");

    return res.status(201).json({
      success: true,
      message: "Öğrenci listesi başarıyla yüklendi",
      count: insertedOrUpdatedCount,
      class_name: students[0]?.class_name,
      school_level: students[0]?.school_level,
      data: students,
    });
  } catch (error) {
    await client.query("ROLLBACK");
    next(error);
  } finally {
    client.release();
  }
};

const getStudents = async (req, res, next) => {
  try {
    const { schoolCode, school_level, archived } = req.query;

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

    const schemaName = `school_${schoolCode}`;

    // Schema'nın var olup olmadığını kontrol et
    const schemaCheck = await pool.query(
      `
      SELECT schema_name
      FROM information_schema.schemata
      WHERE schema_name = $1
      `,
      [schemaName]
    );

    if (schemaCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Okul bulunamadı",
      });
    }

    await pool.query(`
      ALTER TABLE ${schemaName}.students
      ADD COLUMN IF NOT EXISTS class_code VARCHAR(50)
    `);

    await pool.query(`
      ALTER TABLE ${schemaName}.students
      ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)
    `);

    await pool.query(`
      ALTER TABLE ${schemaName}.students
      ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP
    `);

    const params = [];
    const conditions = [];

    if (school_level && String(school_level).trim() !== "") {
      params.push(String(school_level).trim().toLowerCase());
      conditions.push(`LOWER(COALESCE(s.school_level, '')) = $${params.length}`);
    }

    // archived=true -> yalnizca Eski Ogrenciler; aksi halde yalnizca aktif ogrenciler
    if (String(archived) === "true") {
      conditions.push("s.archived_at IS NOT NULL");
    } else {
      conditions.push("s.archived_at IS NULL");
    }

    const whereClause = conditions.length ? "WHERE " + conditions.join(" AND ") : "";

    await pool.query(`
      ALTER TABLE public.users
      ADD COLUMN IF NOT EXISTS plain_password VARCHAR(255)
    `);

    const result = await pool.query(
      `
      SELECT
        s.student_number,
        s.full_name,
        s.class_name,
        s.class_code,
        s.school_level,
        s.archived_at,
        s.created_at,
        pu.email,
        pu.phone,
        '1234' AS password
      FROM ${schemaName}.students s
      LEFT JOIN ${schemaName}.users su ON su.student_id = s.student_number
        AND LOWER(COALESCE(su.school_level, '')) = LOWER(COALESCE(s.school_level, ''))
      LEFT JOIN public.users pu ON pu.user_id = su.user_id
      ${whereClause}
      ORDER BY s.full_name ASC
      `,
      params
    );

    return res.status(200).json({
      success: true,
      data: result.rows,
    });
  } catch (error) {
    next(error);
  }
};

const createManualStudent = async (req, res, next) => {
  const client = await pool.connect();

  try {
    const {
      schoolCode,
      student_number,
      full_name,
      class_name,
      class_code,
      school_level,
    } = req.body;

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

    const studentNumber = String(student_number ?? "").trim();
    const fullName = String(full_name ?? "").trim();
    const className = String(class_name ?? "").trim().toLocaleUpperCase("tr-TR");
    const classCode = String(class_code ?? className).trim().toLocaleUpperCase("tr-TR");
    const schoolLevel = String(school_level ?? "").trim().toLocaleLowerCase("tr-TR");

    if (!studentNumber || !fullName || !className || !schoolLevel) {
      return res.status(400).json({
        success: false,
        message: "Öğrenci numarası, ad soyad, sınıf ve okul seviyesi zorunlu",
      });
    }

    const allowedLevels = ["ilkokul", "ortaokul", "lise", "hazırlık", "diğer"];

    if (!allowedLevels.includes(schoolLevel)) {
      return res.status(400).json({
        success: false,
        message: "Okul seviyesi ilkokul, ortaokul, lise, hazırlık veya diğer olmalı",
      });
    }

    const schemaName = `school_${schoolCode}`;

    await client.query("BEGIN");

    const schemaCheck = await client.query(
      `
      SELECT schema_name
      FROM information_schema.schemata
      WHERE schema_name = $1
      `,
      [schemaName]
    );

    if (schemaCheck.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({
        success: false,
        message: "Okul bulunamadı",
      });
    }

    await client.query(`
      ALTER TABLE ${schemaName}.students
      ADD COLUMN IF NOT EXISTS class_code VARCHAR(50)
    `);

    await client.query(`
      ALTER TABLE ${schemaName}.students
      ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)
    `);

    const existingStudent = await client.query(
      `
      SELECT *
      FROM ${schemaName}.students
      WHERE student_number = $1
        AND LOWER(COALESCE(school_level, '')) = $2
      LIMIT 1
      `,
      [studentNumber, schoolLevel]
    );

    if (existingStudent.rows.length > 0) {
      await client.query("ROLLBACK");
      return res.status(409).json({
        success: false,
        message: "Bu okul seviyesinde bu öğrenci numarası zaten kayıtlı",
      });
    }

    const result = await client.query(
      `
      INSERT INTO ${schemaName}.students
      (
        student_number,
        full_name,
        class_name,
        class_code,
        school_level
      )
      VALUES ($1, $2, $3, $4, $5)
      RETURNING
        student_id,
        student_number,
        full_name,
        class_name,
        class_code,
        school_level,
        created_at
      `,
      [
        studentNumber,
        fullName,
        className,
        classCode || className,
        schoolLevel,
      ]
    );

    const defaultPassword = STUDENT_PASSWORD;
    const hashedPassword = await bcrypt.hash(defaultPassword, 10);

    const schoolRow = await client.query(
      `SELECT school_id FROM public.schools WHERE school_code = $1 LIMIT 1`,
      [schoolCode]
    );
    const schoolId = schoolRow.rows[0]?.school_id;

    if (schoolId) {
      const nameParts = fullName.split(" ");
      const firstName = nameParts[0] || fullName;
      const lastName = nameParts.slice(1).join(" ") || "";

      // school_level sütunlarını ekle
      await client.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)`);
      await client.query(`ALTER TABLE ${schemaName}.users ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)`);

      // Aynı numara + seviye kombinasyonuna göre kullanıcı ara
      const existingUser = await client.query(
        `SELECT user_id FROM public.users
         WHERE school_id = $1 AND user_role = 'student' AND student_id = $2
           AND LOWER(COALESCE(school_level, '')) = $3
         LIMIT 1`,
        [schoolId, studentNumber, schoolLevel]
      );

      let userId;
      if (existingUser.rows.length > 0) {
        userId = existingUser.rows[0].user_id;
      } else {
        const publicUser = await client.query(
          `INSERT INTO public.users
           (user_name, user_surname, user_role, student_id, user_class, user_class_code, school_id, email, password, plain_password, school_level)
           VALUES ($1, $2, 'student', $3, $4, $5, $6, NULL, $7, $8, $9)
           RETURNING user_id`,
          [firstName, lastName, studentNumber, className, classCode || className, schoolId, hashedPassword, defaultPassword, schoolLevel]
        );
        userId = publicUser.rows[0]?.user_id;
      }

      if (userId) {
        await client.query(
          `INSERT INTO ${schemaName}.users
           (user_id, user_name, user_surname, email, password, user_role, student_id, user_class, user_class_code, school_id, school_level)
           VALUES ($1, $2, $3, '', $4, 'student', $5, $6, $7, $8, $9)
           ON CONFLICT (user_id) DO NOTHING`,
          [userId, firstName, lastName, hashedPassword, studentNumber, className, classCode || className, schoolId, schoolLevel]
        );
      }
    }

    await client.query("COMMIT");

    return res.status(201).json({
      success: true,
      message: "Öğrenci başarıyla eklendi",
      data: result.rows[0],
    });
  } catch (error) {
    await client.query("ROLLBACK");
    next(error);
  } finally {
    client.release();
  }
};

const loginStudent = async (req, res, next) => {
  try {
    const { schoolCode, student_number, password, school_level } = req.body;

    const normalizedLevel = school_level ? String(school_level).trim().toLowerCase() : "";

    if (!schoolCode || !student_number || !password) {
      return res.status(400).json({
        success: false,
        message: "schoolCode, student_number ve password zorunlu",
      });
    }

    const schemaName = `school_${schoolCode}`;

    // 1) Okul kodu geçerli mi?
    const schemaCheck = await pool.query(
      `SELECT schema_name FROM information_schema.schemata WHERE schema_name = $1`,
      [schemaName]
    );
    if (schemaCheck.rows.length === 0) {
      return res.status(401).json({ success: false, message: "Okul bulunamadı" });
    }

    // 2) Students tablosunda bu numara + seviye var mı?
    const studentResult = await pool.query(
      `SELECT student_id, student_number, full_name, class_name, class_code, school_level
       FROM ${schemaName}.students
       WHERE student_number = $1
         AND LOWER(COALESCE(school_level, '')) = $2
       LIMIT 1`,
      [student_number, normalizedLevel]
    );
    if (studentResult.rows.length === 0) {
      return res.status(401).json({
        success: false,
        message: "Öğrenci numarası ve okul seviyesi uyuşmuyor",
      });
    }

    const student = studentResult.rows[0];
    const nameParts = (student.full_name || "").trim().split(/\s+/);
    const firstName = nameParts.shift() || "";
    const lastName = nameParts.join(" ") || "";

    // 3) Okul bilgisi
    const schoolInfo = await pool.query(
      `SELECT school_id, school_code, school_name FROM public.schools WHERE school_code = $1 LIMIT 1`,
      [schoolCode]
    );
    const school = schoolInfo.rows[0] || { school_id: null, school_code: schoolCode, school_name: `School ${schoolCode}` };

    // 4) Sabit öğrenci şifresi: tüm öğrenciler "1234" ile giriş yapar.
    //    (Mail ile şifre alma kaldırıldı; şifreler artık öğrenci bazında tutulmaz.)
    if (String(password) !== STUDENT_PASSWORD) {
      return res.status(401).json({ success: false, message: "Şifre hatalı" });
    }

    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)`);
    await pool.query(`ALTER TABLE ${schemaName}.users ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)`);

    // Token ve rezervasyon FK'si için öğrencinin bir giriş kaydı olmalı:
    // bu seviye için ara, yoksa öğrencinin herhangi bir kaydını kullan, o da
    // yoksa (ör. Excel'den eklenip şifre atanmamış) sabit şifreyle yeni kayıt oluştur.
    let userResult = await pool.query(
      `SELECT u.* FROM ${schemaName}.users u
       WHERE u.user_role = 'student' AND u.student_id = $1
         AND LOWER(COALESCE(u.school_level, '')) = $2
       LIMIT 1`,
      [student_number, normalizedLevel]
    );
    let user = userResult.rows[0] || null;

    if (!user) {
      const anyUserResult = await pool.query(
        `SELECT u.* FROM ${schemaName}.users u
         WHERE u.user_role = 'student' AND u.student_id = $1
         LIMIT 1`,
        [student_number]
      );

      if (anyUserResult.rows.length > 0) {
        // Öğrencinin başka seviyedeki kaydını kullan (token seviyesi istekten gelir)
        user = anyUserResult.rows[0];
      } else {
        // Hiç giriş kaydı yok → sabit şifreyle yeni kayıt oluştur
        const hashed = await bcrypt.hash(STUDENT_PASSWORD, 10);
        const newPublic = await pool.query(
          `INSERT INTO public.users
           (user_name, user_surname, user_role, student_id, user_class, user_class_code, school_id, email, password, plain_password, school_level)
           VALUES ($1, $2, 'student', $3, $4, $5, $6, NULL, $7, $8, $9)
           RETURNING *`,
          [
            firstName, lastName, student_number,
            student.class_name, student.class_code,
            school.school_id, hashed, STUDENT_PASSWORD,
            normalizedLevel,
          ]
        );
        user = newPublic.rows[0];

        await pool.query(
          `INSERT INTO ${schemaName}.users
           (user_id, user_name, user_surname, email, password, user_role, student_id, user_class, user_class_code, school_id, school_level)
           VALUES ($1, $2, $3, '', $4, 'student', $5, $6, $7, $8, $9)
           ON CONFLICT (user_id) DO NOTHING`,
          [
            user.user_id, firstName, lastName,
            hashed, student_number,
            student.class_name, student.class_code,
            school.school_id, normalizedLevel,
          ]
        );
      }
    } else {
      // User bilgilerini students tablosuyla senkronize et
      if (firstName !== user.user_name || lastName !== user.user_surname || student.class_name !== user.user_class) {
        await pool.query(
          `UPDATE ${schemaName}.users SET user_name=$1, user_surname=$2, user_class=$3, school_level=$4 WHERE user_id=$5`,
          [firstName, lastName, student.class_name, normalizedLevel, user.user_id]
        );
        await pool.query(
          `UPDATE public.users SET user_name=$1, user_surname=$2, user_class=$3, school_level=$4 WHERE user_id=$5`,
          [firstName, lastName, student.class_name, normalizedLevel, user.user_id]
        );
        user.user_name = firstName;
        user.user_surname = lastName;
        user.user_class = student.class_name;
      }
    }

    // 6) Token oluştur ve dön
    const token = signStudentToken({
      ...user,
      school_code: school.school_code,
      school_level: normalizedLevel,
    });

    return res.status(200).json({
      success: true,
      message: "Giriş başarılı",
      token,
      data: {
        user_id: user.user_id,
        user_name: user.user_name || firstName,
        user_surname: user.user_surname || lastName,
        user_role: "student",
        student_number: student_number,
        user_class: student.class_name,
        user_class_code: student.class_code,
        school_id: school.school_id,
        school_code: school.school_code,
        school_name: school.school_name,
        school_level: normalizedLevel,
      },
    });
  } catch (error) {
    next(error);
  }
};

const createStudentReservation = async (req, res, next) => {
  const client = await pool.connect();

  try {
    const { book_id } = req.body;
    const { user_id, school_id, school_code } = req.user;

    if (!book_id) {
      return res.status(400).json({
        success: false,
        message: "book_id zorunlu",
      });
    }

    const schemaName = `school_${school_code}`;

    await client.query("BEGIN");

    const bookResult = await client.query(
      `
      SELECT *
      FROM ${schemaName}.book_inventory
      WHERE book_id = $1
      FOR UPDATE
      `,
      [book_id]
    );

    if (bookResult.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({
        success: false,
        message: "Kitap okul envanterinde bulunamadı",
      });
    }

    const inventory = bookResult.rows[0];

    if (inventory.available_quantity <= 0) {
      await client.query("ROLLBACK");
      return res.status(400).json({
        success: false,
        message: "Bu kitap şu anda müsait değil",
      });
    }

    const activeReservation = await client.query(
      `
      SELECT reservation_id
      FROM ${schemaName}.reservations
      WHERE user_id = $1
        AND book_id = $2
        AND status IN ('pending_approval', 'loaned', 'return_requested')
      LIMIT 1
      `,
      [user_id, book_id]
    );

    if (activeReservation.rows.length > 0) {
      await client.query("ROLLBACK");
      return res.status(409).json({
        success: false,
        message: "Bu kitap için zaten aktif talebin veya ödüncün var",
      });
    }

    const publicReservation = await client.query(
      `
      INSERT INTO public.reservations
      (
        user_id,
        book_id,
        school_id,
        reservation_date,
        reservation_status,
        created_at,
        updated_at
      )
      VALUES ($1, $2, $3, CURRENT_TIMESTAMP, 'pending_approval', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      RETURNING *
      `,
      [user_id, book_id, school_id]
    );

    const schoolReservation = await client.query(
      `
      INSERT INTO ${schemaName}.reservations
      (
        user_id,
        book_id,
        school_id,
        status,
        reserved_at
      )
      VALUES ($1, $2, $3, 'pending_approval', CURRENT_TIMESTAMP)
      RETURNING *
      `,
      [user_id, book_id, school_id]
    );

    await client.query(
      `
      UPDATE ${schemaName}.book_inventory
      SET available_quantity = available_quantity - 1
      WHERE book_id = $1
      `,
      [book_id]
    );

    await client.query("COMMIT");

    return res.status(201).json({
      success: true,
      message: "Kitap talebi oluşturuldu",
      data: {
        publicReservation: publicReservation.rows[0],
        schoolReservation: schoolReservation.rows[0],
      },
    });
  } catch (error) {
    await client.query("ROLLBACK");
    next(error);
  } finally {
    client.release();
  }
};

const getMyReservations = async (req, res, next) => {
  try {
    const { user_id, school_code } = req.user;
    const schemaName = `school_${school_code}`;

    const result = await pool.query(
      `
      SELECT
        r.*,
        b.book_name,
        b.book_writer,
        b.publisher,
        b.isbn,
        b.cover_url
      FROM ${schemaName}.reservations r
      JOIN public.books b ON b.book_id = r.book_id
      WHERE r.user_id = $1
      ORDER BY r.reserved_at DESC
      `,
      [user_id]
    );

    return res.status(200).json({
      success: true,
      data: result.rows,
    });
  } catch (error) {
    next(error);
  }
};

const getMyProfile = async (req, res, next) => {
  try {
    const { user_id } = req.user;

    await pool.query(`
      ALTER TABLE public.users
      ADD COLUMN IF NOT EXISTS phone VARCHAR(20)
    `);
    await pool.query(`
      ALTER TABLE public.users
      ADD COLUMN IF NOT EXISTS profile_completed BOOLEAN DEFAULT FALSE
    `);
    await pool.query(`
      ALTER TABLE public.users
      ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)
    `);

    const result = await pool.query(
      `
      SELECT
        user_id,
        user_name,
        user_surname,
        email,
        phone,
        user_role,
        student_id,
        user_class,
        user_class_code,
        school_id,
        profile_completed,
        school_level
      FROM public.users
      WHERE user_id = $1
      LIMIT 1
      `,
      [user_id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Kullanıcı bulunamadı",
      });
    }

    return res.status(200).json({
      success: true,
      data: result.rows[0],
    });
  } catch (error) {
    next(error);
  }
};

const updateMyProfile = async (req, res, next) => {
  try {
    const { user_id } = req.user;
    const { email, phone, password } = req.body;

    await pool.query(`
      ALTER TABLE public.users
      ADD COLUMN IF NOT EXISTS phone VARCHAR(20)
    `);
    await pool.query(`
      ALTER TABLE public.users
      ADD COLUMN IF NOT EXISTS profile_completed BOOLEAN DEFAULT FALSE
    `);

    const existing = await pool.query(
      "SELECT * FROM public.users WHERE user_id = $1",
      [user_id]
    );

    if (existing.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Kullanıcı bulunamadı",
      });
    }

    const current = existing.rows[0];

    const hashedPassword = password
      ? await bcrypt.hash(String(password), 10)
      : current.password;

    const result = await pool.query(
      `
      UPDATE public.users
      SET email = $1,
          phone = $2,
          password = $3,
          profile_completed = TRUE,
          plain_password = COALESCE($5, plain_password)
      WHERE user_id = $4
      RETURNING
        user_id,
        user_name,
        user_surname,
        email,
        phone,
        user_role,
        student_id,
        user_class,
        user_class_code,
        school_id,
        profile_completed
      `,
      [
        email ?? current.email,
        phone ?? current.phone,
        hashedPassword,
        user_id,
        password || null,
      ]
    );

    return res.status(200).json({
      success: true,
      message: "Profil güncellendi",
      data: result.rows[0],
    });
  } catch (error) {
    next(error);
  }
};

const bulkAssignPasswords = async (req, res, next) => {
  const client = await pool.connect();

  try {
    const { schoolCode, school_level, password: rawPassword } = req.body;

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

    const defaultPassword = rawPassword || STUDENT_PASSWORD;
    const schemaName = `school_${schoolCode}`;

    await client.query("BEGIN");

    const schemaCheck = await client.query(
      `SELECT schema_name FROM information_schema.schemata WHERE schema_name = $1`,
      [schemaName]
    );

    if (schemaCheck.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({ success: false, message: "Okul bulunamadı" });
    }

    const schoolResult = await client.query(
      "SELECT school_id, school_code FROM public.schools WHERE school_code = $1 LIMIT 1",
      [schoolCode]
    );

    if (schoolResult.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({ success: false, message: "Okul bulunamadı" });
    }

    const school = schoolResult.rows[0];

    await client.query(`
      ALTER TABLE ${schemaName}.students
      ADD COLUMN IF NOT EXISTS class_code VARCHAR(50)
    `);
    await client.query(`
      ALTER TABLE ${schemaName}.students
      ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)
    `);

    const levelFilter = school_level && String(school_level).trim() !== ""
      ? "WHERE LOWER(COALESCE(school_level, '')) = $1"
      : "";
    const levelParams = levelFilter ? [String(school_level).trim().toLowerCase()] : [];

    const studentsResult = await client.query(
      `SELECT * FROM ${schemaName}.students ${levelFilter} ORDER BY student_id ASC`,
      levelParams
    );

    if (studentsResult.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({
        success: false,
        message: "Öğrenci bulunamadı",
      });
    }

    const hashedPassword = await bcrypt.hash(String(defaultPassword), 10);
    let created = 0;
    let updated = 0;

    for (const student of studentsResult.rows) {
      const nameParts = String(student.full_name || "").trim().split(/\s+/);
      const firstName = nameParts.shift() || "Öğrenci";
      const lastName = nameParts.join(" ") || "-";

      const studentLevel = (student.school_level || "").trim().toLowerCase();

      // school_level sütunlarını ekle
      await client.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)`);
      await client.query(`ALTER TABLE ${schemaName}.users ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)`);

      const existingSchemaUser = await client.query(
        `SELECT local_user_id, user_id FROM ${schemaName}.users
         WHERE user_role = 'student' AND student_id = $1
           AND LOWER(COALESCE(school_level, '')) = $2
         LIMIT 1`,
        [student.student_number, studentLevel]
      );

      if (existingSchemaUser.rows.length > 0) {
        const uid = existingSchemaUser.rows[0].user_id;
        await client.query(
          `UPDATE ${schemaName}.users SET password = $1 WHERE user_id = $2`,
          [hashedPassword, uid]
        );
        await client.query(
          `UPDATE public.users SET password = $1, plain_password = $3 WHERE user_id = $2`,
          [hashedPassword, uid, String(defaultPassword)]
        );
        updated++;
      } else {
        const existingPublicUser = await client.query(
          `SELECT user_id FROM public.users
           WHERE school_id = $1 AND user_role = 'student' AND student_id = $2
             AND LOWER(COALESCE(school_level, '')) = $3
           LIMIT 1`,
          [school.school_id, student.student_number, studentLevel]
        );

        let userId;

        if (existingPublicUser.rows.length > 0) {
          userId = existingPublicUser.rows[0].user_id;
          await client.query(
            `UPDATE public.users SET password = $1, plain_password = $3 WHERE user_id = $2`,
            [hashedPassword, userId, String(defaultPassword)]
          );
        } else {
          const ins = await client.query(
            `INSERT INTO public.users
             (user_name, user_surname, user_role, student_id, user_class, user_class_code, school_id, email, password, plain_password, school_level)
             VALUES ($1, $2, 'student', $3, $4, $5, $6, NULL, $7, $8, $9)
             RETURNING user_id`,
            [
              firstName,
              lastName,
              student.student_number,
              student.class_name || null,
              student.class_code || null,
              school.school_id,
              hashedPassword,
              String(defaultPassword),
              studentLevel,
            ]
          );
          userId = ins.rows[0].user_id;
        }

        await client.query(
          `INSERT INTO ${schemaName}.users
           (user_id, user_name, user_surname, email, password, user_role, student_id, user_class, user_class_code, school_id, school_level)
           VALUES ($1, $2, $3, '', $4, 'student', $5, $6, $7, $8, $9)`,
          [
            userId,
            firstName,
            lastName,
            hashedPassword,
            student.student_number,
            student.class_name || null,
            student.class_code || null,
            school.school_id,
            studentLevel,
          ]
        );
        created++;
      }
    }

    await client.query("COMMIT");

    return res.status(200).json({
      success: true,
      message: `${created + updated} öğrenciye şifre atandı (${created} yeni, ${updated} güncellendi)`,
      data: {
        total: studentsResult.rows.length,
        created,
        updated,
        defaultPassword,
      },
    });
  } catch (error) {
    await client.query("ROLLBACK");
    next(error);
  } finally {
    client.release();
  }
};

const deleteStudent = async (req, res, next) => {
  const client = await pool.connect();

  try {
    const { schoolCode, student_number, school_level } = req.query;

    if (!schoolCode || !student_number) {
      return res.status(400).json({
        success: false,
        message: "schoolCode ve student_number zorunlu",
      });
    }

    const schemaName = `school_${schoolCode}`;

    const schemaCheck = await client.query(
      `SELECT schema_name FROM information_schema.schemata WHERE schema_name = $1`,
      [schemaName]
    );

    if (schemaCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Okul bulunamadı",
      });
    }

    await client.query("BEGIN");

    const levelFilter = school_level && String(school_level).trim() !== ""
      ? "AND LOWER(COALESCE(school_level, '')) = $2"
      : "";
    const params = [student_number];
    if (levelFilter) params.push(String(school_level).trim().toLowerCase());

    const studentResult = await client.query(
      `SELECT student_id FROM ${schemaName}.students WHERE student_number = $1 ${levelFilter} LIMIT 1`,
      params
    );

    if (studentResult.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({
        success: false,
        message: "Öğrenci bulunamadı",
      });
    }

    // school_level sütunlarını ekle (yoksa)
    await client.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)`);
    await client.query(`ALTER TABLE ${schemaName}.users ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)`);

    // Aktif rezervasyonları (loaned) otomatik iade et ve stok güncelle
    const studentId = studentResult.rows[0].student_id;
    const loanedReservations = await client.query(
      `SELECT reservation_id, book_id FROM ${schemaName}.reservations
       WHERE student_local_id = $1 AND status = 'loaned'`,
      [studentId]
    );

    for (const loan of loanedReservations.rows) {
      // Okul schema'daki rezervasyonu iade et
      await client.query(
        `UPDATE ${schemaName}.reservations
         SET status = 'returned', returned_at = CURRENT_TIMESTAMP
         WHERE reservation_id = $1`,
        [loan.reservation_id]
      );

      // Kitap stokunu geri artır
      await client.query(
        `UPDATE ${schemaName}.book_inventory
         SET available_quantity = available_quantity + 1
         WHERE book_id = $1`,
        [loan.book_id]
      );

      // Public reservations tablosunu da güncelle
      await client.query(
        `UPDATE public.reservations
         SET reservation_status = 'returned', updated_at = CURRENT_TIMESTAMP
         WHERE reservation_id IN (
           SELECT public_reservation_id FROM ${schemaName}.reservations
           WHERE reservation_id = $1 AND public_reservation_id IS NOT NULL
         )`,
        [loan.reservation_id]
      );
    }

    // Önce users tablosundan sil (school_level ile filtrele)
    const schemaUserResult = await client.query(
      `SELECT user_id FROM ${schemaName}.users WHERE user_role = 'student' AND student_id = $1 ${levelFilter.replace('school_level', 'school_level')} LIMIT 1`,
      params
    );

    if (schemaUserResult.rows.length > 0) {
      const uid = schemaUserResult.rows[0].user_id;
      await client.query(
        `DELETE FROM ${schemaName}.users WHERE user_id = $1`,
        [uid]
      );
      await client.query(
        `DELETE FROM public.users WHERE user_id = $1`,
        [uid]
      );
    }

    // Sonra students tablosundan sil
    await client.query(
      `DELETE FROM ${schemaName}.students WHERE student_number = $1 ${levelFilter}`,
      params
    );

    await client.query("COMMIT");

    return res.status(200).json({
      success: true,
      message: "Öğrenci silindi",
    });
  } catch (error) {
    await client.query("ROLLBACK");
    next(error);
  } finally {
    client.release();
  }
};

// Öğrencinin KENDİ hesabını silmesi (Google Play hesap silme politikası)
const deleteMyAccount = async (req, res, next) => {
  const client = await pool.connect();

  try {
    const { user_id, school_code, student_number, school_level } = req.user;

    if (!user_id || !school_code) {
      return res.status(400).json({
        success: false,
        message: "Hesap bilgisi eksik",
      });
    }

    const schemaName = `school_${school_code}`;

    const schemaCheck = await client.query(
      `SELECT schema_name FROM information_schema.schemata WHERE schema_name = $1`,
      [schemaName]
    );

    if (schemaCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Okul bulunamadı",
      });
    }

    await client.query("BEGIN");

    // Aktif (loaned) ödünçleri otomatik iade et ve stoku geri ver
    const loanedReservations = await client.query(
      `SELECT reservation_id, book_id FROM ${schemaName}.reservations
       WHERE status = 'loaned' AND user_id = $1`,
      [user_id]
    );

    for (const loan of loanedReservations.rows) {
      await client.query(
        `UPDATE ${schemaName}.reservations
         SET status = 'returned', returned_at = CURRENT_TIMESTAMP
         WHERE reservation_id = $1`,
        [loan.reservation_id]
      );
      await client.query(
        `UPDATE ${schemaName}.book_inventory
         SET available_quantity = available_quantity + 1
         WHERE book_id = $1`,
        [loan.book_id]
      );
      await client.query(
        `UPDATE public.reservations
         SET reservation_status = 'returned', updated_at = CURRENT_TIMESTAMP
         WHERE reservation_id IN (
           SELECT public_reservation_id FROM ${schemaName}.reservations
           WHERE reservation_id = $1 AND public_reservation_id IS NOT NULL
         )`,
        [loan.reservation_id]
      );
    }

    // Giriş hesabını sil (okul şeması + public)
    await client.query(`DELETE FROM ${schemaName}.users WHERE user_id = $1`, [
      user_id,
    ]);
    await client.query(`DELETE FROM public.users WHERE user_id = $1`, [user_id]);

    // Roster kaydını sil (varsa)
    if (student_number) {
      const levelFilter =
        school_level && String(school_level).trim() !== ""
          ? "AND LOWER(COALESCE(school_level, '')) = $2"
          : "";
      const studentParams = [String(student_number)];
      if (levelFilter) {
        studentParams.push(String(school_level).trim().toLowerCase());
      }

      await client.query(
        `DELETE FROM ${schemaName}.students WHERE student_number = $1 ${levelFilter}`,
        studentParams
      );
    }

    await client.query("COMMIT");

    return res.status(200).json({
      success: true,
      message: "Hesabınız ve kişisel verileriniz kalıcı olarak silindi",
    });
  } catch (error) {
    await client.query("ROLLBACK");
    next(error);
  } finally {
    client.release();
  }
};

// ─── İlk giriş / şifre alma: numara okulda varsa e-postaya şifre gönder ───
const requestStudentPassword = async (req, res, next) => {
  const client = await pool.connect();

  try {
    const { schoolCode, student_number, school_level, email } = req.body;

    if (!schoolCode || !student_number || !school_level || !email) {
      return res.status(400).json({
        success: false,
        message: "schoolCode, student_number, school_level ve email zorunlu",
      });
    }

    if (!/^\d+$/.test(String(schoolCode))) {
      return res.status(400).json({ success: false, message: "Geçersiz okul kodu" });
    }

    const emailInput = String(email).trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailInput)) {
      return res.status(400).json({ success: false, message: "Geçerli bir e-posta adresi girin" });
    }

    const studentNumber = String(student_number).trim();
    const normalizedLevel = String(school_level).trim().toLowerCase();
    const schemaName = `school_${schoolCode}`;

    await client.query("BEGIN");

    const schemaCheck = await client.query(
      `SELECT schema_name FROM information_schema.schemata WHERE schema_name = $1`,
      [schemaName]
    );
    if (schemaCheck.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({ success: false, message: "Okul bulunamadı" });
    }

    await client.query(`ALTER TABLE ${schemaName}.students ADD COLUMN IF NOT EXISTS class_code VARCHAR(50)`);
    await client.query(`ALTER TABLE ${schemaName}.students ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)`);

    // Öğrenci listede var mı?
    const studentRes = await client.query(
      `SELECT student_number, full_name, class_name, class_code, school_level
       FROM ${schemaName}.students
       WHERE student_number = $1 AND LOWER(COALESCE(school_level, '')) = $2
       LIMIT 1`,
      [studentNumber, normalizedLevel]
    );
    if (studentRes.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({
        success: false,
        message: "Bu okul seviyesinde bu numarada öğrenci bulunamadı",
      });
    }

    const student = studentRes.rows[0];
    const nameParts = String(student.full_name || "").trim().split(/\s+/);
    const firstName = nameParts.shift() || "Öğrenci";
    const lastName = nameParts.join(" ") || "-";

    const schoolRow = await client.query(
      `SELECT school_id, school_name FROM public.schools WHERE school_code = $1 LIMIT 1`,
      [schoolCode]
    );
    const schoolId = schoolRow.rows[0]?.school_id;
    const schoolName = schoolRow.rows[0]?.school_name || `Okul ${schoolCode}`;
    if (!schoolId) {
      await client.query("ROLLBACK");
      return res.status(404).json({ success: false, message: "Okul kaydı bulunamadı" });
    }

    await client.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)`);
    await client.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS phone VARCHAR(20)`);
    await client.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS profile_completed BOOLEAN DEFAULT FALSE`);
    await client.query(`ALTER TABLE ${schemaName}.users ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)`);

    // Mevcut giriş hesabı (public.users) var mı?
    const pubUserRes = await client.query(
      `SELECT user_id, email FROM public.users
       WHERE school_id = $1 AND user_role = 'student' AND student_id = $2
         AND LOWER(COALESCE(school_level, '')) = $3
       LIMIT 1`,
      [schoolId, studentNumber, normalizedLevel]
    );

    // Hesap ele geçirme koruması: kayıtlı e-posta varsa ve girilen farklıysa,
    // şifreyi yine SADECE kayıtlı adrese gönder (başkası başkasının hesabını alamaz).
    const registeredEmail = pubUserRes.rows[0]?.email
      ? String(pubUserRes.rows[0].email).trim().toLowerCase()
      : "";
    const targetEmail =
      registeredEmail && registeredEmail !== emailInput ? registeredEmail : emailInput;

    const newPassword = generateStudentPassword(6);
    const hashedPassword = await bcrypt.hash(newPassword, 10);

    let userId;
    if (pubUserRes.rows.length > 0) {
      userId = pubUserRes.rows[0].user_id;
      await client.query(
        `UPDATE public.users
         SET password = $1, plain_password = $2, email = $3, profile_completed = TRUE
         WHERE user_id = $4`,
        [hashedPassword, newPassword, targetEmail, userId]
      );
    } else {
      const ins = await client.query(
        `INSERT INTO public.users
         (user_name, user_surname, user_role, student_id, user_class, user_class_code, school_id, email, password, plain_password, school_level, profile_completed)
         VALUES ($1, $2, 'student', $3, $4, $5, $6, $7, $8, $9, $10, TRUE)
         RETURNING user_id`,
        [
          firstName, lastName, studentNumber,
          student.class_name, student.class_code || student.class_name,
          schoolId, targetEmail, hashedPassword, newPassword, normalizedLevel,
        ]
      );
      userId = ins.rows[0].user_id;
    }

    // schema.users aynasını oluştur/güncelle (profil e-postası public.users'ta tutulur)
    const schemaUserRes = await client.query(
      `SELECT user_id FROM ${schemaName}.users WHERE user_id = $1 LIMIT 1`,
      [userId]
    );
    if (schemaUserRes.rows.length > 0) {
      await client.query(
        `UPDATE ${schemaName}.users SET password = $1 WHERE user_id = $2`,
        [hashedPassword, userId]
      );
    } else {
      await client.query(
        `INSERT INTO ${schemaName}.users
         (user_id, user_name, user_surname, email, password, user_role, student_id, user_class, user_class_code, school_id, school_level)
         VALUES ($1, $2, $3, '', $4, 'student', $5, $6, $7, $8, $9)`,
        [
          userId, firstName, lastName, hashedPassword, studentNumber,
          student.class_name, student.class_code || student.class_name,
          schoolId, normalizedLevel,
        ]
      );
    }

    // E-postayı gönder — başarısız olursa rollback (öğrenci tekrar deneyebilsin)
    try {
      await sendStudentPasswordEmail({
        to: targetEmail,
        firstName,
        schoolName,
        password: newPassword,
      });
    } catch (mailErr) {
      await client.query("ROLLBACK");
      console.error("Şifre e-postası gönderilemedi:", mailErr.message);
      return res.status(502).json({
        success: false,
        message: "E-posta gönderilemedi, lütfen biraz sonra tekrar deneyin",
      });
    }

    await client.query("COMMIT");

    return res.status(200).json({
      success: true,
      message: "Şifre e-posta adresine gönderildi",
      email: maskEmail(targetEmail),
    });
  } catch (error) {
    await client.query("ROLLBACK");
    next(error);
  } finally {
    client.release();
  }
};

module.exports = {
  parseStudentsFromWorkbook,
  upsertStudentWithMerge,
  registerStudent,
  loginStudent,
  requestStudentPassword,
  createStudentReservation,
  getMyReservations,
  getStudents,
  importStudentsFromExcel,
  createManualStudent,
  getMyProfile,
  updateMyProfile,
  bulkAssignPasswords,
  deleteStudent,
  deleteMyAccount,
};
