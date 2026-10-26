const express = require("express");
const cors = require("cors");
const morgan = require("morgan");
const pool = require("./config/db");

const bookRoutes = require("./routes/book.routes");
const userRoutes = require("./routes/user.routes");
const reservationRoutes = require("./routes/reservation.routes");
const adminRoutes = require("./routes/admin.routes");
const schoolRoutes = require("./routes/school.routes");
const studentRoutes = require("./routes/student.routes");
const announcementRoutes = require("./routes/announcement.routes");
const { getStudents } = require("./controllers/student.controller");
const { loanBookByStudent } = require("./controllers/reservation.controller");

const app = express();
const BUILD_MARKER = "plain-password-final-2026-05-26";
const mountedRouters = [
  { prefix: "/api/books", router: bookRoutes },
  { prefix: "/api/users", router: userRoutes },
  { prefix: "/api/reservations", router: reservationRoutes },
  { prefix: "/api/admin", router: adminRoutes },
  { prefix: "/api/schools", router: schoolRoutes },
  { prefix: "/api/students", router: studentRoutes },
  { prefix: "/api/announcements", router: announcementRoutes },
];

app.use(
  cors({
    origin: process.env.CORS_ORIGIN || "*",
    methods: ["GET", "POST", "PATCH", "DELETE"],
    allowedHeaders: ["Content-Type", "Authorization"],
  })
);

app.use(morgan("dev"));
app.use(express.json({ limit: "50mb" }));

app.use((req, res, next) => {
  req.setTimeout(45000, () => {
    console.error("[TIMEOUT]", req.method, req.originalUrl);
    if (!res.headersSent) {
      res.status(408).json({
        success: false,
        message: "Request timeout",
      });
    }
  });
  next();
});

app.get("/", (req, res) => {
  res.json({
    success: true,
    message: "Library API is running",
    build: BUILD_MARKER,
  });
});

app.get("/health", async (req, res) => {
  try {
    await pool.query("SELECT 1");
    res.status(200).json({
      success: true,
      db: true,
      uptime: process.uptime(),
      build: BUILD_MARKER,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      db: false,
      error: error.message,
      build: BUILD_MARKER,
    });
  }
});

app.get("/debug/routes", (req, res) => {
  const routes = [];

  function collectRoutes(stack, prefix = "") {
    for (const layer of stack || []) {
      if (layer.route) {
        routes.push({
          path: `${prefix}${layer.route.path}`,
          methods: Object.keys(layer.route.methods),
        });
        continue;
      }

      if (layer.handle?.stack) {
        collectRoutes(layer.handle.stack, prefix);
      }
    }
  }

  collectRoutes(app.router?.stack || app._router?.stack || []);
  for (const mount of mountedRouters) {
    collectRoutes(mount.router.stack, mount.prefix);
  }

  res.json({
    success: true,
    build: BUILD_MARKER,
    routes,
  });
});

app.use("/api/books", bookRoutes);
app.use("/api/users", userRoutes);
app.post("/api/reservations/loan-by-student", loanBookByStudent);
app.use("/api/reservations", reservationRoutes);
app.use("/api/admin", adminRoutes);
app.use("/api/schools", schoolRoutes);
app.get("/api/students", getStudents);
app.use("/api/students", studentRoutes);
app.use("/api/announcements", announcementRoutes);

app.use((err, req, res, next) => {
  console.error("[UNHANDLED_ERROR]", err);

  if (res.headersSent) {
    return next(err);
  }

  res.status(err.statusCode || 500).json({
    success: false,
    message: err.message || "Internal server error",
  });
});

module.exports = app;
