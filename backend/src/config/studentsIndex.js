// students tablosunun benzersizligi: (school_level, class_name, student_number)
// YALNIZCA AKTIF ogrenciler icin gecerlidir. "Eski Ogrenciler" (archived_at dolu)
// bu benzersizlige dahil DEGILDIR; cunku sinif numaralari her yil yeniden kullanilir
// ve mezun/arsiv bir ogrenci ayni numarali yeni ogrenciyi engellememelidir.
// Bu yuzden tam UNIQUE constraint yerine "WHERE archived_at IS NULL" kosullu
// KISMI (partial) unique index kullanilir. Fonksiyon idempotenttir: eski constraint'i
// dusurup kismi index'e gecirir, zaten gecmisse hicbir sey yapmaz.
async function ensureStudentsUniqueIndex(client, schema) {
  await client.query(`
    ALTER TABLE ${schema}.students
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP
  `);

  // Ayni slotta (seviye+sinif+numara) birden fazla AKTIF satir varsa en dusuk id'yi
  // tut (kismi index olusturulabilsin). Arsivli satirlara dokunma.
  await client.query(`
    DELETE FROM ${schema}.students a
    USING ${schema}.students b
    WHERE a.student_id > b.student_id
      AND a.archived_at IS NULL AND b.archived_at IS NULL
      AND a.school_level IS NOT DISTINCT FROM b.school_level
      AND a.class_name IS NOT DISTINCT FROM b.class_name
      AND a.student_number IS NOT DISTINCT FROM b.student_number
  `);

  // Eski tam UNIQUE constraint varsa dusur (kismi index ile ayni adi paylasamaz).
  await client.query(`
    DO $do$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'students_unique_level_class_number'
          AND connamespace = to_regnamespace('${schema}')
      ) THEN
        ALTER TABLE ${schema}.students
          DROP CONSTRAINT students_unique_level_class_number;
      END IF;
    END
    $do$;
  `);

  // Kismi unique index: yalnizca aktif (arsivsiz) ogrenciler benzersiz.
  await client.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS students_unique_level_class_number
      ON ${schema}.students (school_level, class_name, student_number)
      WHERE archived_at IS NULL
  `);
}

module.exports = { ensureStudentsUniqueIndex };
