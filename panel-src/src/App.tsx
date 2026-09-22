import { Routes, Route, Navigate } from "react-router-dom";
import { Layout } from "./components/Layout";
import { ProtectedRoute } from "./components/ProtectedRoute";
import { LoginPage } from "./pages/Login";
import { DashboardPage } from "./pages/Dashboard";
import { StudentsPage } from "./pages/Students";
import { BooksPage } from "./pages/Books";
import { ReservationsPage } from "./pages/Reservations";
import { QuickLoanPage } from "./pages/QuickLoan";
import { ReadingStatsPage } from "./pages/ReadingStats";
import { ReportCardsPage } from "./pages/ReportCards";
import { AnnouncementsPage } from "./pages/Announcements";

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />

      <Route
        element={
          <ProtectedRoute>
            <Layout />
          </ProtectedRoute>
        }
      >
        <Route index element={<DashboardPage />} />
        <Route path="/students" element={<StudentsPage />} />
        <Route path="/books" element={<BooksPage />} />
        <Route path="/reservations" element={<ReservationsPage />} />
        <Route path="/quick-loan" element={<QuickLoanPage />} />
        <Route path="/reading-stats" element={<ReadingStatsPage />} />
        <Route path="/report-cards" element={<ReportCardsPage />} />
        <Route path="/announcements" element={<AnnouncementsPage />} />
      </Route>

      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
