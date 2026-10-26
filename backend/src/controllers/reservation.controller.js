const pool = require("../config/db");

function normalizeIsbn(value = "") {
  return String(value).replace(/[^0-9Xx]/g, "").toUpperCase().trim();
}

function isNumericSchoolCode(schoolCode) {
  return /^\d+$/.test(String(schoolCode));
}

async function ensureStudentColumns(client, schemaName) {
  await client.query(`
    ALTER TABLE ${schemaName}.students
    ADD COLUMN IF NOT EXISTS class_code VARCHAR(50)
  `);

  await client.query(`
    ALTER TABLE ${schemaName}.students
    ADD COLUMN IF NOT EXISTS school_level VARCHAR(50)
  `);
}

async function ensureSchoolReservationColumns(client, schemaName) {
  await client.query(`
    ALTER TABLE ${schemaName}.reservations
    ADD COLUMN IF NOT EXISTS student_number VARCHAR(50)
  `);

  await client.query(`
    ALTER TABLE ${schemaName}.reservations
    ADD COLUMN IF NOT EXISTS public_reservation_id INTEGER
  `);
}

async function getPublicReservationColumns(client) {
  const result = await client.query(
    `
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'reservations'
    `
  );

  return new Set(result.rows.map((row) => row.column_name));
}

const getAllReservations = async (req, res, next) => {
  try {
    const {
      schoolCode,
      status,
      studentNumber,
      school_level,
      startDate,
      endDate,
    } = req.query;

    if (!schoolCode) {
      const params = [];
      const filters = [];

      if (status && String(status).trim() !== "") {
        params.push(String(status).trim().toLowerCase());
        filters.push(`LOWER(COALESCE(r.reservation_status, '')) = $${params.length}`);
      }

      if (startDate && String(startDate).trim() !== "") {
        params.push(String(startDate).trim());
        filters.push(`r.reservation_date >= $${params.length}::date`);
      }

      if (endDate && String(endDate).trim() !== "") {
        params.push(String(endDate).trim());
        filters.push(`r.reservation_date < ($${params.length}::date + INTERVAL '1 day')`);
      }

      const statusFilter = filters.length > 0 ? `WHERE ${filters.join(" AND ")}` : "";

      const result = await pool.query(
        `
        SELECT
          r.reservation_id,
          r.user_id,
          r.book_id,
          r.school_id,
          r.reservation_status AS status,
          r.reservation_date,
          r.created_at,
          r.updated_at,
          u.user_name || ' ' || u.user_surname AS student_name,
          u.student_id AS student_number,
          u.user_class AS class_name,
          u.user_class_code AS class_code,
          b.book_name,
          b.isbn
        FROM public.reservations r
        LEFT JOIN public.users u ON u.user_id = r.user_id
        JOIN public.books b ON b.book_id = r.book_id
        ${statusFilter}
        ORDER BY r.reservation_id DESC
        `,
        params
      );

      return res.status(200).json({
        success: true,
        data: result.rows,
      });
    }

    if (!isNumericSchoolCode(schoolCode)) {
      return res.status(400).json({
        success: false,
        message: "Geçersiz okul kodu",
      });
    }

    const schoolResult = await pool.query(
      "SELECT * FROM public.schools WHERE school_code = $1 LIMIT 1",
      [schoolCode]
    );

    if (schoolResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Okul bulunamadı",
      });
    }

    const schemaName = `school_${schoolCode}`;

    await ensureStudentColumns(pool, schemaName);
    await ensureSchoolReservationColumns(pool, schemaName);

    const params = [];
    const filters = [];

    if (status && String(status).trim() !== "") {
      params.push(String(status).trim().toLowerCase());
      filters.push(`LOWER(COALESCE(sr.status, '')) = $${params.length}`);
    }

    if (studentNumber && String(studentNumber).trim() !== "") {
      params.push(String(studentNumber).trim());
      filters.push(`COALESCE(sr.student_number, st.student_number) = $${params.length}`);
    }

    // Öğrenciyi tek başına numara belirlemez: aynı numara farklı seviyelerde
    // (ör. ortaokul 10 ve lise 10) başka öğrencilere ait olabilir.
    // Kimlik numara + seviye çiftidir.
    if (school_level && String(school_level).trim() !== "") {
      params.push(String(school_level).trim().toLowerCase());
      filters.push(
        `(
          st.school_level IS NULL
          OR LOWER(COALESCE(st.school_level, '')) = $${params.length}
        )`
      );
    }

    if (startDate && String(startDate).trim() !== "") {
      params.push(String(startDate).trim());
      filters.push(`sr.reserved_at >= $${params.length}::date`);
    }

    if (endDate && String(endDate).trim() !== "") {
      params.push(String(endDate).trim());
      filters.push(`sr.reserved_at < ($${params.length}::date + INTERVAL '1 day')`);
    }

    const statusFilter = filters.length > 0 ? `WHERE ${filters.join(" AND ")}` : "";

    const result = await pool.query(
      `
      SELECT DISTINCT ON (sr.reservation_id)
        COALESCE(sr.public_reservation_id, sr.reservation_id) AS reservation_id,
        sr.book_id,
        b.book_name,
        b.isbn,
        st.full_name AS student_name,
        COALESCE(sr.student_number, st.student_number) AS student_number,
        st.class_name,
        st.class_code,
        st.school_level,
        sr.reserved_at,
        sr.due_date,
        sr.returned_at,
        sr.status
      FROM ${schemaName}.reservations sr
      JOIN public.books b ON b.book_id = sr.book_id
      LEFT JOIN ${schemaName}.students st
        ON sr.student_local_id IS NOT NULL
        AND st.student_id = sr.student_local_id
      ${statusFilter}
      ORDER BY sr.reservation_id DESC
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

const getReservationById = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { schoolCode } = req.query;

    if (!schoolCode) {
      const result = await pool.query(
        `
        SELECT
          r.*,
          r.reservation_status AS status,
          b.book_name,
          b.isbn
        FROM public.reservations r
        JOIN public.books b ON b.book_id = r.book_id
        WHERE r.reservation_id = $1
        LIMIT 1
        `,
        [id]
      );

      if (result.rows.length === 0) {
        return res.status(404).json({
          success: false,
          message: "Ödünç kaydı bulunamadı",
        });
      }

      return res.status(200).json({
        success: true,
        data: result.rows[0],
      });
    }

    if (!isNumericSchoolCode(schoolCode)) {
      return res.status(400).json({
        success: false,
        message: "Geçersiz okul kodu",
      });
    }

    const schemaName = `school_${schoolCode}`;

    const schoolResult = await pool.query(
      "SELECT * FROM public.schools WHERE school_code = $1 LIMIT 1",
      [schoolCode]
    );

    if (schoolResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Okul bulunamadı",
      });
    }

    await ensureStudentColumns(pool, schemaName);
    await ensureSchoolReservationColumns(pool, schemaName);

    const result = await pool.query(
      `
      SELECT
        COALESCE(pr.reservation_id, sr.public_reservation_id, sr.reservation_id) AS reservation_id,
        sr.user_id,
        sr.student_local_id,
        sr.book_id,
        sr.school_id,
        sr.status,
        sr.reserved_at,
        sr.due_date,
        sr.returned_at,
        COALESCE(sr.student_number, st.student_number) AS student_number,
        st.full_name AS student_name,
        st.class_name,
        st.class_code,
        st.school_level,
        b.book_name,
        b.book_writer,
        b.publisher,
        b.isbn
      FROM ${schemaName}.reservations sr
      LEFT JOIN ${schemaName}.students st
        ON sr.student_local_id IS NOT NULL
        AND st.student_id = sr.student_local_id
      JOIN public.books b ON b.book_id = sr.book_id
      WHERE sr.reservation_id = $1
         OR sr.public_reservation_id = $1
      LIMIT 1
      `,
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Ödünç kaydı bulunamadı",
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

const createReservation = async (req, res, next) => {
  const client = await pool.connect();

  try {
    const { user_id, book_id, school_id, schoolCode } = req.body;

    if (!user_id || !book_id || (!school_id && !schoolCode)) {
      return res.status(400).json({
        success: false,
        message: "user_id, book_id ve school_id veya schoolCode zorunlu",
      });
    }

    if (schoolCode && !isNumericSchoolCode(schoolCode)) {
      return res.status(400).json({
        success: false,
        message: "Geçersiz okul kodu",
      });
    }

    await client.query("BEGIN");

    const schoolResult = await client.query(
      `
      SELECT *
      FROM public.schools
      WHERE school_id = COALESCE($1::int, school_id)
        AND ($2::text IS NULL OR school_code = $2)
      LIMIT 1
      `,
      [school_id || null, schoolCode || null]
    );

    if (schoolResult.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({
        success: false,
        message: "Okul bulunamadı",
      });
    }

    const school = schoolResult.rows[0];
    const schemaName = `school_${school.school_code}`;

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
      [user_id, book_id, school.school_id]
    );

    await ensureSchoolReservationColumns(client, schemaName);

    await client.query(
      `
      INSERT INTO ${schemaName}.reservations
      (
        user_id,
        public_reservation_id,
        book_id,
        school_id,
        status,
        reserved_at
      )
      VALUES ($1, $2, $3, $4, 'pending_approval', CURRENT_TIMESTAMP)
      `,
      [user_id, publicReservation.rows[0].reservation_id, book_id, school.school_id]
    );

    await client.query("COMMIT");

    return res.status(201).json({
      success: true,
      message: "Rezervasyon oluşturuldu",
      data: publicReservation.rows[0],
    });
  } catch (error) {
    await client.query("ROLLBACK");
    next(error);
  } finally {
    client.release();
  }
};

const loanBookByStudent = async (req, res, next) => {
  const client = await pool.connect();

  try {
    const { schoolCode, isbn, student_number, school_level, due_date } = req.body;

    if (!schoolCode || !isbn || !student_number) {
      return res.status(400).json({
        success: false,
        message: "schoolCode, isbn ve student_number zorunlu",
      });
    }

    if (!isNumericSchoolCode(schoolCode)) {
      return res.status(400).json({
        success: false,
        message: "Geçersiz okul kodu",
      });
    }

    const normalizedIsbn = normalizeIsbn(isbn);
    const normalizedLevel =
      school_level && String(school_level).trim() !== ""
        ? String(school_level).trim().toLowerCase()
        : null;
    const schemaName = `school_${schoolCode}`;

    await client.query("BEGIN");

    const schoolResult = await client.query(
      "SELECT * FROM public.schools WHERE school_code = $1 LIMIT 1",
      [schoolCode]
    );

    if (schoolResult.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({
        success: false,
        message: "Okul bulunamadı",
      });
    }

    const school = schoolResult.rows[0];

    await ensureStudentColumns(client, schemaName);
    await ensureSchoolReservationColumns(client, schemaName);

    const studentResult = await client.query(
      `
      SELECT *
      FROM ${schemaName}.students
      WHERE student_number = $1
        AND (
          $2::text IS NULL
          OR school_level IS NULL
          OR LOWER(COALESCE(school_level, '')) = $2
        )
      LIMIT 1
      `,
      [String(student_number), normalizedLevel]
    );

    if (studentResult.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({
        success: false,
        message: "Öğrenci bulunamadı",
      });
    }

    const student = studentResult.rows[0];

    let userResult = await client.query(
      `
      SELECT *
      FROM public.users
      WHERE school_id = $1
        AND user_role = 'student'
        AND student_id = $2
      LIMIT 1
      `,
      [school.school_id, String(student_number)]
    );

    if (userResult.rows.length === 0) {
      const nameParts = String(student.full_name || "").trim().split(/\s+/);
      const fallbackName = nameParts.shift() || "Öğrenci";
      const fallbackSurname = nameParts.join(" ") || "-";
      const fallbackEmail = `student-${school.school_code}-${String(student_number).trim()}@no-email.local`;

      userResult = await client.query(
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
          password
        )
        VALUES ($1, $2, 'student', $3, $4, $5, $6, $7, NULL)
        RETURNING *
        `,
        [
          fallbackName,
          fallbackSurname,
          String(student_number),
          student.class_name || null,
          student.class_code || null,
          school.school_id,
          fallbackEmail,
        ]
      );

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
          school_id
        )
        VALUES ($1, $2, $3, $4, NULL, 'student', $5, $6, $7, $8)
        ON CONFLICT (user_id) DO UPDATE SET
          user_name = EXCLUDED.user_name,
          user_surname = EXCLUDED.user_surname,
          email = EXCLUDED.email,
          student_id = EXCLUDED.student_id,
          user_class = EXCLUDED.user_class,
          user_class_code = EXCLUDED.user_class_code,
          school_id = EXCLUDED.school_id
        `,
        [
          userResult.rows[0].user_id,
          userResult.rows[0].user_name,
          userResult.rows[0].user_surname,
          fallbackEmail,
          String(student_number),
          student.class_name || null,
          student.class_code || null,
          school.school_id,
        ]
      );
    }

    const userId = userResult.rows[0].user_id;

    const bookResult = await client.query(
      `
      SELECT
        b.*,
        bi.inventory_id,
        bi.quantity,
        bi.available_quantity
      FROM public.books b
      JOIN ${schemaName}.book_inventory bi ON bi.book_id = b.book_id
      WHERE UPPER(regexp_replace(COALESCE(b.isbn, ''), '[^0-9Xx]', '', 'g')) = $1
      ORDER BY b.book_id ASC
      LIMIT 1
      FOR UPDATE OF bi
      `,
      [normalizedIsbn]
    );

    if (bookResult.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({
        success: false,
        message: "Kitap bu okulun envanterinde bulunamadı",
      });
    }

    const book = bookResult.rows[0];

    if (Number(book.available_quantity) <= 0) {
      await client.query("ROLLBACK");
      return res.status(400).json({
        success: false,
        message: "Bu kitabın müsait adedi yok",
      });
    }

    const activeLoan = await client.query(
      `
      SELECT reservation_id
      FROM ${schemaName}.reservations
      WHERE book_id = $1
        AND (
          user_id = $2
          OR student_number = $3
          OR student_local_id = $4
        )
        AND status IN ('pending_approval', 'reserved', 'loaned', 'return_requested')
      LIMIT 1
      `,
      [book.book_id, userId, String(student_number), student.student_id]
    );

    if (activeLoan.rows.length > 0) {
      await client.query("ROLLBACK");
      return res.status(409).json({
        success: false,
        message: "Bu öğrenci için bu kitap zaten aktif görünüyor",
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
      VALUES ($1, $2, $3, CURRENT_TIMESTAMP, 'loaned', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      RETURNING *
      `,
      [userId, book.book_id, school.school_id]
    );

    const schoolReservation = await client.query(
      `
      INSERT INTO ${schemaName}.reservations
      (
        user_id,
        student_local_id,
        student_number,
        public_reservation_id,
        book_id,
        school_id,
        status,
        reserved_at,
        due_date
      )
      VALUES
      (
        $1,
        $2,
        $3,
        $4,
        $5,
        $6,
        'loaned',
        CURRENT_TIMESTAMP,
        COALESCE($7::timestamp, CURRENT_TIMESTAMP + INTERVAL '15 days')
      )
      RETURNING *
      `,
      [
        userId,
        student.student_id,
        String(student_number),
        publicReservation.rows[0].reservation_id,
        book.book_id,
        school.school_id,
        due_date || null,
      ]
    );

    await client.query(
      `
      UPDATE ${schemaName}.book_inventory
      SET available_quantity = available_quantity - 1
      WHERE book_id = $1
      `,
      [book.book_id]
    );

    await client.query("COMMIT");

    return res.status(201).json({
      success: true,
      message: "Kitap öğrenciye verildi",
      data: {
        student: {
          student_number: student.student_number,
          full_name: student.full_name,
          class_name: student.class_name,
          class_code: student.class_code,
          school_level: student.school_level,
        },
        book: {
          book_id: book.book_id,
          title: book.book_name,
          book_name: book.book_name,
          isbn: book.isbn,
        },
        reservation: {
          reservation_id: publicReservation.rows[0].reservation_id,
          school_reservation_id: schoolReservation.rows[0].reservation_id,
          status: schoolReservation.rows[0].status,
          due_date: schoolReservation.rows[0].due_date,
        },
      },
    });
  } catch (error) {
    await client.query("ROLLBACK");
    next(error);
  } finally {
    client.release();
  }
};

const updateReservationStatus = async (req, res, next, targetStatus, message) => {
  const client = await pool.connect();

  try {
    const { id } = req.params;

    await client.query("BEGIN");

    const reservationResult = await client.query(
      `
      SELECT
        r.*,
        s.school_code
      FROM public.reservations r
      JOIN public.schools s ON s.school_id = r.school_id
      WHERE r.reservation_id = $1
      FOR UPDATE OF r
      `,
      [id]
    );

    if (reservationResult.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({
        success: false,
        message: "Rezervasyon bulunamadı",
      });
    }

    const reservation = reservationResult.rows[0];
    const schemaName = `school_${reservation.school_code}`;

    await ensureSchoolReservationColumns(client, schemaName);

    const updatedPublic = await client.query(
      `
      UPDATE public.reservations
      SET reservation_status = $1,
          updated_at = CURRENT_TIMESTAMP
      WHERE reservation_id = $2
      RETURNING *
      `,
      [targetStatus, id]
    );

    await client.query(
      `
      UPDATE ${schemaName}.reservations
      SET status = $1
      WHERE reservation_id = (
        SELECT reservation_id FROM ${schemaName}.reservations
        WHERE public_reservation_id = $2
           OR (
            user_id = $3
            AND book_id = $4
            AND school_id = $5
            AND status NOT IN ('returned', 'rejected')
          )
        ORDER BY reservation_id DESC
        LIMIT 1
      )
      `,
      [
        targetStatus,
        id,
        reservation.user_id,
        reservation.book_id,
        reservation.school_id,
      ]
    );

    await client.query("COMMIT");

    return res.status(200).json({
      success: true,
      message,
      data: updatedPublic.rows[0],
    });
  } catch (error) {
    await client.query("ROLLBACK");
    next(error);
  } finally {
    client.release();
  }
};

const loanReservation = (req, res, next) =>
  updateReservationStatus(req, res, next, "loaned", "Kitap ödünç verildi");

const rejectReservation = (req, res, next) =>
  updateReservationStatus(req, res, next, "rejected", "Rezervasyon reddedildi");

const returnReservation = async (req, res, next) => {
  const client = await pool.connect();

  try {
    const { id } = req.params;

    if (!id) {
      return res.status(400).json({
        success: false,
        message: "reservation id zorunlu",
      });
    }

    await client.query("BEGIN");

    const publicReservationResult = await client.query(
      `
      SELECT
        r.*,
        s.school_code
      FROM public.reservations r
      JOIN public.schools s ON s.school_id = r.school_id
      WHERE r.reservation_id = $1
      FOR UPDATE OF r
      `,
      [id]
    );

    if (publicReservationResult.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({
        success: false,
        message: "Ödünç kaydı bulunamadı",
      });
    }

    const publicReservation = publicReservationResult.rows[0];
    const schemaName = `school_${publicReservation.school_code}`;

    await ensureSchoolReservationColumns(client, schemaName);

    const schoolReservationResult = await client.query(
      `
      SELECT *
      FROM ${schemaName}.reservations
      WHERE public_reservation_id = $1
         OR (
          user_id = $2
          AND book_id = $3
          AND school_id = $4
          AND status = 'loaned'
        )
      ORDER BY reservation_id DESC
      LIMIT 1
      FOR UPDATE
      `,
      [
        publicReservation.reservation_id,
        publicReservation.user_id,
        publicReservation.book_id,
        publicReservation.school_id,
      ]
    );

    if (schoolReservationResult.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({
        success: false,
        message: "Okul ödünç kaydı bulunamadı",
      });
    }

    const schoolReservation = schoolReservationResult.rows[0];

    if (schoolReservation.status === "returned") {
      await client.query("ROLLBACK");
      return res.status(400).json({
        success: false,
        message: "Bu kitap zaten iade edilmiş",
      });
    }

    if (schoolReservation.status !== "loaned") {
      await client.query("ROLLBACK");
      return res.status(400).json({
        success: false,
        message: "Sadece ödünç verilmiş kitaplar iade alınabilir",
      });
    }

    const publicColumns = await getPublicReservationColumns(client);
    const publicSetClauses = ["reservation_status = 'returned'"];

    if (publicColumns.has("returned_at")) {
      publicSetClauses.push("returned_at = CURRENT_TIMESTAMP");
    }

    if (publicColumns.has("returned_date")) {
      publicSetClauses.push("returned_date = CURRENT_TIMESTAMP");
    }

    if (publicColumns.has("updated_at")) {
      publicSetClauses.push("updated_at = CURRENT_TIMESTAMP");
    }

    const updatedPublicReservation = await client.query(
      `
      UPDATE public.reservations
      SET ${publicSetClauses.join(", ")}
      WHERE reservation_id = $1
      RETURNING *
      `,
      [publicReservation.reservation_id]
    );

    const updatedSchoolReservation = await client.query(
      `
      UPDATE ${schemaName}.reservations
      SET status = 'returned',
          returned_at = CURRENT_TIMESTAMP
      WHERE reservation_id = $1
      RETURNING *
      `,
      [schoolReservation.reservation_id]
    );

    await client.query(
      `
      UPDATE ${schemaName}.book_inventory
      SET available_quantity = available_quantity + 1
      WHERE book_id = $1
      `,
      [schoolReservation.book_id]
    );

    await client.query("COMMIT");

    return res.status(200).json({
      success: true,
      message: "Kitap iade alındı",
      data: {
        publicReservation: updatedPublicReservation.rows[0],
        schoolReservation: updatedSchoolReservation.rows[0],
      },
    });
  } catch (error) {
    await client.query("ROLLBACK");
    next(error);
  } finally {
    client.release();
  }
};

const deleteReservation = async (req, res, next) => {
  const client = await pool.connect();

  try {
    const { id } = req.params;
    const { schoolCode } = req.body;

    if (!id || !schoolCode) {
      return res.status(400).json({
        success: false,
        message: "reservation id ve schoolCode zorunlu",
      });
    }

    if (!isNumericSchoolCode(schoolCode)) {
      return res.status(400).json({
        success: false,
        message: "Geçersiz okul kodu",
      });
    }

    const schemaName = `school_${schoolCode}`;

    await client.query("BEGIN");

    const schoolResult = await client.query(
      "SELECT * FROM public.schools WHERE school_code = $1 LIMIT 1",
      [schoolCode]
    );

    if (schoolResult.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({
        success: false,
        message: "Okul bulunamadı",
      });
    }

    await ensureSchoolReservationColumns(client, schemaName);

    const reservationResult = await client.query(
      `
      SELECT *
      FROM ${schemaName}.reservations
      WHERE reservation_id = $1
         OR public_reservation_id = $1
      FOR UPDATE
      `,
      [id]
    );

    if (reservationResult.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({
        success: false,
        message: "Ödünç kaydı bulunamadı",
      });
    }

    const reservation = reservationResult.rows[0];

    if (reservation.status === "loaned") {
      await client.query("ROLLBACK");
      return res.status(400).json({
        success: false,
        message: "Ödünçteki kitap silinemez. Önce iade alın.",
      });
    }

    const deleted = await client.query(
      `
      DELETE FROM ${schemaName}.reservations
      WHERE reservation_id = $1
      RETURNING *
      `,
      [reservation.reservation_id]
    );

    await client.query("COMMIT");

    return res.status(200).json({
      success: true,
      message: "Ödünç kaydı silindi",
      data: deleted.rows[0],
    });
  } catch (error) {
    await client.query("ROLLBACK");
    next(error);
  } finally {
    client.release();
  }
};

module.exports = {
  getAllReservations,
  getReservationById,
  createReservation,
  loanBookByStudent,
  loanReservation,
  rejectReservation,
  returnReservation,
  deleteReservation,
};