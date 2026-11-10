const express = require("express");
const router = express.Router();
const adminController = require("../controllers/admin.controller");
const { requireAdminKeyIfConfigured } = require("../middlewares/staff.middleware");

// Okul ve öğretmen yönetimi. ADMIN_API_KEY tanımlandığı anda her istekte
// "x-admin-key" başlığı zorunlu olur.
router.use(requireAdminKeyIfConfigured);

// Okul işlemleri
router.post("/schools", adminController.createSchool);
router.get("/schools", adminController.getSchools);

// Öğretmen işlemleri
router.post("/schools/:schoolId/teachers", adminController.createTeacher);
router.get("/schools/:schoolId/teachers", adminController.getSchoolTeachers);
router.delete("/schools/:schoolId/teachers/:teacherId", adminController.deleteTeacher);

module.exports = router;