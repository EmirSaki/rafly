const crypto = require("crypto");
const jwt = require("jsonwebtoken");

// Personel (öğretmen/yönetici) oturumu: /api/users/login'in verdiği JWT.
function readStaffToken(req) {
  const header = String(req.headers.authorization || "");
  const token = header.replace(/^Bearer\s+/i, "").trim();
  if (!token) return null;
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET || "dev_secret");
    return ["teacher", "admin"].includes(decoded.role) ? decoded : null;
  } catch {
    return null;
  }
}

// Platform yöneticisi anahtarı: Cloud Run'da ADMIN_API_KEY ortam değişkeni,
// istekte "x-admin-key" başlığı. Anahtar tanımlı değilse hiçbir istek
// yönetici sayılmaz.
function hasAdminKey(req) {
  const expected = String(process.env.ADMIN_API_KEY || "");
  const given = String(req.headers["x-admin-key"] || "");
  if (!expected || !given) return false;
  const a = Buffer.from(expected);
  const b = Buffer.from(given);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

// Yalnızca platform yöneticisi. Anahtar tanımlı değilse uç nokta KAPALIDIR.
function requireAdminKey(req, res, next) {
  if (hasAdminKey(req)) return next();
  return res.status(process.env.ADMIN_API_KEY ? 401 : 403).json({
    success: false,
    message: "Bu işlem için yönetici yetkisi gerekiyor.",
  });
}

// Geçiş dönemi: ADMIN_API_KEY tanımlanana kadar uç nokta eskisi gibi açık
// kalır (mevcut yönetici uygulaması bozulmasın); tanımlandığı anda zorunlu olur.
let warnedOpenAdmin = false;
function requireAdminKeyIfConfigured(req, res, next) {
  if (!process.env.ADMIN_API_KEY) {
    if (!warnedOpenAdmin) {
      warnedOpenAdmin = true;
      console.warn("[AUTH] ADMIN_API_KEY tanımlı değil: /api/admin uçları korumasız çalışıyor");
    }
    return next();
  }
  return requireAdminKey(req, res, next);
}

// Personel oturumu ya da yönetici anahtarı gerekir.
function requireStaff(req, res, next) {
  if (hasAdminKey(req)) {
    req.isPlatformAdmin = true;
    return next();
  }
  const staff = readStaffToken(req);
  if (!staff) {
    return res.status(401).json({
      success: false,
      message: "Oturum geçersiz. Yeniden giriş yapın.",
    });
  }
  req.staff = staff;
  return next();
}

// requireStaff'tan sonra: personel yalnızca kendi okulunun kaydına dokunabilir.
function staffCanAccessSchool(req, schoolCode) {
  if (req.isPlatformAdmin) return true;
  return !!req.staff && String(req.staff.school_code) === String(schoolCode);
}

module.exports = {
  readStaffToken,
  hasAdminKey,
  requireAdminKey,
  requireAdminKeyIfConfigured,
  requireStaff,
  staffCanAccessSchool,
};
