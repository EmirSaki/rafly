import { FormEvent, Suspense, lazy, useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { BookOpen, ScanLine, Info } from "lucide-react";
import toast from "react-hot-toast";
import { Button } from "@/components/Button";
import { Input } from "@/components/Input";
import { Select } from "@/components/Select";
import { PageHeader } from "@/components/PageHeader";
import { useAuthStore } from "@/store/authStore";
import { loanBookByStudent } from "@/api/reservations";
import { getErrorMessage } from "@/api/client";
import { normalizeIsbn } from "@/lib/utils";

// ZXing kutuphanesi buyuk; sadece tarama acilinca yuklensin diye tembel yukleniyor.
const BarcodeScanner = lazy(() =>
  import("@/components/BarcodeScanner").then((m) => ({ default: m.BarcodeScanner }))
);

export function QuickLoanPage() {
  const school = useAuthStore((s) => s.school);
  const schoolCode = school?.school_code || "";

  const [studentNumber, setStudentNumber] = useState("");
  const [isbn, setIsbn] = useState("");
  const [schoolLevel, setSchoolLevel] = useState("");
  const [dueDate, setDueDate] = useState("");
  const [scanOpen, setScanOpen] = useState(false);

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
        title="Hızlı Ödünç"
        description="Öğrenciye kitap ödünç vermek için gerekli bilgileri girin."
      />

      <form onSubmit={handleSubmit} className="quick-loan-form card">
        <div className="quick-loan-top-grid">
          <section className="quick-loan-step step-blue">
            <div className="quick-loan-step-heading"><span>1</span><div><h2>Öğrenci Numarası</h2><p>Ödünç vereceğiniz öğrencinin numarasını girin.</p></div></div>
            <Input label="Öğrenci numarası" placeholder="Öğrenci numarası" value={studentNumber} onChange={(e) => setStudentNumber(e.target.value)} autoFocus />
          </section>
          <section className="quick-loan-step step-amber">
            <div className="quick-loan-step-heading"><span>2</span><div><h2>Kitap ISBN</h2><p>ISBN numarasını girin veya barkodu okutun.</p></div></div>
            <div className="quick-isbn"><Input label="ISBN numarası" placeholder="ISBN numarası" value={isbn} onChange={(e) => setIsbn(e.target.value)} /><button type="button" onClick={() => setScanOpen(true)}><ScanLine size={18} /> Barkod Okut</button></div>
          </section>
        </div>
        <section className="quick-loan-step step-neutral">
          <div className="quick-loan-step-heading"><span>3</span><div><h2>Okul Seviyesi ve Son İade Tarihi</h2></div></div>
          <div className="quick-loan-fields">
            <Select label="Okul Seviyesi (opsiyonel)" value={schoolLevel} onChange={(e) => setSchoolLevel(e.target.value)}><option value="">Seçiniz</option><option value="ilkokul">İlkokul</option><option value="ortaokul">Ortaokul</option><option value="lise">Lise</option><option value="hazırlık">Hazırlık</option></Select>
            <Input label="Son İade Tarihi" type="date" value={dueDate || defaultDueDate} onChange={(e) => setDueDate(e.target.value)} />
          </div>
        </section>
        <div className="quick-loan-footer"><p><Info size={18} /> Öğrenci numarası ve ISBN girerek ödünç işlemini tamamlayın.</p><Button type="submit" size="lg" loading={mutation.isPending}><BookOpen size={18} /> Ödünç Ver</Button></div>
      </form>

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
