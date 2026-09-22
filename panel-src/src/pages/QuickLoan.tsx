import { FormEvent, useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { Zap, ScanLine } from "lucide-react";
import toast from "react-hot-toast";
import { Button } from "@/components/Button";
import { Input } from "@/components/Input";
import { Select } from "@/components/Select";
import { PageHeader } from "@/components/PageHeader";
import { useAuthStore } from "@/store/authStore";
import { loanBookByStudent } from "@/api/reservations";
import { getErrorMessage } from "@/api/client";
import { normalizeIsbn } from "@/lib/utils";

export function QuickLoanPage() {
  const school = useAuthStore((s) => s.school);
  const schoolCode = school?.school_code || "";

  const [studentNumber, setStudentNumber] = useState("");
  const [isbn, setIsbn] = useState("");
  const [schoolLevel, setSchoolLevel] = useState("");
  const [dueDate, setDueDate] = useState("");

  const mutation = useMutation({
    mutationFn: () =>
      loanBookByStudent({
        schoolCode,
        student_number: studentNumber.trim(),
        isbn: normalizeIsbn(isbn),
        school_level: schoolLevel || undefined,
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

          <div className="relative">
            <Input
              label="Kitap ISBN"
              placeholder="ISBN gir veya barkod tara..."
              value={isbn}
              onChange={(e) => setIsbn(e.target.value)}
            />
            <ScanLine
              size={16}
              className="absolute right-3 top-[34px] text-muted-foreground pointer-events-none"
            />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <Select
              label="Okul Seviyesi (opsiyonel)"
              value={schoolLevel}
              onChange={(e) => setSchoolLevel(e.target.value)}
            >
              <option value="">Belirtilmedi</option>
              <option value="ilkokul">İlkokul</option>
              <option value="ortaokul">Ortaokul</option>
              <option value="lise">Lise</option>
              <option value="hazırlık">Hazırlık</option>
            </Select>
            <Input
              label="Son İade Tarihi"
              type="date"
              value={dueDate || defaultDueDate}
              onChange={(e) => setDueDate(e.target.value)}
            />
          </div>

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
            edilmiştir. Öğrenci numarasını ve kitabın ISBN'ini girdiğinde
            arkada öğrenci doğrulanır, kitap envanterden düşülür ve ödünç kaydı
            açılır.
          </p>
        </div>
      </div>
    </div>
  );
}
