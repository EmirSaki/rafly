import { apiClient } from "./client";
import type { ApiResponse, Reservation, ReservationStatus } from "@/types";

export interface ReservationsQuery {
  schoolCode: string;
  status?: ReservationStatus | "";
  studentNumber?: string;
  startDate?: string;
  endDate?: string;
}

export async function getReservations(params: ReservationsQuery) {
  const { data } = await apiClient.get<ApiResponse<Reservation[]>>(
    "/api/reservations",
    { params }
  );
  return data.data ?? [];
}

export async function getReservationById(id: number, schoolCode: string) {
  const { data } = await apiClient.get<ApiResponse<Reservation>>(
    `/api/reservations/${id}`,
    { params: { schoolCode } }
  );
  return data.data;
}

export interface LoanByStudentPayload {
  schoolCode: string;
  isbn: string;
  student_number: string;
  school_level?: string;
  due_date?: string;
}

export async function loanBookByStudent(payload: LoanByStudentPayload) {
  const { data } = await apiClient.post<ApiResponse<Reservation>>(
    "/api/reservations/loan-by-student",
    payload
  );
  return data;
}

export async function approveLoan(
  id: number,
  schoolCode: string,
  due_date?: string
) {
  const { data } = await apiClient.patch<ApiResponse<Reservation>>(
    `/api/reservations/${id}/loan`,
    { schoolCode, due_date }
  );
  return data;
}

export async function rejectReservation(id: number, schoolCode: string) {
  const { data } = await apiClient.patch<ApiResponse<Reservation>>(
    `/api/reservations/${id}/reject`,
    { schoolCode }
  );
  return data;
}

export async function returnReservation(id: number, schoolCode: string) {
  const { data } = await apiClient.patch<ApiResponse<Reservation>>(
    `/api/reservations/${id}/return`,
    { schoolCode }
  );
  return data;
}

export async function deleteReservation(id: number, schoolCode: string) {
  const { data } = await apiClient.delete<ApiResponse<unknown>>(
    `/api/reservations/${id}`,
    { params: { schoolCode } }
  );
  return data;
}
