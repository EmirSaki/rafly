const pool = require("../config/db");

async function ensureAnnouncementsTable(client) {
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS public.announcements (
        id SERIAL PRIMARY KEY,
        school_code VARCHAR(50) NOT NULL,
        title VARCHAR(500) NOT NULL,
        content TEXT NOT NULL,
        image_url TEXT,
        image_urls JSONB DEFAULT '[]'::jsonb,
        target_type VARCHAR(20) NOT NULL DEFAULT 'all',
        target_values JSONB DEFAULT '[]'::jsonb,
        start_date DATE NOT NULL,
        end_date DATE NOT NULL,
        sender_name VARCHAR(200) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
  } catch (e) {
    console.warn("[ensureAnnouncementsTable] CREATE TABLE error:", e.message);
  }
  try {
    await client.query(`
      ALTER TABLE public.announcements
      ADD COLUMN IF NOT EXISTS image_urls JSONB DEFAULT '[]'::jsonb
    `);
  } catch (e) {
    console.warn("[ensureAnnouncementsTable] ALTER TABLE error:", e.message);
  }
  try {
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_announcements_school_code
      ON public.announcements(school_code)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_announcements_dates
      ON public.announcements(start_date, end_date)
    `);
  } catch (e) {
    console.warn("[ensureAnnouncementsTable] CREATE INDEX error:", e.message);
  }
}

const getAnnouncements = async (req, res, next) => {
  try {
    const { schoolCode } = req.query;

    if (!schoolCode) {
      return res.status(400).json({
        success: false,
        message: "schoolCode zorunlu",
      });
    }

    const client = await pool.connect();
    try {
      await ensureAnnouncementsTable(client);

      const result = await client.query(
        `SELECT id, school_code, title, content, target_type, target_values,
                start_date, end_date, sender_name, created_at,
                COALESCE(jsonb_array_length(COALESCE(image_urls, '[]'::jsonb)), 0) AS image_count
         FROM public.announcements
         WHERE school_code = $1
         ORDER BY created_at DESC
         LIMIT 200`,
        [schoolCode]
      );

      return res.status(200).json({
        success: true,
        data: result.rows,
      });
    } finally {
      client.release();
    }
  } catch (error) {
    next(error);
  }
};

const createAnnouncement = async (req, res, next) => {
  try {
    const {
      schoolCode,
      title,
      content,
      target_type,
      target_values,
      start_date,
      end_date,
    } = req.body;

    if (!schoolCode || !title || !content || !start_date || !end_date) {
      return res.status(400).json({
        success: false,
        message: "schoolCode, title, content, start_date ve end_date zorunlu",
      });
    }

    const validTypes = ["all", "school_level", "class", "section"];
    const type = validTypes.includes(target_type) ? target_type : "all";

    let parsedValues = [];
    if (target_values) {
      try {
        parsedValues =
          typeof target_values === "string"
            ? JSON.parse(target_values)
            : target_values;
      } catch {
        parsedValues = [];
      }
    }

    let imageUrl = null;
    let imageUrls = [];

    if (req.files && req.files.length > 0) {
      imageUrls = req.files.map((file) => {
        const mimeType = file.mimetype || "image/png";
        const base64 = file.buffer.toString("base64");
        return `data:${mimeType};base64,${base64}`;
      });
      imageUrl = imageUrls[0];
    } else if (req.file) {
      const mimeType = req.file.mimetype || "image/png";
      const base64 = req.file.buffer.toString("base64");
      imageUrl = `data:${mimeType};base64,${base64}`;
      imageUrls = [imageUrl];
    }

    if (req.body.image_urls && Array.isArray(req.body.image_urls)) {
      imageUrls = req.body.image_urls;
      if (imageUrls.length > 0 && !imageUrl) {
        imageUrl = imageUrls[0];
      }
    } else if (req.body.image_url && !imageUrl) {
      imageUrl = req.body.image_url;
      imageUrls = [imageUrl];
    }

    let senderName = "Yetkili";
    const authHeader = req.headers.authorization;
    if (authHeader) {
      try {
        const jwt = require("jsonwebtoken");
        const token = authHeader.split(" ")[1];
        const decoded = jwt.verify(
          token,
          process.env.JWT_SECRET || "dev_secret"
        );
        if (decoded.user_id) {
          const userResult = await pool.query(
            "SELECT user_name, user_surname FROM public.users WHERE user_id = $1 LIMIT 1",
            [decoded.user_id]
          );
          if (userResult.rows.length > 0) {
            const u = userResult.rows[0];
            senderName = `${u.user_name} ${u.user_surname}`.trim();
          }
        }
      } catch {
        // token decode edilemezse default sender_name kullanılır
      }
    }

    const client = await pool.connect();
    try {
      await ensureAnnouncementsTable(client);

      const result = await client.query(
        `INSERT INTO public.announcements
         (school_code, title, content, image_url, image_urls, target_type, target_values, start_date, end_date, sender_name)
         VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7::jsonb, $8, $9, $10)
         RETURNING *`,
        [
          schoolCode,
          title.trim(),
          content.trim(),
          imageUrl,
          JSON.stringify(imageUrls),
          type,
          JSON.stringify(parsedValues),
          start_date,
          end_date,
          senderName,
        ]
      );

      return res.status(201).json({
        success: true,
        message: "Bilgilendirme oluşturuldu",
        data: result.rows[0],
      });
    } finally {
      client.release();
    }
  } catch (error) {
    next(error);
  }
};

const getAnnouncementImages = async (req, res, next) => {
  try {
    const { id } = req.params;
    if (!id || isNaN(Number(id))) {
      return res.status(400).json({ success: false, message: "Geçerli bir id gerekli" });
    }

    const client = await pool.connect();
    try {
      const result = await client.query(
        "SELECT image_url, image_urls FROM public.announcements WHERE id = $1 LIMIT 1",
        [id]
      );
      if (result.rows.length === 0) {
        return res.status(404).json({ success: false, message: "Bulunamadı" });
      }
      const row = result.rows[0];
      let images = [];
      if (row.image_urls && Array.isArray(row.image_urls) && row.image_urls.length > 0) {
        images = row.image_urls;
      } else if (row.image_url) {
        images = [row.image_url];
      }
      return res.status(200).json({ success: true, data: images });
    } finally {
      client.release();
    }
  } catch (error) {
    next(error);
  }
};

const deleteAnnouncement = async (req, res, next) => {
  try {
    const { id } = req.params;

    if (!id || isNaN(Number(id))) {
      return res.status(400).json({
        success: false,
        message: "Geçerli bir id gerekli",
      });
    }

    const client = await pool.connect();
    try {
      await ensureAnnouncementsTable(client);

      const result = await client.query(
        "DELETE FROM public.announcements WHERE id = $1 RETURNING id",
        [id]
      );

      if (result.rows.length === 0) {
        return res.status(404).json({
          success: false,
          message: "Bilgilendirme bulunamadı",
        });
      }

      return res.status(200).json({
        success: true,
        message: "Bilgilendirme silindi",
      });
    } finally {
      client.release();
    }
  } catch (error) {
    next(error);
  }
};

module.exports = {
  getAnnouncements,
  getAnnouncementImages,
  createAnnouncement,
  deleteAnnouncement,
};
