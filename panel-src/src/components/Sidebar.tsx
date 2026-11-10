import { useEffect, useRef, useState } from "react";
import { NavLink, useNavigate } from "react-router-dom";
import {
  LayoutDashboard,
  Users,
  BookOpen,
  ClipboardList,
  Zap,
  LogOut,
  TrendingUp,
  Megaphone,
  Camera,
  Trash2,
  Award,
  X,
  BookMarked,
} from "lucide-react";
import toast from "react-hot-toast";
import { useAuthStore } from "@/store/authStore";
import { useLogoStore } from "@/store/logoStore";
import { cn } from "@/lib/utils";

const navItems = [
  { to: "/", label: "Anasayfa", icon: LayoutDashboard, end: true },
  { to: "/quick-loan", label: "Hızlı Ödünç", icon: Zap },
  { to: "/students", label: "Öğrenciler", icon: Users },
  { to: "/books", label: "Kitaplar", icon: BookOpen },
  { to: "/reservations", label: "Rezervasyonlar", icon: ClipboardList },
  { to: "/reading-stats", label: "Okuma İstatistikleri", icon: TrendingUp },
  { to: "/report-cards", label: "Karne Oluştur", icon: Award },
  { to: "/announcements", label: "Bilgilendirme", icon: Megaphone },
];

interface SidebarProps {
  mobileOpen?: boolean;
  onClose?: () => void;
}

export function Sidebar({ mobileOpen = false, onClose }: SidebarProps) {
  const { user, school, logout } = useAuthStore();
  const { logoUrl, loading, fetchLogo, uploadLogo, removeLogo } = useLogoStore();
  const navigate = useNavigate();
  const [statsOpen, setStatsOpen] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const isTeacher =
    user?.user_role === "teacher" || user?.user_role === "admin";

  useEffect(() => {
    if (school?.school_code) {
      fetchLogo(school.school_code);
    }
  }, [school?.school_code, fetchLogo]);

  function handleLogout() {
    useLogoStore.getState().clearLogo();
    logout();
    navigate("/login", { replace: true });
  }

  async function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file || !school?.school_code) return;

    // Reset input
    e.target.value = "";

    if (file.size > 2 * 1024 * 1024) {
      toast.error("Logo dosyası en fazla 2MB olabilir");
      return;
    }

    try {
      await uploadLogo(school.school_code, file);
      toast.success("Okul logosu güncellendi");
    } catch {
      toast.error("Logo yüklenemedi");
    }
  }

  async function handleRemoveLogo() {
    if (!school?.school_code) return;
    try {
      await removeLogo(school.school_code);
      toast.success("Okul logosu kaldırıldı");
    } catch {
      toast.error("Logo silinemedi");
    }
  }

  return (
    <>
      {/* Mobil karartma katmani */}
      {mobileOpen && (
        <div
          className="fixed inset-0 z-40 bg-black/40"
          onClick={onClose}
          aria-hidden="true"
        />
      )}

      <aside
        className={cn(
          "rafly-sidebar w-60 border-r flex flex-col shrink-0 z-50",
          // Mobil: soldan kayan cekmece. Masaustu (md+): sabit ve her zaman gorunur.
          "fixed inset-y-0 left-0 h-full transform transition-transform duration-200 ease-in-out",
          mobileOpen ? "translate-x-0" : "-translate-x-full"
        )}
      >
      <div className="sidebar-brand p-6 border-b">
        {/* Mobil kapatma butonu */}
        <div className="flex justify-end -mt-2 -mr-2 mb-1">
          <button
            onClick={onClose}
            aria-label="Menuyu kapat"
            className="p-1.5 rounded-md text-muted-foreground hover:bg-accent hover:text-accent-foreground transition-colors"
          >
            <X size={18} />
          </button>
        </div>
        <div className="rafly-wordmark"><BookMarked size={29} strokeWidth={1.8} /><span>Rafly</span></div>
        <div className="school-identity">
          <div className="school-logo-wrap">
            {logoUrl ? <img src={logoUrl} alt={`${school?.school_name || "Okul"} logosu`} className="school-logo" /> : <BookOpen size={31} strokeWidth={1.5} aria-hidden="true" />}
          </div>
          <p className="school-name" title={school?.school_name || "Okul adı"}>{school?.school_name || "Okul Kütüphanesi"}</p>
          <p className="school-caption">Kütüphane Yönetimi</p>
        </div>
        <div className="school-logo-actions">
          {isTeacher && (
            <div className="flex flex-col gap-0.5">
              <button
                onClick={() => fileInputRef.current?.click()}
                disabled={loading}
                className="p-1 rounded transition-colors"
                title="Logo yükle / değiştir"
              >
                <Camera size={14} />
              </button>
              {logoUrl && (
                <button
                  onClick={handleRemoveLogo}
                  disabled={loading}
                  className="p-1 rounded transition-colors"
                  title="Logoyu kaldır"
                >
                  <Trash2 size={14} />
                </button>
              )}
            </div>
          )}
          <input
            ref={fileInputRef}
            type="file"
            accept="image/png,image/jpeg,image/webp,image/svg+xml"
            className="hidden"
            onChange={handleFileChange}
          />
        </div>
      </div>

      <nav className="sidebar-nav flex-1 p-3 space-y-1">
        {navItems.map((item) => item.to === "/reading-stats" ? <div key={item.to} className="sidebar-stats-group"><button type="button" className="sidebar-link flex items-center gap-3 w-full" aria-expanded={statsOpen} onClick={() => setStatsOpen(!statsOpen)}><TrendingUp size={18} /><span>Kütüphane İstatistikleri</span><span>{statsOpen ? "⌃" : "⌄"}</span></button>{statsOpen && <div className="sidebar-submenu"><NavLink to="/reading-stats" onClick={onClose}>Okuma İstatistikleri</NavLink><NavLink to="/book-stats" onClick={onClose}>Kitap İstatistikleri</NavLink></div>}</div> : (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.end}
            onClick={onClose}
            className={({ isActive }) =>
              cn(
                "sidebar-link flex items-center gap-3 px-3 py-2 rounded-md text-sm font-medium transition-colors",
                isActive
                  ? "sidebar-link-active"
                  : "sidebar-link-idle"
              )
            }
          >
            <item.icon size={18} />
            <span>{item.label}</span>
          </NavLink>
        ))}
      </nav>

      <div className="sidebar-footer p-3 border-t">
        {user && (
          <div className="px-3 py-2 mb-2">
            <p className="text-xs text-muted-foreground">Giriş yapan</p>
            <p className="text-sm font-medium truncate">
              {user.user_name} {user.user_surname}
            </p>
            <p className="text-[10px] text-muted-foreground capitalize">{user.user_role}</p>
          </div>
        )}
        <button
          onClick={handleLogout}
          className="w-full flex items-center gap-3 px-3 py-2 rounded-md text-sm font-medium text-destructive hover:bg-destructive/10 transition-colors"
        >
          <LogOut size={18} />
          Çıkış Yap
        </button>
      </div>
      </aside>
    </>
  );
}
