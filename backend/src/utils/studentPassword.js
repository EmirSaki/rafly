const jwt = require("jsonwebtoken");

// Yeni kayıtlı / sıfırlanmış öğrencinin ilk giriş şifresi. Yalnızca "ilk giriş"
// için geçerlidir; öğrenci kendi şifresini belirleyene kadar tam oturum verilmez.
const INITIAL_STUDENT_PASSWORD = "1234";
const MIN_PASSWORD_LENGTH = 6;
const SETUP_TOKEN_TTL = "15m";

function jwtSecret() {
  return process.env.JWT_SECRET || "dev_secret";
}

// Hata mesajı döner, geçerliyse null.
function validateNewPassword(pw) {
  if (typeof pw !== "string" || pw.length < MIN_PASSWORD_LENGTH) {
    return `Şifre en az ${MIN_PASSWORD_LENGTH} karakter olmalı`;
  }
  if (pw.length > 72) return "Şifre en fazla 72 karakter olabilir";
  if (pw === INITIAL_STUDENT_PASSWORD) return "Başlangıç şifresini yeni şifre olarak kullanamazsın";
  if (/^(\d)\1+$/.test(pw)) return "Şifre tek tekrarlayan karakterlerden oluşamaz";
  return null;
}

// Tam oturum değil: yalnızca set-password ucunda geçerli, kısa ömürlü anahtar.
function signSetupToken(user) {
  return jwt.sign({ purpose: "student_password_setup", user_id: user.user_id }, jwtSecret(), {
    expiresIn: SETUP_TOKEN_TTL,
  });
}

function verifySetupToken(token) {
  try {
    const d = jwt.verify(String(token || ""), jwtSecret());
    return d.purpose === "student_password_setup" && d.user_id ? d : null;
  } catch (_) {
    return null;
  }
}

// Bellek içi deneme sınırı: aynı anahtar için pencere içinde en fazla `max` hatalı deneme.
function createLoginThrottle({ max = 8, windowMs = 15 * 60 * 1000, now = () => Date.now() } = {}) {
  const hits = new Map();
  const MAX_KEYS = 5000; // rastgele anahtarlarla belleği şişirmeyi önler
  const prune = () => {
    const t = now();
    for (const [k, list] of hits) {
      if (!list.some((x) => t - x < windowMs)) hits.delete(k);
    }
    if (hits.size > MAX_KEYS) hits.clear();
  };
  const fresh = (key) => {
    const t = now();
    const list = (hits.get(key) || []).filter((x) => t - x < windowMs);
    if (list.length) hits.set(key, list); else hits.delete(key);
    return list;
  };
  return {
    blocked: (key) => fresh(key).length >= max,
    fail: (key) => {
      if (hits.size >= MAX_KEYS) prune();
      const list = fresh(key); list.push(now()); hits.set(key, list);
    },
    reset: (key) => hits.delete(key),
  };
}

module.exports = {
  INITIAL_STUDENT_PASSWORD,
  MIN_PASSWORD_LENGTH,
  validateNewPassword,
  signSetupToken,
  verifySetupToken,
  createLoginThrottle,
};
