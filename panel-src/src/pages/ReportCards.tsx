import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import toast from "react-hot-toast";
import { Award, Download, FolderTree, FileText, Users as UsersIcon } from "lucide-react";
import { PageHeader } from "@/components/PageHeader";
import { Select } from "@/components/Select";
import { Input } from "@/components/Input";
import { Button } from "@/components/Button";
import { Badge } from "@/components/Badge";
import { useAuthStore } from "@/store/authStore";
import { getStudents } from "@/api/students";
import {
  downloadReportCards,
  getReportCardSummary,
  readBlobErrorMessage,
  saveBlob,
} from "@/api/reportCards";
import { getErrorMessage } from "@/api/client";

const SCHOOL_LEVELS = [
  { value: "", label: "Tüm seviyeler" },
  { value: "ilkokul", label: "İlkokul" },
  { value: "ortaokul", label: "Ortaokul" },
  { value: "lise", label: "Lise" },
  { value: "hazırlık", label: "Hazırlık" },
  { value: "diğer", label: "Diğer" },
];

/** "11C", "6/A" → "6" ; "ÖĞRETMEN" → null */
function extractGrade(className?: string | null): string | null {
  if (!className) return null;
  const match = String(className).trim().match(/^(\d{1,2})/);
  return match ? match[1] : null;
}

function toInputDate(date: Date): string {
  const two = (n: number) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())}`;
}

function formatTr(value: string): string {
  const [y, m, d] = value.split("-");
  return `${d}.${m}.${y}`;
}

/**
 * Eğitim yılı 1 Eylül'de başlar. Temmuz/Ağustos'ta bulunuyorsak
 * biten yılı gösteririz, aksi hâlde içinde bulunduğumuz yılı.
 */
function currentSchoolYear(): { start: string; end: string } {
  const now = new Date();
  const startYear = now.getMonth() >= 8 ? now.getFullYear() : now.getFullYear() - 1;
  return {
    start: `${startYear}-09-01`,
    end: `${startYear + 1}-06-30`,
  };
}

export function ReportCardsPage() {
  const school = useAuthStore((s) => s.school);
  const schoolCode = school?.school_code || "";

  const [level, setLevel] = useState("");
  const [grade, setGrade] = useState("");
  const [className, setClassName] = useState("");
  const [format, setFormat] = useState<"zip" | "pdf">("zip");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [busy, setBusy] = useState(false);

  const { data: students, isLoading } = useQuery({
    queryKey: ["students", schoolCode],
    queryFn: () => getStudents({ schoolCode }),
    enabled: !!schoolCode,
  });

  const dateError =
    startDate && endDate && startDate > endDate
      ? "Başlangıç tarihi bitişten sonra olamaz"
      : "";

  function applyPreset(preset: "all" | "year" | "month" | "term") {
    const now = new Date();
    if (preset === "all") {
      setStartDate("");
      setEndDate("");
      return;
    }
    if (preset === "year") {
      const { start, end } = currentSchoolYear();
      setStartDate(start);
      setEndDate(end);
      return;
    }
    if (preset === "month") {
      setStartDate(toInputDate(new Date(now.getFullYear(), now.getMonth(), 1)));
      setEndDate(toInputDate(now));
      return;
    }
    // Dönem: eğitim yılının ikinci yarısı (Şubat - Haziran) ya da ilk yarısı
    const { start, end } = currentSchoolYear();
    const startYear = Number(start.slice(0, 4));
    const inSecondTerm = now.getMonth() >= 1 && now.getMonth() <= 7;
    setStartDate(inSecondTerm ? `${startYear + 1}-02-01` : start);
    setEndDate(inSecondTerm ? end : `${startYear + 1}-01-31`);
  }

  // Kaç öğrencinin karnesi basılacak — istek atmadan önce göster
  const { selected, availableGrades, availableClasses } = useMemo(() => {
    const list = students || [];
    const grades = new Set<string>();
    const classes = new Set<string>();

    list.forEach((s) => {
      if (level && String(s.school_level ?? "").toLowerCase() !== level) return;
      const g = extractGrade(s.class_name);
      if (g) grades.add(g);
      if (s.class_name) classes.add(String(s.class_name));
    });

    const matched = list.filter((s) => {
      if (level && String(s.school_level ?? "").toLowerCase() !== level) return false;
      if (grade && extractGrade(s.class_name) !== grade) return false;
      if (className && String(s.class_name ?? "") !== className) return false;
      return true;
    });

    return {
      selected: matched,
      availableGrades: Array.from(grades).sort((a, b) => Number(a) - Number(b)),
      availableClasses: Array.from(classes).sort((a, b) => a.localeCompare(b, "tr")),
    };
  }, [students, level, grade, className]);

  const classCount = useMemo(
    () => new Set(selected.map((s) => String(s.class_name ?? "-"))).size,
    [selected]
  );

  // Karnelerdekiyle aynı hesaptan gelen özet
  const { data: summary, isFetching: summaryLoading } = useQuery({
    queryKey: [
      "report-card-summary",
      schoolCode,
      level,
      grade,
      className,
      startDate,
      endDate,
    ],
    queryFn: () =>
      getReportCardSummary({
        schoolCode,
        school_level: level || undefined,
        grade: grade || undefined,
        class_name: className || undefined,
        startDate: startDate || undefined,
        endDate: endDate || undefined,
      }),
    enabled: !!schoolCode && !dateError && selected.length > 0,
    retry: false,
  });

  async function handleDownload() {
    if (!schoolCode) return;
    if (selected.length === 0) {
      toast.error("Bu filtreye uyan öğrenci yok");
      return;
    }
    if (dateError) {
      toast.error(dateError);
      return;
    }

    setBusy(true);
    const toastId = toast.loading(
      `${selected.length} karne hazırlanıyor, bu biraz sürebilir...`
    );

    try {
      const { blob, fileName } = await downloadReportCards({
        schoolCode,
        school_level: level || undefined,
        grade: grade || undefined,
        class_name: className || undefined,
        startDate: startDate || undefined,
        endDate: endDate || undefined,
        format,
      });

      saveBlob(blob, fileName);
      toast.success(`${selected.length} karne indirildi`, { id: toastId });
    } catch (error) {
      const message =
        (await readBlobErrorMessage(error)) || getErrorMessage(error);
      toast.error(message, { id: toastId });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div>
      <PageHeader
        title="Karne Oluştur"
        description="Öğrencilerin okuma karnelerini PDF olarak indir"
      />

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        {/* Sol: filtreler */}
        <div className="lg:col-span-2 space-y-4">
          <div className="card p-5">
            <h2 className="font-semibold mb-1">Kimlerin karnesi basılsın?</h2>
            <p className="text-sm text-muted-foreground mb-4">
              Boş bırakılan filtreler tüm kayıtları kapsar.
            </p>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <Select
                label="Okul Seviyesi"
                value={level}
                onChange={(e) => {
                  setLevel(e.target.value);
                  setGrade("");
                  setClassName("");
                }}
              >
                {SCHOOL_LEVELS.map((l) => (
                  <option key={l.value} value={l.value}>
                    {l.label}
                  </option>
                ))}
              </Select>

              <Select
                label="Sınıf Düzeyi"
                value={grade}
                onChange={(e) => {
                  setGrade(e.target.value);
                  setClassName("");
                }}
              >
                <option value="">Tüm düzeyler</option>
                {availableGrades.map((g) => (
                  <option key={g} value={g}>
                    {g}. Sınıf
                  </option>
                ))}
              </Select>

              <Select
                label="Şube"
                value={className}
                onChange={(e) => setClassName(e.target.value)}
              >
                <option value="">Tüm şubeler</option>
                {availableClasses
                  .filter((c) => (grade ? extractGrade(c) === grade : true))
                  .map((c) => (
                    <option key={c} value={c}>
                      {c}
                    </option>
                  ))}
              </Select>
            </div>
          </div>

          <div className="card p-5">
            <h2 className="font-semibold mb-1">Hangi tarih aralığı?</h2>
            <p className="text-sm text-muted-foreground mb-4">
              Yalnızca bu aralıkta <b>iade edilmiş</b> kitaplar sayılır ve
              sıralamalar da bu aralığa göre hesaplanır. Boş bırakırsan tüm
              zamanlar.
            </p>

            <div className="flex flex-wrap gap-2 mb-4">
              {[
                { key: "all" as const, label: "Tüm zamanlar" },
                { key: "year" as const, label: "Bu eğitim yılı" },
                { key: "term" as const, label: "Bu dönem" },
                { key: "month" as const, label: "Bu ay" },
              ].map((p) => (
                <button
                  key={p.key}
                  type="button"
                  onClick={() => applyPreset(p.key)}
                  className="px-3 py-1.5 text-xs rounded-md border hover:bg-muted/40 transition-colors"
                >
                  {p.label}
                </button>
              ))}
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <Input
                type="date"
                label="Başlangıç"
                value={startDate}
                max={endDate || undefined}
                onChange={(e) => setStartDate(e.target.value)}
              />
              <Input
                type="date"
                label="Bitiş"
                value={endDate}
                min={startDate || undefined}
                onChange={(e) => setEndDate(e.target.value)}
                error={dateError || undefined}
              />
            </div>

            <div className="mt-3 flex items-center gap-2 flex-wrap">
              <Badge variant="info">
                {startDate || endDate
                  ? `${startDate ? formatTr(startDate) : "başlangıç"} – ${
                      endDate ? formatTr(endDate) : "bugün"
                    }`
                  : "Tüm zamanlar"}
              </Badge>
              {!dateError && summary && (
                <span className="text-xs text-muted-foreground">
                  Bu aralıkta {summary.totalBooks} kitap ·{" "}
                  {summary.readingStudentCount} öğrenci okumuş
                </span>
              )}
              {summaryLoading && (
                <span className="text-xs text-muted-foreground">
                  hesaplanıyor...
                </span>
              )}
              {(startDate || endDate) && (
                <button
                  type="button"
                  onClick={() => applyPreset("all")}
                  className="text-xs text-muted-foreground hover:text-foreground underline"
                >
                  temizle
                </button>
              )}
            </div>
          </div>

          <div className="card p-5">
            <h2 className="font-semibold mb-3">Çıktı biçimi</h2>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <button
                type="button"
                onClick={() => setFormat("zip")}
                className={
                  "text-left p-4 rounded-lg border-2 transition-colors " +
                  (format === "zip"
                    ? "border-primary bg-primary/5"
                    : "border-border hover:bg-muted/30")
                }
              >
                <div className="flex items-center gap-2 mb-1">
                  <FolderTree size={18} className="text-primary" />
                  <span className="font-medium">Sınıf klasörlü ZIP</span>
                </div>
                <p className="text-xs text-muted-foreground">
                  Her öğrenci için ayrı PDF, sınıf klasörlerine ayrılmış.
                  Dağıtmak için uygun.
                </p>
              </button>

              <button
                type="button"
                onClick={() => setFormat("pdf")}
                className={
                  "text-left p-4 rounded-lg border-2 transition-colors " +
                  (format === "pdf"
                    ? "border-primary bg-primary/5"
                    : "border-border hover:bg-muted/30")
                }
              >
                <div className="flex items-center gap-2 mb-1">
                  <FileText size={18} className="text-primary" />
                  <span className="font-medium">Tek birleşik PDF</span>
                </div>
                <p className="text-xs text-muted-foreground">
                  Tüm karneler tek dosyada, her öğrenci bir sayfa. Toplu
                  yazdırmak için uygun.
                </p>
              </button>
            </div>
          </div>

          <div className="card p-5">
            <h2 className="font-semibold mb-2">Karnede ne yazıyor?</h2>
            <ul className="text-sm text-muted-foreground space-y-1.5 list-disc pl-5">
              <li>Ad soyad, okul numarası, sınıf ve seviye</li>
              <li>Seçilen tarih aralığı (karnenin başlığında yazar)</li>
              <li>Okuduğu kitap sayısı ve kitapların listesi (iade tarihleriyle)</li>
              <li>
                Dört ayrı sıralama: okul geneli, kendi seviyesi, kendi sınıf
                düzeyi (ör. tüm 6. sınıflar) ve kendi şubesi
              </li>
            </ul>
            <p className="text-xs text-muted-foreground mt-3">
              Okunan kitap = iade edilmiş kitap. Sıralamalar her zaman okulun
              tamamı üzerinden hesaplanır; yukarıdaki filtreler yalnızca kimin
              karnesinin basılacağını belirler.
            </p>
          </div>
        </div>

        {/* Sağ: özet + indir */}
        <div className="space-y-4">
          <div className="card p-5">
            <div className="flex items-center gap-2 mb-4">
              <Award size={18} className="text-primary" />
              <h2 className="font-semibold">Özet</h2>
            </div>

            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground">Öğrenci</span>
                <span className="text-2xl font-bold">
                  {isLoading ? "…" : selected.length}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground">Sınıf</span>
                <span className="font-medium">{isLoading ? "…" : classCount}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground">
                  Okunan kitap
                </span>
                <span className="font-medium">
                  {summary ? summary.totalBooks : "…"}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground">Biçim</span>
                <Badge variant="info">
                  {format === "zip" ? "ZIP" : "Tek PDF"}
                </Badge>
              </div>
              <div className="flex items-center justify-between gap-2">
                <span className="text-sm text-muted-foreground shrink-0">
                  Dönem
                </span>
                <span className="text-xs font-medium text-right">
                  {startDate || endDate
                    ? `${startDate ? formatTr(startDate) : "başlangıç"} – ${
                        endDate ? formatTr(endDate) : "bugün"
                      }`
                    : "Tüm zamanlar"}
                </span>
              </div>
            </div>

            <div className="mt-5">
              <Button
                onClick={handleDownload}
                disabled={busy || isLoading || selected.length === 0 || !!dateError}
                className="w-full"
              >
                <Download size={16} />
                {busy ? "Hazırlanıyor..." : "Karneleri İndir"}
              </Button>
            </div>

            {selected.length > 150 && (
              <p className="text-xs text-muted-foreground mt-3">
                Çok sayıda karne üretiliyor; indirme başlayana kadar sayfayı
                kapatma.
              </p>
            )}
          </div>

          <div className="card p-5">
            <div className="flex items-center gap-2 mb-2">
              <UsersIcon size={16} className="text-muted-foreground" />
              <h3 className="text-sm font-medium">Seçilen sınıflar</h3>
            </div>
            {isLoading ? (
              <p className="text-xs text-muted-foreground">Yükleniyor...</p>
            ) : selected.length === 0 ? (
              <p className="text-xs text-muted-foreground">
                Bu filtreye uyan öğrenci yok.
              </p>
            ) : (
              <div className="flex flex-wrap gap-1.5">
                {Array.from(
                  new Set(selected.map((s) => String(s.class_name ?? "-")))
                )
                  .sort((a, b) => a.localeCompare(b, "tr"))
                  .slice(0, 40)
                  .map((c) => (
                    <Badge key={c} variant="neutral">
                      {c}
                    </Badge>
                  ))}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
