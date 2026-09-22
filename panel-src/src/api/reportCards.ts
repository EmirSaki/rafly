import { apiClient } from "./client";

export interface ReportCardQuery {
  schoolCode: string;
  /** Boş bırakılırsa tüm seviyeler */
  school_level?: string;
  /** Sınıf düzeyi, ör. "6" */
  grade?: string;
  /** Şube, ör. "6A" */
  class_name?: string;
  /** Dönem başlangıcı, YYYY-AA-GG. Bu tarihten önce iade edilenler sayılmaz. */
  startDate?: string;
  /** Dönem bitişi, YYYY-AA-GG. Bu gün dahildir. */
  endDate?: string;
  /** "zip" = sınıf klasörlü, öğrenci başına ayrı PDF; "pdf" = tek birleşik dosya */
  format?: "zip" | "pdf";
}

export interface ReportCardSummary {
  period: { startDate: string | null; endDate: string | null; label: string };
  studentCount: number;
  readingStudentCount: number;
  totalBooks: number;
  classCount: number;
  topReaders: Array<{
    student_number: string;
    full_name: string;
    class_name: string;
    school_level: string;
    count: number;
    schoolRank: number | null;
  }>;
}

/**
 * Karne üretmeden özet verir. Sayılar karnelerdekiyle **aynı hesaptan**
 * geldiği için ekranda gösterilen ile PDF'e yazılan hiç ayrışmaz.
 */
export async function getReportCardSummary(
  params: Omit<ReportCardQuery, "format">
): Promise<ReportCardSummary> {
  const { schoolCode, ...query } = params;
  const { data } = await apiClient.get(`/api/schools/${schoolCode}/report-cards`, {
    params: { ...query, format: "json" },
  });
  return data.data as ReportCardSummary;
}

export interface ReportCardFile {
  blob: Blob;
  fileName: string;
}

/**
 * Karneleri indirir. Sıralamalar her zaman okulun tamamı üzerinden
 * hesaplanır; filtreler yalnızca kimin karnesinin basılacağını belirler.
 */
export async function downloadReportCards(
  params: ReportCardQuery
): Promise<ReportCardFile> {
  const { schoolCode, ...query } = params;

  const response = await apiClient.get(`/api/schools/${schoolCode}/report-cards`, {
    params: query,
    responseType: "blob",
    // Yüzlerce karne üretimi varsayılan 30 sn'yi aşabilir
    timeout: 180000,
  });

  const disposition = String(response.headers["content-disposition"] ?? "");
  const match = disposition.match(/filename="?([^";]+)"?/i);
  const fallback = `karneler-${schoolCode}.${query.format === "pdf" ? "pdf" : "zip"}`;

  return {
    blob: response.data as Blob,
    fileName: match ? match[1] : fallback,
  };
}

/** Sunucu hata döndürdüğünde gövde blob olarak gelir; mesajı çıkarır. */
export async function readBlobErrorMessage(error: unknown): Promise<string | null> {
  const response = (error as { response?: { data?: unknown } })?.response;
  const data = response?.data;
  if (!(data instanceof Blob)) return null;

  try {
    const text = await data.text();
    const parsed = JSON.parse(text) as { message?: string };
    return parsed.message ?? null;
  } catch {
    return null;
  }
}

export function saveBlob(blob: Blob, fileName: string) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = fileName;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}
