import { FormEvent, Suspense, lazy, useEffect, useMemo, useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { Zap, ScanLine, UserCheck, AlertTriangle } from "lucide-react";
import toast from "react-hot-toast";
import { Button } from "@/components/Button";
import { Input } from "@/components/Input";
import { PageHeader } from "@/components/PageHeader";
import { useAuthStore } from "@/store/authStore";
import { loanBookByStudent } from "@/api/reservations";
import { getStudents } from "@/api/students";
import type { Student } from "@/types";
import { getErrorMessage } from "@/api/client";
import { normalizeIsbn } from "@/lib/utils";

// ZXing kutuphanesi buyuk; sadece tarama acilinca yuklensin diye tembel yukleniyor.
const BarcodeScanner = lazy(() =>
  import("@/components/BarcodeScanner").then((m) => ({ default: m.BarcodeScanner }))
);

const LEVEL_LABELS: Record<string, string> = {
  ilkokul: "İlkokul",
  ortaokul: "Ortaokul",
  lise: "Lise",
  "hazırlık": "Hazırlık",
  "diğer": "Diğer",
};

function levelLabel(level?: string | null) {
  const key = String(level || "").trim().toLowerCase();
  return LEVEL_LABELS[key] || (key ? key : "Seviye yok");
}

// Öğrencinin kimliği numara + seviye (+ sınıf) üçlüsüdür; yalnızca numara yetmez.
function studentKey(s: Student) {
  return `${String(s.school_level || "").toLowerCase()}|${s.class_name || ""}`;
}

export function QuickLoanPage() {
  const school = useAuthStore((s) => s.school);
  const schoolCode = school?.school_code || "";

  const [studentNumber, setStudentNumber] = useState("");
  const [isbn, setIsbn] = useState("");
  const [selectedKey, setSelectedKey] = useState("");
  const [dueDate, setDueDate] = useState("");
  const [scanOpen, setScanOpen] = useState(false);

  // Yalnızca aktif öğrenciler gelir (mezun/eski öğrenciler listede yoktur).
  const { data: students, isLoading: studentsLoading } = useQuery({
    queryKey: ["students", schoolCode, ""],
    queryFn: () => getStudents({ schoolCode }),
    enabled: !!schoolCode,
  });

  const matches = useMemo(() => {
    const number = studentNumber.trim();
    if (!number || !students) return [];
    return students.filter((s) => String(s.student_number || "").trim() === number);
  }, [students, studentNumber]);

  const selectedStudent =
    matches.length === 1
      ? matches[0]
      : matches.find((s) => studentKey(s) === selectedKey) || null;

  useEffect(() => {
    setSelectedKey("");
  }, [studentNumber]);

  const mutation = useMutation({
    mutationFn: () =>
      loanBookByStudent({
        schoolCode,
        student_number: studentNumber.trim(),
        isbn: normalizeIsbn(isbn),
        school_level: selectedStudent?.school_level || undefined,
        class_name: selectedStudent?.class_name || undefined,
        due_date: dueDate || defaultDueDate,
      }),
    onSuccess: () => {
      toast.success("Kitap başarıyla ödünç verildi");
      setStudentNumber("");
      setIsbn("");
      setDueDate("");
    },
    onError: (err) => toast.error(getErrorMessage(err)),
  });

  function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!studentNumber.trim() || !isbn.trim()) {
      toast.error("Öğrenci numarası ve ISBN zorunlu");
      return;
    }
    if (!selectedStudent) {
      toast.error(
        matches.length > 1
          ? "Bu numarada birden fazla öğrenci var. Hangisi olduğunu seç."
          : "Bu numarada aktif öğrenci bulunamadı"
      );
      return;
    }
    mutation.mutate();
  }

  // Varsayılan iade tarihi: 15 gün sonra
  const defaultDueDate = (() => {
    const d = new Date();
    d.setDate(d.getDate() + 15);
    return d.toISOString().slice(0, 10);
  })();

  return (
    <div>
      <PageHeader
        title="Hızlı Ödünç Ver"
        description="Öğrenci numarası ve ISBN ile tek tıkla ödünç verme"
      />

      <div className="card p-6 max-w-2xl">
        <div className="flex items-center gap-3 mb-6">
          <div className="p-2.5 bg-amber-50 text-amber-600 rounded-lg">
            <Zap size={20} />
          </div>
          <div>
            <h2 className="font-semibold">Yeni Ödünç İşlemi</h2>
            <p className="text-sm text-muted-foreground">
              Barkod okuyucu varsa direkt ISBN alanına okutabilirsin
            </p>
          </div>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <Input
            label="Öğrenci Numarası"
            placeholder="Örn: 12345"
            value={studentNumber}
            onChange={(e) => setStudentNumber(e.target.value)}
            autoFocus
          />

          {studentNumber.trim() && !studentsLoading && matches.length === 0 && (
            <div className="flex items-center gap-2 rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
              <AlertTriangle size={16} />
              Bu numarada aktif öğrenci yok (mezun/eski öğrencilere kitap verilmez).
            </div>
          )}

          {matches.length === 1 && (
            <div className="flex items-center gap-2 rounded-md border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-emerald-800">
              <UserCheck size={16} />
              <span>
                <strong>{matches[0].full_name}</strong> · {matches[0].class_name || "-"} ·{" "}
                {levelLabel(matches[0].school_level)}
              </span>
            </div>
          )}

          {matches.length > 1 && (
            <div className="rounded-md border border-amber-200 bg-amber-50 p-3">
              <p className="mb-2 flex items-center gap-2 text-sm font-medium text-amber-900">
                <AlertTriangle size={16} />
                Bu numarada {matches.length} öğrenci var. Kitabı alacak olanı seç:
              </p>
              <div className="space-y-1.5">
                {matches.map((s) => {
                  const key = studentKey(s);
                  return (
                    <label
                      key={key}
                      className={`flex cursor-pointer items-center gap-2 rounded-md border px-3 py-2 text-sm ${
                        selectedKey === key
                          ? "border-primary bg-white"
                          : "border-transparent bg-white/60 hover:bg-white"
                      }`}
                    >
                      <input
                        type="radio"
                        name="loan-student"
                        checked={selectedKey === key}
                        onChange={() => setSelectedKey(key)}
                      />
                      <span>
                        <strong>{levelLabel(s.school_level)}</strong> · {s.class_name || "-"} ·{" "}
                        {s.full_name}
                      </span>
                    </label>
                  );
                })}
              </div>
            </div>
          )}

          <div className="relative">
            <Input
              label="Kitap ISBN"
              placeholder="ISBN gir veya barkod tara..."
              value={isbn}
              onChange={(e) => setIsbn(e.target.value)}
              className="pr-12"
            />
            <button
              type="button"
              onClick={() => setScanOpen(true)}
              title="Kamera ile barkod tara"
              aria-label="Kamera ile barkod tara"
              className="absolute right-1.5 top-[26px] flex items-center justify-center rounded-md p-2 text-primary hover:bg-primary/10 transition-colors"
            >
              <ScanLine size={20} />
            </button>
          </div>

          <Input
            label="Son İade Tarihi"
            type="date"
            value={dueDate || defaultDueDate}
            onChange={(e) => setDueDate(e.target.value)}
          />

          <div className="flex justify-end pt-2">
            <Button
              type="submit"
              size="lg"
              loading={mutation.isPending}
              className="min-w-[160px]"
            >
              <Zap size={16} />
              Ödünç Ver
            </Button>
          </div>
        </form>

        <div className="mt-6 p-4 bg-blue-50 border border-blue-100 rounded-md">
          <p className="text-xs text-blue-900">
            <strong>İpucu:</strong> Bu ekran kütüphane kasası için optimize
            edilmiştir. Numarayı yazınca öğrencinin adı, sınıfı ve okul
            seviyesi görünür; aynı numara hem ortaokulda hem lisede varsa
            hangisi olduğunu seçmen istenir. Kitap yalnızca seçilen öğrenciye
            yazılır.
          </p>
        </div>
      </div>

      {scanOpen && (
        <Suspense fallback={null}>
          <BarcodeScanner
            open
            onClose={() => setScanOpen(false)}
            onDetected={(code) => {
              setIsbn(code);
              setScanOpen(false);
            }}
            title="Kitap barkodunu tara"
          />
        </Suspense>
      )}
    </div>
  );
}
