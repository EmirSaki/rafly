import { useEffect, useRef } from "react";
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
          className="fixed inset-0 z-40 bg-black/40 md:hidden"
          onClick={onClose}
          aria-hidden="true"
        />
      )}

      <aside
        className={cn(
          "w-60 bg-white border-r flex flex-col shrink-0 z-50",
          // Mobil: soldan kayan cekmece. Masaustu (md+): sabit ve her zaman gorunur.
          "fixed inset-y-0 left-0 h-full transform transition-transform duration-200 ease-in-out",
          "md:static md:h-full md:translate-x-0 md:transition-none",
          mobileOpen ? "translate-x-0" : "-translate-x-full"
        )}
      >
      <div className="p-6 border-b">
        {/* Mobil kapatma butonu */}
        <div className="flex justify-end md:hidden -mt-2 -mr-2 mb-1">
          <button
            onClick={onClose}
            aria-label="Menuyu kapat"
            className="p-1.5 rounded-md text-muted-foreground hover:bg-accent hover:text-accent-foreground transition-colors"
          >
            <X size={18} />
          </button>
        </div>
        <div className="flex items-center gap-2.5">
          {logoUrl ? (
            <img
              src={logoUrl}
              alt="Okul Logosu"
              className="w-10 h-10 rounded-md object-contain"
              onError={(e) => {
                (e.target as HTMLImageElement).style.display = "none";
              }}
            />
          ) : (
            <img
              src="/logo.png"
              alt="Rafly"
              className="w-10 h-10 rounded-md object-contain"
              onError={(e) => {
                (e.target as HTMLImageElement).style.display = "none";
              }}
            />
          )}
          <div className="flex-1 min-w-0">
            <h1 className="text-base font-bold leading-tight text-primary truncate">
              {logoUrl ? school?.school_name || "Rafly" : "Rafly"}
            </h1>
            <p className="text-[10px] text-muted-foreground leading-tight uppercase tracking-wide">
              {logoUrl ? "Kütüphane Sistemi" : "Library Automation"}
            </p>
          </div>
          {isTeacher && (
            <div className="flex flex-col gap-0.5">
              <button
                onClick={() => fileInputRef.current?.click()}
                disabled={loading}
                className="p-1 rounded text-muted-foreground hover:text-primary hover:bg-primary/5 transition-colors"
                title="Logo yükle / değiştir"
              >
                <Camera size={14} />
              </button>
              {logoUrl && (
                <button
                  onClick={handleRemoveLogo}
                  disabled={loading}
                  className="p-1 rounded text-muted-foreground hover:text-destructive hover:bg-destructive/5 transition-colors"
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
        {school && (
          <div className="mt-4 px-2 py-2 bg-muted/50 rounded-md">
            <p className="text-xs text-muted-foreground">Okul</p>
            <p className="text-sm font-medium truncate">{school.school_name}</p>
            <p className="text-[10px] text-muted-foreground">
              Kod: {school.school_code}
            </p>
          </div>
        )}
      </div>

      <nav className="flex-1 p-3 space-y-1 overflow-y-auto">
        {navItems.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.end}
            onClick={onClose}
            className={({ isActive }) =>
              cn(
                "flex items-center gap-3 px-3 py-2 rounded-md text-sm font-medium transition-colors",
                isActive
                  ? "bg-primary text-primary-foreground"
                  : "text-muted-foreground hover:bg-accent hover:text-accent-foreground"
              )
            }
          >
            <item.icon size={18} />
            <span>{item.label}</span>
          </NavLink>
        ))}
      </nav>

      <div className="p-3 border-t">
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
