import axios, { AxiosError } from "axios";

const baseURL =
  (import.meta.env.VITE_API_BASE_URL as string | undefined) ||
  "https://library-api-346058361420.europe-west1.run.app";

export const apiClient = axios.create({
  baseURL,
  timeout: 30000,
  headers: {
    "Content-Type": "application/json",
  },
});

// Her isteğe localStorage'daki JWT'yi ekle
apiClient.interceptors.request.use((config) => {
  const token = localStorage.getItem("auth_token");
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// 401 dönerse otomatik logout
apiClient.interceptors.response.use(
  (response) => response,
  (error: AxiosError) => {
    if (error.response?.status === 401) {
      // Token geçersizse temizle (login sayfasına yönlendirme App.tsx'de)
      localStorage.removeItem("auth_token");
      localStorage.removeItem("auth_user");
      localStorage.removeItem("auth_school");
    }
    return Promise.reject(error);
  }
);

// Axios hatasının HTTP durum kodunu döndür (yoksa undefined)
export function getErrorStatus(error: unknown): number | undefined {
  if (axios.isAxiosError(error)) return error.response?.status;
  return undefined;
}

// Backend tarafından dönen mesaj string'ini çıkar
export function getErrorMessage(error: unknown): string {
  if (axios.isAxiosError(error)) {
    const data = error.response?.data as { message?: string } | undefined;
    if (data?.message) return data.message;
    if (error.message) return error.message;
  }
  if (error instanceof Error) return error.message;
  return "Bilinmeyen bir hata oluştu";
}

export { baseURL };
