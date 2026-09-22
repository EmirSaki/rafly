import { apiClient } from "./client";
import type { ApiResponse, LoginResponse } from "@/types";

export interface LoginPayload {
  schoolCode: string;
  email: string;
  password: string;
}

export async function loginUser(payload: LoginPayload) {
  const { data } = await apiClient.post<
    ApiResponse<LoginResponse> & { token: string }
  >("/api/users/login", payload);
  return data;
}
