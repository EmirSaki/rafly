import { apiClient } from "./client";
import type { ApiResponse, Student } from "@/types";

export interface StudentsQuery {
  schoolCode: string;
  school_level?: string;
}

export async function getStudents(params: StudentsQuery) {
  const { data } = await apiClient.get<ApiResponse<Student[]>>("/api/students", {
    params,
  });
  return data.data ?? [];
}

export interface CreateStudentPayload {
  schoolCode: string;
  student_number: string;
  full_name: string;
  class_name: string;
  class_code?: string;
  school_level: "ilkokul" | "ortaokul" | "lise" | "hazırlık" | "diğer";
}

export async function createStudent(payload: CreateStudentPayload) {
  const { data } = await apiClient.post<ApiResponse<Student>>(
    "/api/students",
    payload
  );
  return data;
}

export async function deleteStudent(params: {
  schoolCode: string;
  student_number: string;
  school_level: string;
}) {
  const { data } = await apiClient.delete<ApiResponse<null>>("/api/students", {
    params,
  });
  return data;
}

export async function importStudentsFromExcel(
  schoolCode: string,
  file: File
) {
  const formData = new FormData();
  formData.append("file", file);

  const { data } = await apiClient.post<
    ApiResponse<Student[]> & { count: number; class_name?: string }
  >(`/api/students/import?schoolCode=${encodeURIComponent(schoolCode)}`, formData, {
    headers: {
      "Content-Type": "multipart/form-data",
    },
  });

  return data;
}
