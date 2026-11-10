const express = require("express");
const multer = require("multer");
const router = express.Router();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowed = ["image/png", "image/jpeg", "image/jpg", "image/webp"];
    if (allowed.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error("Sadece PNG, JPG ve WebP formatları desteklenir"));
    }
  },
});

const {
  getAnnouncements,
  getAnnouncementImages,
  createAnnouncement,
  deleteAnnouncement,
} = require("../controllers/announcement.controller");
const { requireStaff } = require("../middlewares/staff.middleware");

router.get("/", getAnnouncements);
router.get("/:id/images", getAnnouncementImages);
router.post("/", upload.array("images", 10), createAnnouncement);
// Silme: personel oturumu gerekir ve yalnızca kendi okulunun duyurusu silinebilir.
router.delete("/:id", requireStaff, deleteAnnouncement);

module.exports = router;
