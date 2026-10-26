const nodemailer = require("nodemailer");

// Mail gönderici — iki mod:
//  1) BREVO_API_KEY tanımlıysa: Brevo HTTP API (IP kısıtlamasından ETKİLENMEZ,
//     Cloud Run için doğru yöntem).
//  2) Değilse: SMTP (nodemailer) — SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS.
// Gönderen her iki modda da MAIL_FROM'dan alınır (örn. "Rafly <noreply@raflylib.online>").

// "Rafly <noreply@raflylib.online>" -> { name: "Rafly", email: "noreply@..." }
function parseFrom() {
  const raw = process.env.MAIL_FROM || "Rafly <noreply@raflylib.online>";
  const m = raw.match(/^\s*(.*?)\s*<([^>]+)>\s*$/);
  if (m) return { name: m[1] || "Rafly", email: m[2].trim() };
  return { name: "Rafly", email: raw.trim() };
}

// ── Brevo HTTP API ──
async function sendViaBrevoApi({ to, subject, html, text }) {
  const sender = parseFrom();
  const res = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: {
      "api-key": process.env.BREVO_API_KEY,
      "content-type": "application/json",
      accept: "application/json",
    },
    body: JSON.stringify({
      sender,
      to: [{ email: to }],
      subject,
      htmlContent: html,
      textContent: text,
    }),
  });
  if (!res.ok) {
    let detail = "";
    try { detail = JSON.stringify(await res.json()); } catch (_) {}
    throw new Error(`Brevo API ${res.status}: ${detail}`);
  }
  return res.json().catch(() => ({}));
}

// ── SMTP (fallback) ──
let transporter = null;
function getTransporter() {
  if (transporter) return transporter;
  const host = process.env.SMTP_HOST;
  const port = parseInt(process.env.SMTP_PORT || "587", 10);
  const user = process.env.SMTP_USER;
  const pass = process.env.SMTP_PASS;
  if (!host || !user || !pass) {
    throw new Error("SMTP ayarları eksik — SMTP_HOST, SMTP_USER ve SMTP_PASS tanımlı olmalı");
  }
  transporter = nodemailer.createTransport({
    host,
    port,
    secure: port === 465, // 465 = SSL, 587 = STARTTLS
    auth: { user, pass },
  });
  return transporter;
}

async function sendMail({ to, subject, html, text }) {
  if (process.env.BREVO_API_KEY) {
    return sendViaBrevoApi({ to, subject, html, text });
  }
  const from = process.env.MAIL_FROM || "Rafly <noreply@raflylib.online>";
  return getTransporter().sendMail({ from, to, subject, html, text });
}

// Öğrenciye otomatik şifre e-postası
async function sendStudentPasswordEmail({ to, firstName, schoolName, password }) {
  const name = firstName || "Öğrenci";
  const subject = "Rafly Öğrenci Paneli — Giriş Şifren";
  const panelUrl = "https://raflylib.online/ogrenci/";

  const text =
    `Merhaba ${name},\n\n` +
    `${schoolName} kütüphane sistemi için Rafly öğrenci paneli şifren oluşturuldu.\n\n` +
    `Şifren: ${password}\n\n` +
    `Giriş yapmak için: ${panelUrl}\n` +
    `Okul kodun, seviyeni ve öğrenci numaranla birlikte bu şifreyi kullan.\n\n` +
    `Giriş yaptıktan sonra Profil bölümünden şifreni değiştirebilirsin.\n\n` +
    `Rafly`;

  const html = `
  <div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;background:#F9FAFB;padding:24px;color:#111827">
    <div style="max-width:480px;margin:0 auto;background:#fff;border:1px solid #E5E7EB;border-radius:14px;overflow:hidden">
      <div style="background:#1A3366;padding:24px;text-align:center">
        <div style="color:#fff;font-size:22px;font-weight:800;letter-spacing:.5px">Rafly</div>
        <div style="color:#C7D2FE;font-size:13px;margin-top:2px">Öğrenci Paneli</div>
      </div>
      <div style="padding:24px">
        <p style="font-size:15px;margin:0 0 12px">Merhaba <b>${escapeHtml(name)}</b>,</p>
        <p style="font-size:14px;color:#374151;margin:0 0 20px;line-height:1.6">
          <b>${escapeHtml(schoolName)}</b> kütüphane sistemi için öğrenci paneli şifren oluşturuldu.
        </p>
        <div style="background:#F3F4F6;border:1px dashed #9CA3AF;border-radius:10px;padding:16px;text-align:center;margin-bottom:20px">
          <div style="font-size:12px;color:#6B7280;margin-bottom:6px">Giriş Şifren</div>
          <div style="font-size:28px;font-weight:800;letter-spacing:4px;color:#1A3366">${escapeHtml(password)}</div>
        </div>
        <a href="${panelUrl}" style="display:block;background:#1A3366;color:#fff;text-decoration:none;text-align:center;padding:13px;border-radius:10px;font-weight:600;font-size:14px">
          Panele Giriş Yap
        </a>
        <p style="font-size:13px;color:#6B7280;margin:20px 0 0;line-height:1.6">
          Okul kodun, seviyeni ve öğrenci numaranla birlikte bu şifreyi gir.
          Giriş yaptıktan sonra <b>Profil</b> bölümünden şifreni değiştirebilirsin.
        </p>
      </div>
      <div style="padding:14px 24px;border-top:1px solid #E5E7EB;text-align:center;color:#9CA3AF;font-size:11px">
        Bu e-postayı sen istemediysen dikkate alma.
      </div>
    </div>
  </div>`;

  return sendMail({ to, subject, html, text });
}

function escapeHtml(s) {
  return String(s == null ? "" : s).replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[c]));
}

module.exports = { sendMail, sendStudentPasswordEmail };
