const pool = require("../config/db");

const INTERVAL_MS = 60 * 60 * 1000; // her saat kontrol et

async function ensureAnnouncementsTable(client) {
  await client.query(`
    CREATE TABLE IF NOT EXISTS public.announcements (
      id SERIAL PRIMARY KEY,
      school_code VARCHAR(50) NOT NULL,
      title VARCHAR(500) NOT NULL,
      content TEXT NOT NULL,
      image_url TEXT,
      target_type VARCHAR(20) NOT NULL DEFAULT 'all',
      target_values JSONB DEFAULT '[]'::jsonb,
      start_date DATE NOT NULL,
      end_date DATE NOT NULL,
      sender_name VARCHAR(200) NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);
}

async function checkOverdueReservations() {
  const client = await pool.connect();
  try {
    await ensureAnnouncementsTable(client);

    const schools = await client.query(
      "SELECT school_code FROM public.schools"
    );

    let totalSent = 0;

    for (const school of schools.rows) {
      const schemaName = `school_${school.school_code}`;

      const schemaCheck = await client.query(
        `SELECT schema_name FROM information_schema.schemata WHERE schema_name = $1`,
        [schemaName]
      );
      if (schemaCheck.rows.length === 0) continue;

      const tableCheck = await client.query(
        `SELECT EXISTS (
          SELECT 1 FROM information_schema.tables
          WHERE table_schema = $1 AND table_name = 'reservations'
        ) AS exists`,
        [schemaName]
      );
      if (!tableCheck.rows[0]?.exists) continue;

      const overdue = await client.query(
        `
        SELECT
          sr.due_date,
          COALESCE(sr.student_number, st.student_number) AS student_number,
          st.full_name,
          b.book_name
        FROM ${schemaName}.reservations sr
        LEFT JOIN ${schemaName}.students st
          ON sr.student_local_id IS NOT NULL
          AND st.student_id = sr.student_local_id
        JOIN public.books b ON b.book_id = sr.book_id
        WHERE sr.status = 'loaned'
          AND sr.due_date IS NOT NULL
          AND sr.due_date::date < CURRENT_DATE
        `
      );

      for (const row of overdue.rows) {
        const studentNumber = row.student_number;
        if (!studentNumber) continue;

        const alreadySent = await client.query(
          `SELECT id FROM public.announcements
           WHERE school_code = $1
             AND target_type = 'section'
             AND target_values @> $2::jsonb
             AND title = 'Kitap İade Uyarısı'
             AND created_at::date = CURRENT_DATE
           LIMIT 1`,
          [school.school_code, JSON.stringify([studentNumber])]
        );

        if (alreadySent.rows.length > 0) continue;

        const fullName = row.full_name || "Öğrenci";
        const bookName = row.book_name || "kitap";
        const today = new Date().toISOString().split("T")[0];
        const endDate = new Date(Date.now() + 30 * 86400000)
          .toISOString()
          .split("T")[0];

        await client.query(
          `INSERT INTO public.announcements
           (school_code, title, content, target_type, target_values, start_date, end_date, sender_name)
           VALUES ($1, $2, $3, 'section', $4::jsonb, $5, $6, 'Sistem')`,
          [
            school.school_code,
            "Kitap İade Uyarısı",
            `Sayın ${fullName}, "${bookName}" adlı kitabın iade tarihi geçmiştir. Lütfen kitabınızı kütüphaneye iade edin.`,
            JSON.stringify([studentNumber]),
            today,
            endDate,
          ]
        );

        totalSent++;
      }
    }

    if (totalSent > 0) {
      console.log(
        `[OVERDUE_NOTIFIER] ${totalSent} otomatik uyarı bildirimi gönderildi`
      );
    }
  } catch (error) {
    console.error("[OVERDUE_NOTIFIER] Hata:", error.message);
  } finally {
    client.release();
  }
}

function startOverdueNotifier() {
  console.log("[OVERDUE_NOTIFIER] Gecikme bildirimi servisi başlatıldı");

  setTimeout(() => {
    checkOverdueReservations();
  }, 10000);

  setInterval(checkOverdueReservations, INTERVAL_MS);
}

module.exports = { startOverdueNotifier };
