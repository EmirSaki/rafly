const express = require("express");
const router = express.Router();
const userController = require("../controllers/user.controller");

const { requireAdminKey } = require("../middlewares/staff.middleware");

router.post("/login", userController.loginUser);

// Kullanıcı yönetimi (tüm kullanıcıların e-posta/telefon/şifre alanlarını
// döndürür ve değiştirir) yalnızca platform yöneticisine açıktır. Hiçbir
// istemci bu uçları kullanmaz; ADMIN_API_KEY tanımlı değilse tamamen kapalıdır.
router.get("/", requireAdminKey, userController.getAllUsers);
router.get("/:id", requireAdminKey, userController.getUserById);
router.post("/", requireAdminKey, userController.createUser);
router.patch("/:id", requireAdminKey, userController.updateUser);
router.delete("/:id", requireAdminKey, userController.deleteUser);

module.exports = router;