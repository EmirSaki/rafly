const express = require("express");
const multer = require("multer");
const router = express.Router();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 2 * 1024 * 1024 }, // 2MB max
  fileFilter: (req, file, cb) => {
    const allowed = ["image/png", "image/jpeg", "image/jpg", "image/webp", "image/svg+xml"];
    if (allowed.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error("Sadece PNG, JPG, WebP ve SVG formatları desteklenir"));
    }
  },
});

const {
  accessSchool,
  getSchoolBooks,
  getSchoolBookByIsbn,
  getSchoolBookDetail,
  addBookToSchoolInventory,
  updateSchoolBookQuantity,
  deleteSchoolBookFromInventory,
  exportSchoolBooks,
  uploadSchoolLogo,
  getSchoolLogo,
  deleteSchoolLogo,
} = require("../controllers/school.controller");

const { generateReportCards } = require("../controllers/reportCard.controller");

router.post("/access", accessSchool);

// Logo routes
router.get("/:schoolCode/logo", getSchoolLogo);
router.post("/:schoolCode/logo", upload.single("logo"), uploadSchoolLogo);
router.delete("/:schoolCode/logo", deleteSchoolLogo);

router.get("/:schoolCode/report-cards", generateReportCards);

router.get("/:schoolCode/books/export", exportSchoolBooks);
router.get("/:schoolCode/books/isbn/:isbn", getSchoolBookByIsbn);
router.get("/:schoolCode/books", getSchoolBooks);
router.get("/:schoolCode/books/:bookId", getSchoolBookDetail);

router.post("/:schoolCode/books", addBookToSchoolInventory);
router.patch("/:schoolCode/books/:bookId", updateSchoolBookQuantity);
router.delete("/:schoolCode/books/:bookId", deleteSchoolBookFromInventory);

module.exports = router;