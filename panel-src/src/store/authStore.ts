import { create } from "zustand";
import { persist, createJSONStorage } from "zustand/middleware";
import type { User, School } from "@/types";

interface AuthState {
  token: string | null;
  user: User | null;
  school: School | null;
  isAuthenticated: boolean;
  login: (token: string, user: User, school: School) => void;
  logout: () => void;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      token: null,
      user: null,
      school: null,
      isAuthenticated: false,
      login: (token, user, school) => {
        // localStorage'a da yaz (axios interceptor'ı oradan okuyor)
        localStorage.setItem("auth_token", token);
        localStorage.setItem("auth_user", JSON.stringify(user));
        localStorage.setItem("auth_school", JSON.stringify(school));
        set({ token, user, school, isAuthenticated: true });
      },
      logout: () => {
        localStorage.removeItem("auth_token");
        localStorage.removeItem("auth_user");
        localStorage.removeItem("auth_school");
        set({ token: null, user: null, school: null, isAuthenticated: false });
      },
    }),
    {
      name: "library-auth",
      storage: createJSONStorage(() => localStorage),
    }
  )
);
