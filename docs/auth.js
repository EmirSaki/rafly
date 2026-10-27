'use strict';

window.raflyAuth = {
  async login(role, fields, signal) {
    const student = role === 'student';
    const schoolCode = fields.schoolCode.trim();
    if (!/^\d+$/.test(schoolCode)) throw new Error('Okul kodu yalnızca rakamlardan oluşmalıdır.');
    const levels = ['ilkokul', 'ortaokul', 'lise', 'hazırlık', 'diğer'];
    const level = levels[Number(fields.schoolLevel)];
    if (student && (!level || fields.schoolLevel == null)) throw new Error('Okul seviyesini seçin.');
    const body = { schoolCode, password: fields.password };
    if (student) Object.assign(body, { student_number: fields.identity.trim(), school_level: level });
    else body.email = fields.identity.trim();

    const response = await fetch(`https://library-api-346058361420.europe-west1.run.app/api/${student ? 'students' : 'users'}/login`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body), signal,
    });
    const result = await response.json().catch(() => null);
    if (!response.ok || result?.success !== true || !result.token || !result.data) {
      throw new Error(response.status >= 500 ? 'Giriş hizmetine şu anda ulaşılamıyor. Lütfen tekrar deneyin.' : (result?.message || 'Giriş yapılamadı. Bilgilerinizi kontrol edin.'));
    }
    if (signal?.aborted) throw new DOMException('Cancelled', 'AbortError');
    const values = student ? {
      student_token: result.token, student_school_code: schoolCode,
      student_school_level: level, app_role: 'student',
    } : {
      auth_token: result.token,
      auth_user: JSON.stringify(result.data.user),
      auth_school: JSON.stringify(result.data.school),
      'library-auth': JSON.stringify({ state: { token: result.token, user: result.data.user, school: result.data.school, isAuthenticated: true }, version: 0 }),
    };
    if (!student && (!result.data.user || !result.data.school)) throw new Error('Giriş yanıtı eksik. Lütfen tekrar deneyin.');
    const previous = new Map();
    try {
      for (const [key, value] of Object.entries(values)) {
        previous.set(key, localStorage.getItem(key));
        localStorage.setItem(key, value);
      }
    } catch (_) {
      for (const [key, value] of previous) {
        try { if (value === null) localStorage.removeItem(key); else localStorage.setItem(key, value); } catch (_) { /* Storage unavailable. */ }
      }
      throw new Error('Oturum kaydedilemedi. Tarayıcınızda bu site için depolamaya izin verin.');
    }
    return student ? 'ogrenci/' : 'panel/#/';
  },
};
