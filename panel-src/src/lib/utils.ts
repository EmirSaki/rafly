import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatDate(dateString?: string | null): string {
  if (!dateString) return "-";
  try {
    const date = new Date(dateString);
    return date.toLocaleDateString("tr-TR", {
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
    });
  } catch {
    return "-";
  }
}

export function formatDateTime(dateString?: string | null): string {
  if (!dateString) return "-";
  try {
    const date = new Date(dateString);
    return date.toLocaleString("tr-TR", {
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  } catch {
    return "-";
  }
}

export function normalizeIsbn(value: string): string {
  return String(value || "").replace(/[^0-9Xx]/g, "").toUpperCase().trim();
}

export async function exportToCsv(
  filename: string,
  headers: string[],
  rows: string[][]
) {
  const BOM = "﻿";
  const csvContent =
    BOM +
    [headers, ...rows]
      .map((row) =>
        row
          .map((cell) => {
            const escaped = String(cell ?? "").replace(/"/g, '""');
            return `"${escaped}"`;
          })
          .join(";")
      )
      .join("\r\n");

  const blob = new Blob([csvContent], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `${filename}.csv`;
  link.click();
  URL.revokeObjectURL(url);
  return true;
}
