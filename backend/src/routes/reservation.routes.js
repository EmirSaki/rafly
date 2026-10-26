const express = require("express");
const router = express.Router();
const reservationController = require("../controllers/reservation.controller");

router.post("/loan-by-student", reservationController.loanBookByStudent);

router.get("/", reservationController.getAllReservations);
router.get("/:id", reservationController.getReservationById);
router.post("/", reservationController.createReservation);

router.patch("/:id/loan", reservationController.loanReservation);
router.patch("/:id/reject", reservationController.rejectReservation);
router.patch("/:id/return", reservationController.returnReservation);

router.delete("/:id", reservationController.deleteReservation);

module.exports = router;
