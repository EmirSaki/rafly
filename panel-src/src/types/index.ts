// Backend API tip tanımları

export interface ApiResponse<T> {
  success: boolean;
  message?: string;
  data?: T;
  token?: string;
}

export interface User {
  user_id: number;
  user_name: string;
  user_surname: string;
  email: string | null;
  user_role: "admin" | "teacher" | "student";
  school_id: number;
}

export interface School {
  school_id: number;
  school_code: string;
  school_name: string;
  schema_name?: string;
}

export interface LoginResponse {
  user: User;
  school: School;
}

export interface Student {
  student_id?: number;
  student_number: string;
  full_name: string;
  class_name: string;
  class_code: string | null;
  school_level: "ilkokul" | "ortaokul" | "lise" | "hazırlık" | "diğer" | null;
  email?: string | null;
  phone?: string | null;
  password?: string | null;
  created_at?: string;
}

export interface Book {
  book_id: number;
  book_name: string;
  book_writer: string;
  book_genre: string | null;
  publisher: string | null;
  isbn: string;
  page_count: number | null;
  book_quantity?: number;
  book_available_quantity?: number;
}

export interface SchoolBook {
  book_id: number;
  title: string;
  authors: string[];
  isbn: string;
  publisher?: string | null;
  categories?: string[];
  page_count?: number | null;
  quantity: number;
  available_quantity: number;
  total_quantity?: number;
  cover_url?: string | null;
}

export type ReservationStatus =
  | "pending_approval"
  | "loaned"
  | "return_requested"
  | "returned"
  | "rejected"
  | "overdue";

export interface Reservation {
  reservation_id: number;
  user_id?: number;
  book_id: number;
  school_id?: number;
  status: ReservationStatus;
  reserved_at?: string;
  due_date?: string | null;
  returned_at?: string | null;
  reservation_date?: string;
  // Join'lerden gelen alanlar
  book_name?: string;
  isbn?: string;
  student_name?: string;
  student_number?: string;
  class_name?: string;
  class_code?: string;
  school_level?: string;
}

export interface IsbnLookupResult {
  title: string;
  authors: string[];
  publisher: string;
  categories: string[];
  isbn: string;
  isbn10: string;
  isbn13: string;
  pageCount: number;
  source: "local_db" | "google_books";
  physicalDescription: string;
  volumeCount: number;
  hasVolumes: boolean;
  volumes: Array<{ volumeNo: number; title: string }>;
}
