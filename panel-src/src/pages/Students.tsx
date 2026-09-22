import { FormEvent, useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, Upload, Search, Download, User, Hash, GraduationCap, Layers, Mail, Phone, KeyRound, AlertTriangle, Trash2 } from "lucide-react";
import toast from "react-hot-toast";
import { Button } from "@/components/Button";
import { Input } from "@/components/Input";
import { Select } from "@/components/Select";
import { Modal } from "@/components/Modal";
import { StudentPromotionModal } from '@/components/StudentPromotionModal';
import { PageHeader } from "@/components/PageHeader";
import { DataTable, Column } from "@/components/DataTable";
import { Badge } from "@/components/Badge";
import { useAuthStore } from "@/store/authStore";
import {
  getStudents,
  createStudent,
  importStudentsFromExcel,
  deleteStudent,
  CreateStudentPayload,
} from "@/api/students";
import { getReservations } from "@/api/reservations";
import { createAnnouncement } from "@/api/announcements";
import { getErrorMessage } from "@/api/client";
import { formatDate, exportToCsv } from "@/lib/utils";
import type { Student, Reservation } from "@/types";

const SCHOOL_LEVELS = [
  { value: "", label: "Tüm seviyeler" },
  { value: "ilkokul", label: "İlkokul" },
  { value: "ortaokul", label: "Ortaokul" },
  { value: "lise", label: "Lise" },
  { value: "hazırlık", label: "Hazırlık" },
  { value: "diğer", label: "Diğer" },
];

export function StudentsPage() {
  const school = useAuthStore((s) => s.school);
  const user = useAuthStore((s) => s.user);
  const schoolCode = school?.school_code || "";
  const queryClient = useQueryClient();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [levelFilter, setLevelFilter] = useState("");
  const [search, setSearch] = useState("");
  const [addOpen, setAddOpen] = useState(false);
  const [promotionOpen, setPromotionOpen] = useState(false);
  const [detailStudent, setDetailStudent] = useState<Student | null>(null);

  const { data: students, isLoading } = useQuery({
    queryKey: ["students", schoolCode, levelFilter],
    queryFn: () =>
      getStudents({
        schoolCode,
        school_level: levelFilter || undefined,
      }),
    enabled: !!schoolCode,
  });

  const { data: reservations = [] } = useQuery({
    queryKey: ["reservations", schoolCode],
    queryFn: () => getReservations({ schoolCode }),
    enabled: !!schoolCode,
  });

  const overdueMap = useMemo(() => {
    const map = new Map<string, Reservation>();
    const now = new Date();
    now.setHours(0, 0, 0, 0);
    for (const r of reservations) {
      if (r.status !== "loaned" || !r.due_date) continue;
      const due = new Date(r.due_date);
      due.setHours(0, 0, 0, 0);
      if (due < now && r.student_number) {
        map.set(r.student_number, r);
      }
    }
    return map;
  }, [reservations]);

  const warnMut = useMutation({
    mutationFn: (student: Student) => {
      const today = new Date().toISOString().split("T")[0];
      const endDate = new Date(Date.now() + 30 * 86400000).toISOString().split("T")[0];
      return createAnnouncement({
        schoolCode,
        title: "Kitap İade Uyarısı",
        content: `Sayın ${student.full_name}, aldığınız kitabın iade tarihi geçmiştir. Lütfen kitabınızı kütüphaneye iade edin.`,
        target_type: "section",
        target_values: [student.student_number],
        start_date: today,
        end_date: endDate,
      });
    },
    onSuccess: () => toast.success("Uyarı bildirimi gönderildi"),
    onError: (e) => toast.error(getErrorMessage(e)),
  });

  const filtered = useMemo(() => {
    if (!students) return [];
    const q = search.trim().toLocaleLowerCase("tr-TR");
    if (!q) return students;
    return students.filter(
      (s) =>
        (s.full_name || "").toLocaleLowerCase("tr-TR").includes(q) ||
        String(s.student_number || "").includes(q) ||
        (s.class_name || "").toLocaleLowerCase("tr-TR").includes(q)
    );
  }, [students, search]);

  const importMutation = useMutation({
    mutationFn: (file: File) => importStudentsFromExcel(schoolCode, file),
    onSuccess: (res) => {
      toast.success(`${res.count ?? 0} öğrenci başarıyla yüklendi`);
      queryClient.invalidateQueries({ queryKey: ["students", schoolCode] });
    },
    onError: (err) => toast.error(getErrorMessage(err)),
  });

  function handleImportClick() {
    fileInputRef.current?.click();
  }

  function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (file) {
      importMutation.mutate(file);
      e.target.value = "";
    }
  }

  async function handleExport() {
    if (!filtered.length) {
      toast.error("Dışa aktarılacak veri yok");
      return;
    }
    const saved = await exportToCsv(
      `ogrenciler-${schoolCode}`,
      ["Öğrenci No", "Ad Soyad", "Sınıf", "Seviye", "Eklenme"],
      filtered.map((s) => [
        s.student_number,
        s.full_name,
        s.class_name || "-",
        s.school_level || "-",
        formatDate(s.created_at),
      ])
    );
    if (saved) toast.success("Excel dosyası kaydedildi");
  }

  const columns: Column<Student>[] = [
    {
      key: "student_number",
      header: "Öğrenci No",
      width: "140px",
      sortable: true,
      sortValue: (s) => Number(s.student_number) || 0,
      render: (s) => (
        <span className="font-mono text-xs">{s.student_number}</span>
      ),
    },
    {
      key: "full_name",
      header: "Ad Soyad",
      sortable: true,
      sortValue: (s) => s.full_name || "",
    },
    {
      key: "class_name",
      header: "Sınıf",
      sortable: true,
      sortValue: (s) => s.class_name || "",
      render: (s) => <Badge variant="info">{s.class_name || "-"}</Badge>,
    },
    {
      key: "school_level",
      header: "Seviye",
      sortable: true,
      sortValue: (s) => s.school_level || "",
      render: (s) => (
        <span className="capitalize text-muted-foreground">
          {s.school_level || "-"}
        </span>
      ),
    },
    {
      key: "created_at",
      header: "Eklenme",
      sortable: true,
      sortValue: (s) => s.created_at || "",
      render: (s) => (
        <span className="text-xs text-muted-foreground">
          {formatDate(s.created_at)}
        </span>
      ),
    },
    {
      key: "overdue" as any,
      header: "Durum",
      align: "right",
      render: (s) => {
        const overdue = overdueMap.has(s.student_number);
        if (!overdue) return null;
        return (
          <button
            onClick={(e) => {
              e.stopPropagation();
              warnMut.mutate(s);
            }}
            disabled={warnMut.isPending}
            className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md text-xs font-medium bg-red-50 text-red-700 border border-red-200 hover:bg-red-100 transition-colors"
            title="Gecikme uyarısı gönder"
          >
            <AlertTriangle size={13} />
            Uyarı Gönder
          </button>
        );
      },
    },
  ];

  return (
    <div>
      <PageHeader
        title="Öğrenciler"
        description={`Toplam ${filtered.length} öğrenci`}
        actions={
          <>
            <input
              ref={fileInputRef}
              type="file"
              accept=".xlsx,.xls"
              className="hidden"
              onChange={handleFileChange}
            />
            <Button variant="outline" onClick={handleExport}>
              <Download size={16} />
              Excel
            </Button>
            <Button
              variant="outline"
              onClick={handleImportClick}
              loading={importMutation.isPending}
            >
              <Upload size={16} />
              Excel Yükle
            </Button>
            <Button onClick={() => setAddOpen(true)}>
              <Plus size={16} />
              Öğrenci Ekle
            </Button>
            <Button variant="outline" onClick={() => setPromotionOpen(true)}>
              <GraduationCap size={16} />
              Sınıf Atlatma
            </Button>
          </>
        }
      />

      <div className="card p-4 mb-4 flex flex-col sm:flex-row gap-3">
        <div className="relative flex-1">
          <Search
            size={16}
            className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground pointer-events-none"
          />
          <Input
            placeholder="İsim, numara veya sınıf ara..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-9"
          />
        </div>
        <div className="w-full sm:w-48">
          <Select
            value={levelFilter}
            onChange={(e) => setLevelFilter(e.target.value)}
          >
            {SCHOOL_LEVELS.map((l) => (
              <option key={l.value} value={l.value}>
                {l.label}
              </option>
            ))}
          </Select>
        </div>
      </div>

      <DataTable
        columns={columns}
        data={filtered}
        loading={isLoading}
        emptyText="Öğrenci kaydı yok. Excel yükle veya manuel ekle."
        getRowKey={(s) => `${s.student_number}-${s.class_name}`}
        onRowClick={(s) => setDetailStudent(s)}
      />

      <AddStudentModal
        open={addOpen}
        onClose={() => setAddOpen(false)}
        schoolCode={schoolCode}
        students={students}
        onAdded={() =>
          queryClient.invalidateQueries({ queryKey: ["students", schoolCode] })
        }
      />

      {promotionOpen && <StudentPromotionModal schoolCode={schoolCode} onClose={() => setPromotionOpen(false)} onDone={() => {
        queryClient.invalidateQueries({ queryKey: ['students', schoolCode] });
        queryClient.invalidateQueries({ queryKey: ['reservations', schoolCode] });
      }} />}

      <StudentDetailModal
        student={detailStudent}
        open={!!detailStudent}
        onClose={() => setDetailStudent(null)}
        schoolCode={schoolCode}
        onDeleted={() => {
          setDetailStudent(null);
          queryClient.invalidateQueries({ queryKey: ["students", schoolCode] });
        }}
      />
    </div>
  );
}

function StudentDetailModal({
  student,
  open,
  onClose,
  schoolCode,
  onDeleted,
}: {
  student: Student | null;
  open: boolean;
  onClose: () => void;
  schoolCode: string;
  onDeleted: () => void;
}) {
  const [confirmDelete, setConfirmDelete] = useState(false);

  const deleteMut = useMutation({
    mutationFn: () =>
      deleteStudent({
        schoolCode,
        student_number: student!.student_number,
        school_level: student!.school_level || "",
      }),
    onSuccess: () => {
      toast.success("Öğrenci silindi");
      setConfirmDelete(false);
      onDeleted();
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  });

  if (!student) return null;

  const nameParts = (student.full_name || "").split(" ");
  const firstName = nameParts[0] || "-";
  const lastName = nameParts.slice(1).join(" ") || "-";
  const initials = `${firstName[0] || ""}${lastName[0] || ""}`.toUpperCase();

  const fields = [
    { icon: User, label: "Ad", value: firstName },
    { icon: User, label: "Soyad", value: lastName },
    { icon: Hash, label: "Okul Numarası", value: student.student_number || "-" },
    { icon: GraduationCap, label: "Sınıf", value: student.class_name || "-" },
    { icon: Layers, label: "Seviye", value: student.school_level || "-" },
    { icon: Mail, label: "E-posta", value: student.email || "Eklenmemiş" },
    { icon: Phone, label: "Telefon", value: student.phone || "Eklenmemiş" },
    { icon: KeyRound, label: "Şifre", value: student.password || "Atanmamış" },
  ];

  return (
    <Modal open={open} onClose={onClose} title="Öğrenci Künye">
      <div className="flex flex-col items-center pb-4 border-b border-border">
        <div className="w-16 h-16 rounded-2xl bg-primary flex items-center justify-center mb-3">
          <span className="text-2xl font-bold text-white">{initials}</span>
        </div>
        <h3 className="text-lg font-semibold text-foreground">{student.full_name}</h3>
        <span className="text-sm text-muted-foreground">
          {student.class_name || "-"} · {student.school_level || "-"}
        </span>
      </div>

      <div className="mt-4 space-y-1">
        {fields.map(({ icon: Icon, label, value }) => (
          <div
            key={label}
            className="flex items-center gap-3 px-3 py-2.5 rounded-lg hover:bg-muted/50 transition-colors"
          >
            <div className="w-8 h-8 rounded-lg bg-muted flex items-center justify-center shrink-0">
              <Icon size={15} className="text-muted-foreground" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-xs text-muted-foreground">{label}</p>
              <p className="text-sm font-medium text-foreground truncate">{value}</p>
            </div>
          </div>
        ))}
      </div>

      <div className="mt-6 pt-4 border-t border-border">
        {!confirmDelete ? (
          <button
            onClick={() => setConfirmDelete(true)}
            className="w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg text-sm font-medium text-red-600 bg-red-50 border border-red-200 hover:bg-red-100 transition-colors"
          >
            <Trash2 size={15} />
            Öğrenciyi Sil
          </button>
        ) : (
          <div className="space-y-2">
            <p className="text-sm text-red-600 text-center font-medium">
              "{student.full_name}" silinecek. Bu işlem geri alınamaz.
            </p>
            <div className="flex gap-2">
              <button
                onClick={() => setConfirmDelete(false)}
                disabled={deleteMut.isPending}
                className="flex-1 px-4 py-2 rounded-lg text-sm font-medium border border-border hover:bg-muted transition-colors"
              >
                Vazgeç
              </button>
              <button
                onClick={() => deleteMut.mutate()}
                disabled={deleteMut.isPending}
                className="flex-1 px-4 py-2 rounded-lg text-sm font-medium text-white bg-red-600 hover:bg-red-700 transition-colors disabled:opacity-50"
              >
                {deleteMut.isPending ? "Siliniyor..." : "Evet, Sil"}
              </button>
            </div>
          </div>
        )}
      </div>
    </Modal>
  );
}

interface AddStudentModalProps {
  open: boolean;
  onClose: () => void;
  schoolCode: string;
  onAdded: () => void;
  students?: Student[];
}

function AddStudentModal({
  open,
  onClose,
  schoolCode,
  onAdded,
  students,
}: AddStudentModalProps) {
  const [form, setForm] = useState<CreateStudentPayload>({
    schoolCode,
    student_number: "",
    full_name: "",
    class_name: "",
    class_code: "",
    school_level: "ilkokul",
  });

  const isDiger = form.school_level === "diğer";

  const nextDigerNumber = useMemo(() => {
    if (!students) return "10000";
    let max = 9999;
    for (const s of students) {
      const num = Number(s.student_number);
      if (num >= 10000 && num > max) max = num;
    }
    return String(max + 1);
  }, [students]);

  const mutation = useMutation({
    mutationFn: createStudent,
    onSuccess: () => {
      toast.success("Öğrenci eklendi");
      onAdded();
      onClose();
      setForm({
        schoolCode,
        student_number: "",
        full_name: "",
        class_name: "",
        class_code: "",
        school_level: "ilkokul",
      });
    },
    onError: (err) => toast.error(getErrorMessage(err)),
  });

  function handleSubmit(e: FormEvent) {
    e.preventDefault();
    const payload = { ...form, schoolCode };
    if (isDiger) payload.student_number = nextDigerNumber;
    mutation.mutate(payload);
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Manuel Öğrenci Ekle"
      description="Öğrenci bilgilerini girin"
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        {isDiger ? (
          <Input
            label="Öğrenci Numarası (Otomatik)"
            value={nextDigerNumber}
            disabled
          />
        ) : (
          <Input
            label="Öğrenci Numarası"
            value={form.student_number}
            onChange={(e) =>
              setForm({ ...form, student_number: e.target.value })
            }
            required
          />
        )}
        <Input
          label="Ad Soyad"
          value={form.full_name}
          onChange={(e) => setForm({ ...form, full_name: e.target.value })}
          required
        />
        <div className="grid grid-cols-2 gap-3">
          <Input
            label="Sınıf"
            placeholder={isDiger ? "Örn: Personel" : "Örn: 5A"}
            value={form.class_name}
            onChange={(e) =>
              setForm({ ...form, class_name: e.target.value.toUpperCase() })
            }
            required
          />
          <Select
            label="Okul Seviyesi"
            value={form.school_level}
            onChange={(e) =>
              setForm({
                ...form,
                school_level: e.target.value as CreateStudentPayload["school_level"],
              })
            }
          >
            <option value="ilkokul">İlkokul</option>
            <option value="ortaokul">Ortaokul</option>
            <option value="lise">Lise</option>
            <option value="hazırlık">Hazırlık</option>
            <option value="diğer">Diğer</option>
          </Select>
        </div>
        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" variant="outline" onClick={onClose}>
            İptal
          </Button>
          <Button type="submit" loading={mutation.isPending}>
            Ekle
          </Button>
        </div>
      </form>
    </Modal>
  );
}
