import { apiClient } from "./client";
import type {
  ApiResponse,
  Book,
  SchoolBook,
  IsbnLookupResult,
} from "@/types";

export async function getAllBooks() {
  const { data } = await apiClient.get<ApiResponse<Book[]>>("/api/books");
  return data.data ?? [];
}

export async function getBookByIsbn(isbn: string) {
  const { data } = await apiClient.get<ApiResponse<IsbnLookupResult>>(
    `/api/books/isbn/${encodeURIComponent(isbn)}`
  );
  return data.data;
}

export interface CreateBookPayload {
  title: string;
  authors: string[] | string;
  publisher?: string;
  categories?: string[] | string;
  isbn: string;
  pageCount?: number;
  volumeCount?: number;
  physicalDescription?: string;
}

export async function createBook(payload: CreateBookPayload) {
  const { data } = await apiClient.post<ApiResponse<Book[]>>(
    "/api/books",
    payload
  );
  return data;
}

// Okul envanteri
export async function getSchoolBooks(schoolCode: string, search?: string) {
  const { data } = await apiClient.get<ApiResponse<SchoolBook[]>>(
    `/api/schools/${encodeURIComponent(schoolCode)}/books`,
    { params: { ...(search ? { search } : {}), limit: 10000 } }
  );
  return data.data ?? [];
}

export interface AddBookToSchoolPayload {
  schoolCode: string;
  isbn: string;
  title: string;
  authors: string[] | string;
  publisher?: string;
  categories?: string[] | string;
  quantity: number;
  pageCount?: number;
  volumeCount?: number;
}

export async function addBookToSchool({
  schoolCode,
  ...body
}: AddBookToSchoolPayload) {
  const { data } = await apiClient.post<ApiResponse<SchoolBook[]>>(
    `/api/schools/${encodeURIComponent(schoolCode)}/books`,
    body
  );
  return data;
}

export interface UpdateSchoolBookPayload {
  quantity: number;
  authors?: string[];
  publisher?: string;
  categories?: string[];
  page_count?: number;
}

export async function updateSchoolBookQuantity(
  schoolCode: string,
  bookId: number,
  payload: UpdateSchoolBookPayload
) {
  const { data } = await apiClient.patch<ApiResponse<SchoolBook>>(
    `/api/schools/${encodeURIComponent(schoolCode)}/books/${bookId}`,
    payload
  );
  return data;
}

export async function deleteSchoolBook(schoolCode: string, bookId: number) {
  const { data } = await apiClient.delete<ApiResponse<unknown>>(
    `/api/schools/${encodeURIComponent(schoolCode)}/books/${bookId}`
  );
  return data;
}
