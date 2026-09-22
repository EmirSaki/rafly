import { ReactNode, useMemo, useState } from "react";
import { cn } from "@/lib/utils";

export interface Column<T> {
  key: string;
  header: string;
  width?: string;
  render?: (row: T) => ReactNode;
  align?: "left" | "center" | "right";
  sortable?: boolean;
  sortValue?: (row: T) => string | number;
}

interface DataTableProps<T> {
  columns: Column<T>[];
  data: T[];
  loading?: boolean;
  emptyText?: string;
  onRowClick?: (row: T) => void;
  getRowKey?: (row: T, index: number) => string | number;
}

type SortDir = "asc" | "desc";

export function DataTable<T extends Record<string, any>>({
  columns,
  data,
  loading,
  emptyText = "Kayıt bulunamadı",
  onRowClick,
  getRowKey,
}: DataTableProps<T>) {
  const [sortKey, setSortKey] = useState<string | null>(null);
  const [sortDir, setSortDir] = useState<SortDir>("asc");

  function handleSort(col: Column<T>) {
    if (!col.sortable) return;
    if (sortKey === col.key) {
      setSortDir((d) => (d === "asc" ? "desc" : "asc"));
    } else {
      setSortKey(col.key);
      setSortDir("asc");
    }
  }

  const sorted = useMemo(() => {
    if (!sortKey) return data;
    const col = columns.find((c) => c.key === sortKey);
    if (!col) return data;

    return [...data].sort((a, b) => {
      const av = col.sortValue ? col.sortValue(a) : (a[col.key] ?? "");
      const bv = col.sortValue ? col.sortValue(b) : (b[col.key] ?? "");

      let cmp: number;
      if (typeof av === "number" && typeof bv === "number") {
        cmp = av - bv;
      } else {
        cmp = String(av)
          .toLocaleLowerCase("tr-TR")
          .localeCompare(String(bv).toLocaleLowerCase("tr-TR"), "tr-TR");
      }
      return sortDir === "asc" ? cmp : -cmp;
    });
  }, [data, sortKey, sortDir, columns]);

  return (
    <div className="border rounded-lg overflow-hidden bg-white shadow-sm">
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead className="bg-muted/50 border-b">
            <tr>
              {columns.map((col) => (
                <th
                  key={col.key}
                  className={cn(
                    "px-4 py-3 text-xs font-semibold text-muted-foreground uppercase tracking-wide",
                    col.align === "center" && "text-center",
                    col.align === "right" && "text-right",
                    !col.align && "text-left",
                    col.sortable && "cursor-pointer select-none hover:text-foreground"
                  )}
                  style={col.width ? { width: col.width } : undefined}
                  onClick={() => handleSort(col)}
                >
                  <span className="inline-flex items-center gap-1">
                    {col.header}
                    {col.sortable && sortKey === col.key && (
                      <span className="text-[10px]">
                        {sortDir === "asc" ? "▲" : "▼"}
                      </span>
                    )}
                    {col.sortable && sortKey !== col.key && (
                      <span className="text-[10px] opacity-30">⇅</span>
                    )}
                  </span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr>
                <td
                  colSpan={columns.length}
                  className="px-4 py-12 text-center text-muted-foreground text-sm"
                >
                  Yükleniyor...
                </td>
              </tr>
            ) : sorted.length === 0 ? (
              <tr>
                <td
                  colSpan={columns.length}
                  className="px-4 py-12 text-center text-muted-foreground text-sm"
                >
                  {emptyText}
                </td>
              </tr>
            ) : (
              sorted.map((row, idx) => (
                <tr
                  key={getRowKey ? getRowKey(row, idx) : idx}
                  className={cn(
                    "border-b last:border-b-0 transition-colors",
                    onRowClick && "cursor-pointer hover:bg-muted/30"
                  )}
                  onClick={() => onRowClick?.(row)}
                >
                  {columns.map((col) => (
                    <td
                      key={col.key}
                      className={cn(
                        "px-4 py-3 text-sm",
                        col.align === "center" && "text-center",
                        col.align === "right" && "text-right"
                      )}
                    >
                      {col.render ? col.render(row) : (row as any)[col.key] ?? "-"}
                    </td>
                  ))}
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
