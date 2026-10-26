const express = require("express");
const multer = require("multer");
const router = express.Router();
const bookController = require("../controllers/book.controller.js");
const coverController = require("../controllers/cover.controller.js");

// Kapak görselleri cihazda küçültülüp gönderiliyor; 5 MB fazlasıyla yeterli.
const coverUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
});

// Kapak, ISBN'e bağlıdır ve tüm okullarda geçerlidir (public.books ortak tablo)
router.post(
  "/isbn/:isbn/cover",
  coverUpload.single("cover"),
  coverController.uploadCoverByIsbn
);
router.delete("/isbn/:isbn/cover", coverController.deleteCoverByIsbn);

router.get("/", bookController.getAllBooks);
router.get("/isbn/:isbn", bookController.getBookByIsbn);
router.get("/:id", bookController.getBookById);
router.post("/", bookController.createBook);
router.patch("/:id", bookController.updateBook);
router.delete("/:id", bookController.deleteBook);

module.exports = router;
