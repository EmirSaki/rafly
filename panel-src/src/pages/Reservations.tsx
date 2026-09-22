import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, X, Undo2, Search, Download } from "lucide-react";
import toast from "react-hot-toast";
import { Button } from "@/components/Button";
import { Input } from "@/components/Input";
import { Select } from "@/components/Select";
import { PageHeader } from "@/components/PageHeader";
import { DataTable, Column } from "@/components/DataTable";
import { Badge } from "@/components/Badge";
import { useAuthStore } from "@/store/authStore";
import {
  getReservations,
  approveLoan,
  rejectReservation,
  returnReservation,
} from "@/api/reservations";
import { getErrorMessage } from "@/api/client";
import { formatDate, exportToCsv } from "@/lib/utils";
import type { Reservation, ReservationStatus } from "@/types";

const STATUS_OPTIONS: Array<{ value: ReservationStatus | ""; label: string }> = [
  { value: "", label: "Tüm durumlar" },
  { value: "pending_approval", label: "Onay bekliyor" },
  { value: "loaned", label: "Ödünç verildi" },
  { value: "return_requested", label: "İade talebi" },
  { value: "returned", label: "İade edildi" },
  { value: "rejected", label: "Reddedildi" },
];

const STATUS_LABEL: Record<string, string> = {
  pending_approval: "Onay bekliyor",
  loaned: "Ödünç verildi",
  return_requested: "İade talebi",
  returned: "İade edildi",
  rejected: "Reddedildi",
  overdue: "Gecikmiş",
};

function StatusBadge({ status }: { status: ReservationStatus }) {
  const map: Record<
    ReservationStatus,
    { label: string; variant: "info" | "success" | "warning" | "destructive" | "neutral" }
  > = {
    pending_approval: { label: "Onay bekliyor", variant: "warning" },
    loaned: { label: "Ödünç verildi", variant: "info" },
    return_requested: { label: "İade talebi", variant: "warning" },
    returned: { label: "İade edildi", variant: "success" },
    rejected: { label: "Reddedildi", variant: "destructive" },
    overdue: { label: "Gecikmiş", variant: "destructive" },
  };
  const entry = map[status] || { label: status, variant: "neutral" };
  return <Badge variant={entry.variant}>{entry.label}</Badge>;
}

export function ReservationsPage() {
  const school = useAuthStore((s) => s.school);
  const schoolCode = school?.school_code || "";
  const queryClient = useQueryClient();

  const [statusFilter, setStatusFilter] = useState<ReservationStatus | "">("");
  const [search, setSearch] = useState("");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");

  const { data: reservations, isLoading } = useQuery({
    queryKey: ["reservations", schoolCode, startDate, endDate],
    queryFn: () => getReservations({ schoolCode, startDate, endDate }),
    enabled: !!schoolCode,
  });

  const filtered = useMemo(() => {
    if (!reservations) return [];

    const seen = new Set<number>();
    let result = reservations.filter((r) => {
      if (seen.has(r.reservation_id)) return false;
      seen.add(r.reservation_id);
      return true;
    });

    if (statusFilter) {
      result = result.filter((r) => r.status === statusFilter);
    }

    const q = search.trim().toLocaleLowerCase("tr-TR");
    if (q) {
      result = result.filter(
        (r) =>
          (r.book_name || "").toLocaleLowerCase("tr-TR").includes(q) ||
          (r.student_name || "").toLocaleLowerCase("tr-TR").includes(q) ||
          String(r.student_number || "").includes(q) ||
          String(r.isbn || "").includes(q)
      );
    }

    return result;
  }, [reservations, statusFilter, search]);

  const invalidate = () =>
    queryClient.invalidateQueries({ queryKey: ["reservations", schoolCode] });

  const approveMutation = useMutation({
    mutationFn: (id: number) => approveLoan(id, schoolCode),
    onSuccess: () => {
      toast.success("Ödünç onaylandı");
      invalidate();
    },
    onError: (err) => toast.error(getErrorMessage(err)),
  });

  const rejectMutation = useMutation({
    mutationFn: (id: number) => rejectReservation(id, schoolCode),
    onSuccess: () => {
      toast.success("Rezervasyon reddedildi");
      invalidate();
    },
    onError: (err) => toast.error(getErrorMessage(err)),
  });

  const returnMutation = useMutation({
    mutationFn: (id: number) => returnReservation(id, schoolCode),
    onSuccess: () => {
      toast.success("İade alındı");
      invalidate();
    },
    onError: (err) => toast.error(getErrorMessage(err)),
  });

  async function handleExport() {
    if (!filtered.length) {
      toast.error("Dışa aktarılacak veri yok");
      return;
    }
    const saved = await exportToCsv(
      `rezervasyonlar-${schoolCode}`,
      ["Öğrenci", "Öğrenci No", "Sınıf", "Kitap", "ISBN", "Durum", "Rezervasyon Tarihi", "Son İade"],
      filtered.map((r) => [
        r.student_name || "-",
        r.student_number || "-",
        r.class_name || "-",
        r.book_name || "-",
        r.isbn || "-",
        STATUS_LABEL[r.status] || r.status,
        formatDate(r.reserved_at),
        formatDate(r.due_date),
      ])
    );
    if (saved) toast.success("Excel dosyası kaydedildi");
  }

  const columns: Column<Reservation>[] = [
    {
      key: "student",
      header: "Öğrenci",
      sortable: true,
      sortValue: (r) => r.student_name || "",
      render: (r) => (
        <div>
          <p className="font-medium">{r.student_name || "-"}</p>
          <p className="text-xs text-muted-foreground">
            {r.student_number ? `#${r.student_number}` : "-"}
            {r.class_name ? ` · ${r.class_name}` : ""}
          </p>
        </div>
      ),
    },
    {
      key: "book",
      header: "Kitap",
      sortable: true,
      sortValue: (r) => r.book_name || "",
      render: (r) => (
        <div>
          <p className="font-medium">{r.book_name || "-"}</p>
          <p className="text-xs font-mono text-muted-foreground">{r.isbn}</p>
        </div>
      ),
    },
    {
      key: "status",
      header: "Durum",
      width: "140px",
      sortable: true,
      sortValue: (r) => r.status,
      render: (r) => <StatusBadge status={r.status} />,
    },
    {
      key: "reserved_at",
      header: "Rezervasyon Tarihi",
      width: "130px",
      sortable: true,
      sortValue: (r) => r.reserved_at || "",
      render: (r) => (
        <span className="text-xs">{formatDate(r.reserved_at)}</span>
      ),
    },
    {
      key: "due_date",
      header: "Son İade",
      width: "110px",
      sortable: true,
      sortValue: (r) => r.due_date || "",
      render: (r) => (
        <span className="text-xs">{formatDate(r.due_date)}</span>
      ),
    },
    {
      key: "actions",
      header: "İşlem",
      align: "right",
      width: "200px",
      render: (r) => {
        if (r.status === "pending_approval") {
          return (
            <div className="flex justify-end gap-1">
              <Button
                size="sm"
                onClick={() => approveMutation.mutate(r.reservation_id)}
              >
                <Check size={14} />
                Onayla
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={() => rejectMutation.mutate(r.reservation_id)}
              >
                <X size={14} />
              </Button>
            </div>
          );
        }
        if (r.status === "loaned" || r.status === "return_requested") {
          return (
            <Button
              size="sm"
              variant="outline"
              onClick={() => returnMutation.mutate(r.reservation_id)}
            >
              <Undo2 size={14} />
              İade Al
            </Button>
          );
        }
        return <span className="text-xs text-muted-foreground">-</span>;
      },
    },
  ];

  return (
    <div>
      <PageHeader
        title="Rezervasyonlar"
        description={`Toplam ${filtered.length} kayıt`}
        actions={
          <Button variant="outline" onClick={handleExport}>
            <Download size={16} />
            Excel
          </Button>
        }
      />

      <div className="card p-4 mb-4 flex flex-col sm:flex-row gap-3">
        <div className="relative flex-1">
          <Search
            size={16}
            className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground pointer-events-none"
          />
          <Input
            placeholder="Öğrenci, kitap veya ISBN ara..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-9"
          />
        </div>
        <div className="w-full sm:w-56">
          <Select
            value={statusFilter}
            onChange={(e) =>
              setStatusFilter(e.target.value as ReservationStatus | "")
            }
          >
            {STATUS_OPTIONS.map((s) => (
              <option key={s.value} value={s.value}>
                {s.label}
              </option>
            ))}
          </Select>
        </div>
        <div className="w-full sm:w-40">
          <Input
            type="date"
            value={startDate}
            max={endDate || undefined}
            onChange={(e) => setStartDate(e.target.value)}
            aria-label="Başlangıç tarihi"
          />
        </div>
        <div className="w-full sm:w-40">
          <Input
            type="date"
            value={endDate}
            min={startDate || undefined}
            onChange={(e) => setEndDate(e.target.value)}
            aria-label="Bitiş tarihi"
          />
        </div>
        {(startDate || endDate) && (
          <Button
            variant="outline"
            onClick={() => {
              setStartDate("");
              setEndDate("");
            }}
          >
            Tarihi Temizle
          </Button>
        )}
      </div>

      <DataTable
        columns={columns}
        data={filtered}
        loading={isLoading}
        emptyText="Rezervasyon bulunmuyor"
        getRowKey={(r) => r.reservation_id}
      />
    </div>
  );
}
