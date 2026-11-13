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
  isValilikBook?: boolean;
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
  book_name?: string;
  authors?: string[];
  publisher?: string;
  categories?: string[];
  page_count?: number;
  is_valilik_book?: boolean;
  shelves?: string[];
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

export async function getSchoolBooksPage(schoolCode: string, page: number, search: string) {
 const { data } = await apiClient.get<{ data: SchoolBook[]; pagination: { total: number; totalPages: number } }>(`/api/schools/${encodeURIComponent(schoolCode)}/books`, { params: { page, limit: 20, search } });
 return data;
}


// Kapak ISBN'e bağlıdır: aynı ISBN'li kitabı bulunduran tüm okullarda görünür.
export async function uploadBookCover(isbn: string, image: Blob, fileName = "kapak.jpg") {
  const formData = new FormData();
  formData.append("cover", image, fileName);
  const { data } = await apiClient.post<
    ApiResponse<{ isbn: string; cover_url: string; updatedBooks: number }>
  >(`/api/books/isbn/${encodeURIComponent(isbn)}/cover`, formData, {
    headers: { "Content-Type": "multipart/form-data" },
  });
  return data;
}

export async function deleteBookCover(isbn: string) {
  const { data } = await apiClient.delete<ApiResponse<unknown>>(
    `/api/books/isbn/${encodeURIComponent(isbn)}/cover`
  );
  return data;
}
