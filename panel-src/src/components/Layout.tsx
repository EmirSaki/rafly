import { useState } from "react";
import { Outlet } from "react-router-dom";
import { Menu } from "lucide-react";
import { Sidebar } from "./Sidebar";

export function Layout() {
  const [mobileOpen, setMobileOpen] = useState(false);

  return (
    <div className="flex h-screen overflow-hidden bg-gray-50">
      <Sidebar mobileOpen={mobileOpen} onClose={() => setMobileOpen(false)} />

      {/* min-w-0: icerigin daralabilmesi + genis tablolarin yatay kaymasi icin sart */}
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        {/* Mobil ust bar (sadece kucuk ekran) */}
        <header className="md:hidden flex items-center gap-3 h-14 px-4 border-b bg-white shrink-0">
          <button
            onClick={() => setMobileOpen(true)}
            aria-label="Menuyu ac"
            className="p-2 -ml-2 rounded-md text-muted-foreground hover:bg-accent hover:text-accent-foreground transition-colors"
          >
            <Menu size={22} />
          </button>
          <span className="font-bold text-primary">Rafly</span>
        </header>

        <main className="flex-1 overflow-y-auto">
          <div className="w-full max-w-7xl mx-auto p-4 md:p-8">
            <Outlet />
          </div>
        </main>
      </div>
    </div>
  );
}
