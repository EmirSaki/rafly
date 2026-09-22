import { apiClient } from "./client";

export interface Announcement {
  id: number;
  school_code: string;
  title: string;
  content: string;
  image_url?: string | null;
  image_urls?: string[];
  image_count?: number;
  target_type: "all" | "school_level" | "class" | "section";
  target_values: string[];
  start_date: string;
  end_date: string;
  sender_name: string;
  created_at: string;
}

export interface CreateAnnouncementPayload {
  schoolCode: string;
  title: string;
  content: string;
  target_type: "all" | "school_level" | "class" | "section";
  target_values: string[];
  start_date: string;
  end_date: string;
}

export function getAnnouncementImages(a: Announcement): string[] {
  if (a.image_urls && a.image_urls.length > 0) return a.image_urls;
  if (a.image_url) return [a.image_url];
  return [];
}

export async function getAnnouncements(schoolCode: string) {
  const { data } = await apiClient.get<{ success: boolean; data: Announcement[] }>(
    "/api/announcements",
    { params: { schoolCode } }
  );
  return data.data ?? [];
}

export async function createAnnouncement(
  payload: CreateAnnouncementPayload,
  imageFiles?: File[]
) {
  const formData = new FormData();
  formData.append("schoolCode", payload.schoolCode);
  formData.append("title", payload.title);
  formData.append("content", payload.content);
  formData.append("target_type", payload.target_type);
  formData.append("target_values", JSON.stringify(payload.target_values));
  formData.append("start_date", payload.start_date);
  formData.append("end_date", payload.end_date);

  if (imageFiles && imageFiles.length > 0) {
    for (const file of imageFiles) {
      formData.append("images", file);
    }
  }

  const { data } = await apiClient.post<{ success: boolean; data: Announcement; message?: string }>(
    "/api/announcements",
    formData,
    { headers: { "Content-Type": undefined } }
  );
  return data;
}

export async function getAnnouncementImagesById(id: number) {
  const { data } = await apiClient.get<{ success: boolean; data: string[] }>(
    `/api/announcements/${id}/images`
  );
  return data.data ?? [];
}

export async function deleteAnnouncement(id: number) {
  const { data } = await apiClient.delete<{ success: boolean; message?: string }>(
    `/api/announcements/${id}`
  );
  return data;
}
