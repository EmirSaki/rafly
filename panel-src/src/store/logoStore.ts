import { create } from "zustand";
import { getSchoolLogo, uploadSchoolLogo, deleteSchoolLogo } from "@/api/schoolLogo";

interface LogoState {
  logoUrl: string | null;
  loading: boolean;
  fetchLogo: (schoolCode: string) => Promise<void>;
  uploadLogo: (schoolCode: string, file: File) => Promise<void>;
  removeLogo: (schoolCode: string) => Promise<void>;
  clearLogo: () => void;
}

export const useLogoStore = create<LogoState>((set) => ({
  logoUrl: null,
  loading: false,

  fetchLogo: async (schoolCode) => {
    set({ loading: true });
    try {
      const url = await getSchoolLogo(schoolCode);
      set({ logoUrl: url });
    } catch {
      set({ logoUrl: null });
    } finally {
      set({ loading: false });
    }
  },

  uploadLogo: async (schoolCode, file) => {
    set({ loading: true });
    try {
      const url = await uploadSchoolLogo(schoolCode, file);
      set({ logoUrl: url });
    } finally {
      set({ loading: false });
    }
  },

  removeLogo: async (schoolCode) => {
    set({ loading: true });
    try {
      await deleteSchoolLogo(schoolCode);
      set({ logoUrl: null });
    } finally {
      set({ loading: false });
    }
  },

  clearLogo: () => set({ logoUrl: null }),
}));
