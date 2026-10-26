const pool = require("./db");

const initializeDatabase = async () => {
  const client = await pool.connect();

  try {
    console.log("[DB_INIT] Veritabanı tabloları oluşturuluyor...");

    // Public schools tablosu
    await client.query(`
      CREATE TABLE IF NOT EXISTS public.schools (
        school_id SERIAL PRIMARY KEY,
        school_code VARCHAR(50) UNIQUE NOT NULL,
        school_name VARCHAR(255) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    await client.query(`
      ALTER TABLE public.schools
      ADD COLUMN IF NOT EXISTS logo_url TEXT
    `);
    console.log("[DB_INIT] ✓ public.schools tablosu oluşturuldu");

    // Public users tablosu
    await client.query(`
      CREATE TABLE IF NOT EXISTS public.users (
        user_id SERIAL PRIMARY KEY,
        user_name VARCHAR(100) NOT NULL,
        user_surname VARCHAR(100) NOT NULL,
        email VARCHAR(255),
        password VARCHAR(255),
        user_role VARCHAR(50) NOT NULL,
        student_id VARCHAR(50),
        user_class VARCHAR(50),
        user_class_code VARCHAR(50),
        school_id INTEGER REFERENCES public.schools(school_id) ON DELETE CASCADE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    await client.query(`
      ALTER TABLE public.users
      ALTER COLUMN email DROP NOT NULL
    `);
    await client.query(`
      ALTER TABLE public.users
      ADD COLUMN IF NOT EXISTS phone VARCHAR(20)
    `);
    await client.query(`
      ALTER TABLE public.users
      ADD COLUMN IF NOT EXISTS profile_completed BOOLEAN DEFAULT FALSE
    `);
    console.log("[DB_INIT] ✓ public.users tablosu oluşturuldu");

    // Public books tablosu
    await client.query(`
      CREATE TABLE IF NOT EXISTS public.books (
        book_id SERIAL PRIMARY KEY,
        book_name VARCHAR(255),
        book_writer TEXT,
        book_genre TEXT,
        publisher VARCHAR(255),
        isbn VARCHAR(50),
        page_count INTEGER DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    await client.query(`
      ALTER TABLE public.books
      ADD COLUMN IF NOT EXISTS book_name VARCHAR(255)
    `);
    await client.query(`
      ALTER TABLE public.books
      ADD COLUMN IF NOT EXISTS book_writer TEXT
    `);
    await client.query(`
      ALTER TABLE public.books
      ADD COLUMN IF NOT EXISTS book_genre TEXT
    `);
    await client.query(`
      ALTER TABLE public.books
      ADD COLUMN IF NOT EXISTS publisher VARCHAR(255)
    `);
    await client.query(`
      ALTER TABLE public.books
      ADD COLUMN IF NOT EXISTS isbn VARCHAR(50)
    `);
    await client.query(`
      ALTER TABLE public.books
      ADD COLUMN IF NOT EXISTS page_count INTEGER DEFAULT 0
    `);
    await client.query(`
      ALTER TABLE public.books
      ADD COLUMN IF NOT EXISTS cover_url TEXT
    `);
    await client.query(`
      ALTER TABLE public.books
      ADD COLUMN IF NOT EXISTS is_valilik_book BOOLEAN NOT NULL DEFAULT FALSE
    `);
    console.log("[DB_INIT] ✓ public.books tablosu oluşturuldu");

    // Public reservations tablosu
    await client.query(`
      CREATE TABLE IF NOT EXISTS public.reservations (
        reservation_id SERIAL PRIMARY KEY,
        user_id INTEGER REFERENCES public.users(user_id) ON DELETE CASCADE,
        book_id INTEGER REFERENCES public.books(book_id) ON DELETE CASCADE,
        school_id INTEGER REFERENCES public.schools(school_id) ON DELETE CASCADE,
        reservation_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        reservation_status VARCHAR(50) NOT NULL DEFAULT 'pending_approval',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    await client.query(`
      ALTER TABLE public.reservations
      ADD COLUMN IF NOT EXISTS reservation_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    `);
    await client.query(`
      ALTER TABLE public.reservations
      ADD COLUMN IF NOT EXISTS reservation_status VARCHAR(50) NOT NULL DEFAULT 'pending_approval'
    `);
    await client.query(`
      ALTER TABLE public.reservations
      ADD COLUMN IF NOT EXISTS returned_at TIMESTAMP
    `);
    await client.query(`
      ALTER TABLE public.reservations
      ADD COLUMN IF NOT EXISTS created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    `);
    await client.query(`
      ALTER TABLE public.reservations
      ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    `);
    console.log("[DB_INIT] ✓ public.reservations tablosu oluşturuldu");

    // Indices
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_users_school_id ON public.users(school_id)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_reservations_user_id ON public.reservations(user_id)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_reservations_book_id ON public.reservations(book_id)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_reservations_school_id ON public.reservations(school_id)
    `);
    console.log("[DB_INIT] ✓ İndexler oluşturuldu");

    // Tüm okul şemalarındaki book_inventory tablosuna raf (shelf) kolonu ekle
    const schoolSchemas = await client.query(
      `SELECT table_schema
       FROM information_schema.tables
       WHERE table_name = 'book_inventory'
         AND table_schema LIKE 'school\\_%'`
    );

    for (const { table_schema } of schoolSchemas.rows) {
      try {
        await client.query(
          `ALTER TABLE "${table_schema}".book_inventory
           ADD COLUMN IF NOT EXISTS shelf VARCHAR(100)`
        );
      } catch (shelfError) {
        console.error(
          `[DB_INIT] ⚠ ${table_schema}.book_inventory shelf kolonu eklenemedi:`,
          shelfError.message
        );
      }

      // Çoklu raf desteği: bir kitap birden fazla rafta bulunabilsin.
      // Raf başına ADET TUTULMAZ (ödünç alınan kitap başka rafa konabilir,
      // raf başına adet doğrulanamaz) — bu tablo yalnızca kitabın bulunduğu
      // raf etiketlerini saklar. Toplam adet book_inventory'de kalır.
      try {
        await client.query(
          `CREATE TABLE IF NOT EXISTS "${table_schema}".book_shelf_locations (
             id SERIAL PRIMARY KEY,
             book_id INTEGER NOT NULL REFERENCES public.books(book_id) ON DELETE CASCADE,
             shelf VARCHAR(100) NOT NULL,
             created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
             UNIQUE (book_id, shelf)
           )`
        );
        await client.query(
          `CREATE INDEX IF NOT EXISTS idx_${table_schema}_shelf_locations_book_id
           ON "${table_schema}".book_shelf_locations (book_id)`
        );

        // Mevcut veriyi taşı: book_inventory'deki tek raf etiketini raf
        // tablosuna aktar. Idempotent: zaten rafı olan kitaba dokunma.
        await client.query(
          `INSERT INTO "${table_schema}".book_shelf_locations (book_id, shelf)
           SELECT bi.book_id, TRIM(bi.shelf)
           FROM "${table_schema}".book_inventory bi
           WHERE bi.shelf IS NOT NULL
             AND TRIM(bi.shelf) <> ''
             AND NOT EXISTS (
               SELECT 1 FROM "${table_schema}".book_shelf_locations sl
               WHERE sl.book_id = bi.book_id
             )
           ON CONFLICT (book_id, shelf) DO NOTHING`
        );
      } catch (shelfLocError) {
        console.error(
          `[DB_INIT] ⚠ ${table_schema}.book_shelf_locations hazırlanamadı:`,
          shelfLocError.message
        );
      }
    }
    console.log(
      `[DB_INIT] ✓ ${schoolSchemas.rows.length} okul şemasında shelf kolonu + raf kırılım tablosu kontrol edildi`
    );

    console.log("[DB_INIT] ✅ Veritabanı başlatması tamamlandı");
  } catch (error) {
    console.error("[DB_INIT] ❌ Hata:", error.message);
    throw error;
  } finally {
    client.release();
  }
};

module.exports = initializeDatabase;
