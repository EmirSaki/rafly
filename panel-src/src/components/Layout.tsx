import { useState } from "react";
import { Outlet, useLocation } from "react-router-dom";
import { Menu } from "lucide-react";
import { Sidebar } from "./Sidebar";

export function Layout() {
  const [mobileOpen, setMobileOpen] = useState(false);
  const location = useLocation();
  const page = location.pathname.replace(/^\//, "") || "dashboard";

  return (
    <div className="rafly-shell flex h-screen overflow-hidden">
      <Sidebar mobileOpen={mobileOpen} onClose={() => setMobileOpen(false)} />

      {/* min-w-0: icerigin daralabilmesi + genis tablolarin yatay kaymasi icin sart */}
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        {/* Mobil ust bar (sadece kucuk ekran) */}
        <header className="flex items-center gap-3 h-14 px-4 border-b bg-white shrink-0">
          <button
            onClick={() => setMobileOpen((open) => !open)}
            aria-label="Menuyu ac"
            className="p-2 -ml-2 rounded-md text-muted-foreground hover:bg-accent hover:text-accent-foreground transition-colors"
          >
            <Menu size={22} />
          </button>
          <span className="font-bold text-primary">Rafly</span>
        </header>

        <main className="flex-1 overflow-y-auto">
          <div className={`panel-page panel-page-${page} w-full mx-auto p-4 md:p-8`}>
            <Outlet />
          </div>
        </main>
      </div>
    </div>
  );
}
