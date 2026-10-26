const express = require("express");
const multer = require("multer");
const router = express.Router();
// deploy marker: request-password endpoint eklendi (2026-10-06)

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 5 * 1024 * 1024,
  },
});

const {
  getStudents,
  registerStudent,
  loginStudent,
  createStudentReservation,
  getMyReservations,
  importStudentsFromExcel,
  createManualStudent,
  getMyProfile,
  updateMyProfile,
  bulkAssignPasswords,
  deleteStudent,
  deleteMyAccount,
} = require("../controllers/student.controller");

const { authStudent } = require("../middlewares/student.middleware");
const { promotion, authorizePromotion } = require('../controllers/studentPromotion.controller');
const promotionUpload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 5 * 1024 * 1024, files: 100, fields: 4 } });
router.post('/promotion/:phase', authorizePromotion, promotionUpload.array('files', 100), promotion);

// Öğrenci listesi
router.get("/", getStudents);
router.post("/", createManualStudent);
router.delete("/", deleteStudent);

// Excel import
router.post("/import", upload.single("file"), importStudentsFromExcel);

// Auth olmayan
router.post("/register", registerStudent);
router.post("/login", loginStudent);
// Mail ile şifre alma kaldırıldı (öğrenci şifreleri sabit "1234")
router.post("/bulk-passwords", bulkAssignPasswords);

// Auth gerekenler
router.get("/profile", authStudent, getMyProfile);
router.patch("/profile", authStudent, updateMyProfile);
router.delete("/profile", authStudent, deleteMyAccount);
router.post("/reservations", authStudent, createStudentReservation);
router.get("/reservations", authStudent, getMyReservations);

module.exports = router;
