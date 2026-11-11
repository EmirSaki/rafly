const jwt = require("jsonwebtoken");
const { hasAdminKey } = require("./staff.middleware");

// ---------------------------------------------------------------------------
// Genel yetki kapısı
//
// Her API isteği burada sınıflandırılır:
//   public   : oturum gerekmez (giriş, sağlık kontrolü, okul logosu...)
//   member   : öğrenci YA DA personel oturumu (kitap listesi, duyurular...)
//   staff    : personel (öğretmen/yönetici) oturumu
//   self     : uç nokta kendi yetki kontrolünü yapar (öğrenci profil uçları,
//              /api/admin, /api/users, sınıf atlatma)
//
// AUTH_MODE:
//   "enforce" → yetkisiz istek 401/403 ile reddedilir.
//   diğer     → GEÇİŞ MODU: istek eskisi gibi çalışır, yalnızca loglanır
//               ([AUTH_SOFT] ...). Eski uygulama sürümleri, istasyon tableti ve
//               kart aracı henüz oturum bilgisi göndermediği için varsayılan
//               budur; tüm istemciler güncellenince AUTH_MODE=enforce yapılır.
// ---------------------------------------------------------------------------

const PUBLIC = [
  ["GET", /^\/$/],
  ["GET", /^\/health$/],
  ["POST", /^\/api\/users\/login$/],
  ["POST", /^\/api\/students\/login$/],
  ["POST", /^\/api\/students\/register$/],
  ["POST", /^\/api\/schools\/access$/],
  ["GET", /^\/api\/schools\/\d+\/logo$/],
];

// Kendi kontrolünü yapan uçlar (authStudent, requireAdminKey, authorizePromotion...)
const SELF = [
  [null, /^\/api\/admin(\/|$)/],
  [null, /^\/api\/users(\/|$)/],
  [null, /^\/api\/students\/(profile|reservations)$/],
  ["POST", /^\/api\/students\/promotion\//],
  ["DELETE", /^\/api\/announcements\/\d+$/],
  ["GET", /^\/debug\/routes$/],
];

// Öğrencinin de kullandığı salt-okuma uçları
const MEMBER = [
  ["GET", /^\/api\/schools\/\d+\/books(\/isbn\/[^/]+|\/\d+)?$/],
  ["GET", /^\/api\/books(\/isbn\/[^/]+|\/\d+)?\/?$/],
  ["GET", /^\/api\/announcements\/?$/],
  ["GET", /^\/api\/announcements\/\d+\/images$/],
];

function matches(table, method, path) {
  return table.some(([m, re]) => (m === null || m === method) && re.test(path));
}

function classify(method, path) {
  if (matches(PUBLIC, method, path)) return "public";
  if (matches(SELF, method, path)) return "self";
  if (matches(MEMBER, method, path)) return "member";
  return "staff";
}

function readToken(req) {
  const header = String(req.headers.authorization || "");
  const token = header.replace(/^Bearer\s+/i, "").trim();
  if (!token) return null;
  try {
    return jwt.verify(token, process.env.JWT_SECRET || "dev_secret");
  } catch {
    return null;
  }
}

// İsteğin hedeflediği okul kodu (varsa): yol, sorgu ya da JSON gövdesinden.
function requestedSchoolCode(req, path) {
  const fromPath = path.match(/^\/api\/schools\/(\d+)(\/|$)/);
  if (fromPath) return fromPath[1];
  const q = req.query && req.query.schoolCode;
  if (q) return String(q);
  const b = req.body && typeof req.body === "object" ? req.body.schoolCode : null;
  if (b) return String(b);
  return null;
}

// Karar: { ok: true } ya da { ok: false, status, reason }
function decide(req) {
  const method = String(req.method || "GET").toUpperCase();
  const path = String(req.path || "/");
  const kind = classify(method, path);
  if (kind === "public" || kind === "self") return { ok: true, kind };
  if (hasAdminKey(req)) return { ok: true, kind, admin: true };

  const user = readToken(req);
  if (!user) return { ok: false, kind, status: 401, reason: "oturum-yok" };

  const isStaff = ["teacher", "admin"].includes(user.role);
  const isStudent = user.role === "student";
  if (kind === "staff" && !isStaff) return { ok: false, kind, status: 403, reason: "personel-degil" };
  if (kind === "member" && !isStaff && !isStudent) return { ok: false, kind, status: 403, reason: "rol-gecersiz" };

  const wanted = requestedSchoolCode(req, path);
  if (wanted && String(user.school_code) !== wanted) {
    return { ok: false, kind, status: 403, reason: "baska-okul" };
  }
  return { ok: true, kind, user };
}

// Geçiş modunda log seli olmasın: aynı (yöntem, yol kalıbı, neden) 10 dakikada bir yazılır.
const softLog = new Map();
const SOFT_LOG_WINDOW_MS = 10 * 60 * 1000;
function logSoft(req, decision) {
  const pattern = String(req.path || "/").replace(/\d+/g, ":n").replace(/isbn\/[^/]+/, "isbn/:isbn");
  const key = `${req.method} ${pattern} ${decision.reason}`;
  const now = Date.now();
  const entry = softLog.get(key) || { count: 0, last: 0 };
  entry.count += 1;
  if (now - entry.last >= SOFT_LOG_WINDOW_MS) {
    console.warn(`[AUTH_SOFT] ${entry.count}x ${key}`);
    entry.count = 0;
    entry.last = now;
  }
  softLog.set(key, entry);
}

const MESSAGES = {
  "oturum-yok": "Oturum gerekli. Lütfen giriş yapın.",
  "personel-degil": "Bu işlem için personel yetkisi gerekiyor.",
  "rol-gecersiz": "Bu işlem için yetkiniz yok.",
  "baska-okul": "Yalnızca kendi okulunuzun verilerine erişebilirsiniz.",
};

function authGate(req, res, next) {
  const decision = decide(req);
  if (decision.ok) {
    if (decision.user) req.authUser = decision.user;
    return next();
  }
  if (process.env.AUTH_MODE === "enforce") {
    return res.status(decision.status).json({
      success: false,
      message: MESSAGES[decision.reason] || "Yetkisiz istek.",
    });
  }
  logSoft(req, decision);
  return next();
}

module.exports = { authGate, decide, classify };
