import { apiClient } from "./client";

interface LogoResponse {
  success: boolean;
  data?: { logo_url: string | null };
  message?: string;
}

export async function getSchoolLogo(schoolCode: string): Promise<string | null> {
  try {
    const { data } = await apiClient.get<LogoResponse>(
      `/api/schools/${schoolCode}/logo`
    );
    return data?.data?.logo_url ?? null;
  } catch {
    return null;
  }
}

export async function uploadSchoolLogo(
  schoolCode: string,
  file: File
): Promise<string | null> {
  const formData = new FormData();
  formData.append("logo", file);

  const { data } = await apiClient.post<LogoResponse>(
    `/api/schools/${schoolCode}/logo`,
    formData,
    {
      headers: { "Content-Type": "multipart/form-data" },
    }
  );

  return data?.data?.logo_url ?? null;
}

export async function deleteSchoolLogo(schoolCode: string): Promise<void> {
  await apiClient.delete(`/api/schools/${schoolCode}/logo`);
}
