import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { BookOpen, TrendingUp, Users as UsersIcon, Trophy, SlidersHorizontal, ChevronDown, Layers3 } from "lucide-react";
import { PageHeader } from "@/components/PageHeader";
import { DataTable, Column } from "@/components/DataTable";
import { Badge } from "@/components/Badge";
import { useAuthStore } from "@/store/authStore";
import { getReservations } from "@/api/reservations";
import { cn, formatDate } from "@/lib/utils";
import type { Reservation } from "@/types";

const SCHOOL_LEVELS = [
  { value: "", label: "Tüm seviyeler" },
  { value: "ilkokul", label: "İlkokul" },
  { value: "ortaokul", label: "Ortaokul" },
  { value: "lise", label: "Lise" },
  { value: "hazırlık", label: "Hazırlık" },
];

interface StudentStat {
  student_number: string;
  student_name: string;
  class_name: string;
  school_level: string;
  count: number;
  lastBookName: string;
  lastReturnedAt?: string;
}

function extractGrade(className?: string): string | null {
  if (!className) return null;
  const match = String(className).match(/^(\d+)/);
  return match ? match[1] : null;
}

const classNameCollator = new Intl.Collator("tr", { numeric: true, sensitivity: "base" });

function compareClassNames(a: string, b: string): number {
  const aGrade = extractGrade(a);
  const bGrade = extractGrade(b);
  if (aGrade && bGrade && aGrade !== bGrade) return Number(aGrade) - Number(bGrade);
  if (aGrade && !bGrade) return -1;
  if (!aGrade && bGrade) return 1;
  return classNameCollator.compare(a, b);
}

function DownwardFilter({ label, value, options, onChange }: {
  label: string;
  value: string;
  options: { value: string; label: string }[];
  onChange: (value: string) => void;
}) {
  return <details className="reading-filter-select">
    <summary><span><small>{label}</small><strong>{options.find((option) => option.value === value)?.label || options[0]?.label}</strong></span><ChevronDown size={17} /></summary>
    <div className="reading-filter-options" role="listbox" aria-label={label}>
      {options.map((option) => <button type="button" role="option" aria-selected={option.value === value} key={option.value} onClick={(event) => { onChange(option.value); event.currentTarget.closest("details")?.removeAttribute("open"); }}>{option.label}</button>)}
    </div>
  </details>;
}

function MiniStatCard({
  label,
  value,
  icon: Icon,
  color,
}: {
  label: string;
  value: number | string;
  icon: any;
  color: "blue" | "green" | "amber" | "purple";
}) {
  const colors = {
    blue: "bg-blue-50 text-blue-600",
    green: "bg-green-50 text-green-600",
    amber: "bg-amber-50 text-amber-600",
    purple: "bg-purple-50 text-purple-600",
  };
  return (
    <div className="card p-5">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-sm text-muted-foreground">{label}</p>
          <p className="text-3xl font-bold mt-2">{value}</p>
        </div>
        <div className={cn("p-3 rounded-lg", colors[color])}>
          <Icon size={24} />
        </div>
      </div>
    </div>
  );
}

export function ReadingStatsPage() {
  const school = useAuthStore((s) => s.school);
  const schoolCode = school?.school_code || "";

  const [levelFilter, setLevelFilter] = useState("");
  const [gradeFilter, setGradeFilter] = useState("");
  const [classFilter, setClassFilter] = useState("");
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [classSort, setClassSort] = useState<"class" | "books">("class");
  const [selectedStudent, setSelectedStudent] = useState<StudentStat | null>(null);

  // Backend'den status=returned olan tüm kayıtları çek
  const { data: reservations, isLoading } = useQuery({
    queryKey: ["reservations", schoolCode, "returned"],
    queryFn: () => getReservations({ schoolCode, status: "returned" }),
    enabled: !!schoolCode,
  });

  // Dinamik filtre opsiyonları (mevcut datadan üret)
  const { availableGrades, availableClasses } = useMemo(() => {
    const grades = new Set<string>();
    const classes = new Set<string>();
    (reservations || []).forEach((r) => {
      // Sadece şu an seçili seviye için sınıfları göster
      if (levelFilter && r.school_level !== levelFilter) return;
      const g = extractGrade(r.class_name);
      if (g) grades.add(g);
      if (r.class_name) classes.add(r.class_name);
    });
    return {
      availableGrades: Array.from(grades).sort(
        (a, b) => Number(a) - Number(b)
      ),
      availableClasses: Array.from(classes).sort(compareClassNames),
    };
  }, [reservations, levelFilter]);

  // Filtrelenmiş veri
  const filtered = useMemo(() => {
    if (!reservations) return [];
    return reservations.filter((r) => {
      if (levelFilter && r.school_level !== levelFilter) return false;
      if (gradeFilter) {
        const grade = extractGrade(r.class_name);
        if (grade !== gradeFilter) return false;
      }
      if (classFilter && r.class_name !== classFilter) return false;
      return true;
    });
  }, [reservations, levelFilter, gradeFilter, classFilter]);

  // Öğrenci bazında grupla
  const studentStats = useMemo(() => {
    const map = new Map<string, StudentStat>();
    filtered.forEach((r) => {
      const key = `${r.student_number}-${r.class_name}`;
      const existing = map.get(key);
      if (existing) {
        existing.count += 1;
        // En yeni iade tarihini güncelle
        const newDate = r.returned_at || r.due_date;
        if (
          newDate &&
          (!existing.lastReturnedAt || newDate > existing.lastReturnedAt)
        ) {
          existing.lastReturnedAt = newDate;
          existing.lastBookName = r.book_name || "";
        }
      } else {
        map.set(key, {
          student_number: r.student_number || "-",
          student_name: r.student_name || "-",
          class_name: r.class_name || "-",
          school_level: r.school_level || "-",
          count: 1,
          lastBookName: r.book_name || "",
          lastReturnedAt: r.returned_at || r.due_date || undefined,
        });
      }
    });
    return Array.from(map.values()).sort((a, b) => b.count - a.count);
  }, [filtered]);

  // Sınıf bazında grupla
  const classStats = useMemo(() => {
    const map = new Map<string, { class_name: string; count: number; students: Set<string> }>();
    filtered.forEach((r) => {
      const key = r.class_name || "-";
      const existing = map.get(key);
      if (existing) {
        existing.count += 1;
        if (r.student_number) existing.students.add(r.student_number);
      } else {
        map.set(key, {
          class_name: key,
          count: 1,
          students: new Set(r.student_number ? [r.student_number] : []),
        });
      }
    });
    return Array.from(map.values())
      .map((c) => ({
        class_name: c.class_name,
        count: c.count,
        studentCount: c.students.size,
      }))
      .sort((a, b) => classSort === "books"
        ? b.count - a.count || compareClassNames(a.class_name, b.class_name)
        : compareClassNames(a.class_name, b.class_name));
  }, [filtered, classSort]);

  const totalBooks = filtered.length;
  const totalStudents = studentStats.length;
  const topReader = studentStats[0];
  const avgPerStudent =
    totalStudents > 0 ? (totalBooks / totalStudents).toFixed(1) : "0";

  function clearFilters() {
    setLevelFilter("");
    setGradeFilter("");
    setClassFilter("");
  }

  const studentColumns: Column<StudentStat>[] = [
    {
      key: "rank",
      header: "#",
      width: "50px",
      align: "center",
      render: (_s) => {
        const idx = studentStats.indexOf(_s);
        if (idx === 0) return <span className="text-amber-500">🥇</span>;
        if (idx === 1) return <span className="text-gray-400">🥈</span>;
        if (idx === 2) return <span className="text-amber-700">🥉</span>;
        return <span className="text-muted-foreground text-xs">{idx + 1}</span>;
      },
    },
    {
      key: "student_number",
      header: "No",
      width: "100px",
      render: (s) => <span className="font-mono text-xs">{s.student_number}</span>,
    },
    { key: "student_name", header: "Öğrenci" },
    {
      key: "class_name",
      header: "Sınıf",
      width: "100px",
      render: (s) => <Badge variant="info">{s.class_name}</Badge>,
    },
    {
      key: "school_level",
      header: "Seviye",
      width: "120px",
      render: (s) => (
        <span className="text-xs text-muted-foreground capitalize">
          {s.school_level}
        </span>
      ),
    },
    {
      key: "count",
      header: "Okunan",
      align: "center",
      width: "100px",
      render: (s) => (
        <Badge variant="success" className="text-sm font-bold">
          {s.count}
        </Badge>
      ),
    },
    {
      key: "lastBookName",
      header: "Son Okuduğu",
      render: (s) => (
        <div className="min-w-0">
          <p className="text-sm truncate">{s.lastBookName || "-"}</p>
          <p className="text-xs text-muted-foreground">
            {formatDate(s.lastReturnedAt)}
          </p>
        </div>
      ),
    },
  ];

  return (
    <div>
      <PageHeader
        title="Okuma İstatistikleri"
        description="İade edilmiş kitaplar baz alınarak hesaplanır"
      />

      {/* Filtreler */}
      <section className="reading-filter-panel mb-4">
        <button type="button" className="reading-filter-toggle" onClick={() => setFiltersOpen((open) => !open)} aria-expanded={filtersOpen}>
          <span><SlidersHorizontal size={20} /><strong>Filtreler</strong><small>{levelFilter || gradeFilter || classFilter ? "Seçilen sınıf ve seviyeyi düzenle" : "Seviye, sınıf ve şube seç"}</small></span><ChevronDown size={20} />
        </button>
        {filtersOpen && <div className="reading-filter-body"><div className="grid grid-cols-1 md:grid-cols-4 gap-3">
          <DownwardFilter
            label="Okul Seviyesi"
            value={levelFilter}
            onChange={(value) => {
              setLevelFilter(value);
              // Seviye değişince diğer filtreleri sıfırla
              setGradeFilter("");
              setClassFilter("");
            }}
            options={SCHOOL_LEVELS}
          />

          <DownwardFilter
            label="Sınıf"
            value={gradeFilter}
            onChange={(value) => {
              setGradeFilter(value);
              setClassFilter("");
            }}
            options={[{ value: "", label: "Tüm sınıflar" }, ...availableGrades.map((g) => ({ value: g, label: `${g}. Sınıf` }))]}
          />

          <DownwardFilter
            label="Şube"
            value={classFilter}
            onChange={setClassFilter}
            options={[{ value: "", label: "Tüm şubeler" }, ...availableClasses.filter((c) => gradeFilter ? extractGrade(c) === gradeFilter : true).map((c) => ({ value: c, label: c }))]}
          />

          <div className="flex items-end">
            <button
              onClick={clearFilters}
              className="w-full h-10 px-4 text-sm text-muted-foreground hover:text-foreground border border-input rounded-md hover:bg-accent transition-colors"
            >
              Filtreleri Temizle
            </button>
          </div>
        </div>

        {(levelFilter || gradeFilter || classFilter) && (
          <div className="mt-3 flex items-center gap-2 text-xs text-muted-foreground">
            <span>Aktif filtre:</span>
            {levelFilter && (
              <Badge variant="neutral" className="capitalize">{levelFilter}</Badge>
            )}
            {gradeFilter && <Badge variant="neutral">{gradeFilter}. Sınıf</Badge>}
            {classFilter && <Badge variant="neutral">{classFilter}</Badge>}
          </div>
        )}
      </div>}
      </section>

      {/* İstatistik kartları */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-4">
        <MiniStatCard
          label="Toplam Okunan Kitap"
          value={totalBooks}
          icon={BookOpen}
          color="blue"
        />
        <MiniStatCard
          label="Okuyan Öğrenci"
          value={totalStudents}
          icon={UsersIcon}
          color="green"
        />
        <MiniStatCard
          label="Öğrenci Başı Ortalama"
          value={avgPerStudent}
          icon={TrendingUp}
          color="purple"
        />
        <MiniStatCard
          label="En Çok Okuyan"
          value={topReader ? `${topReader.count} kitap` : "-"}
          icon={Trophy}
          color="amber"
        />
      </div>

      <div className="reading-podium" aria-label="En çok okuyan öğrenciler">
        {[2, 0, 1].map((index) => {
          const student = studentStats[index];
          return student && <div key={`${student.student_number}-${student.class_name}`} className={`podium-place podium-${index + 1}`}>
            <span className="podium-medal">{["🥇", "🥈", "🥉"][index]}</span>
            <strong>{student.student_name}</strong><small>{student.class_name} · {student.count} kitap</small>
          </div>;
        })}
      </div>

      {/* Sınıf bazlı özet (sadece sınıf seçili değilken) */}
      {!classFilter && classStats.length > 1 && (
        <div className="reading-classes-section mb-4">
          <div className="reading-classes-header">
            <h2><Layers3 size={21} /> Sınıf Bazında Okuma</h2>
            <div className="reading-class-sort" role="group" aria-label="Sınıf kartlarını sırala">
              <button type="button" aria-pressed={classSort === "class"} onClick={() => setClassSort("class")}>Sınıf bazında</button>
              <button type="button" aria-pressed={classSort === "books"} onClick={() => setClassSort("books")}>Kitap bazında</button>
            </div>
          </div>
          <div className="reading-class-grid">
            {classStats.map((c, index) => (
              <button
                key={c.class_name}
                onClick={() => setClassFilter(c.class_name)}
                className={`reading-class-card reading-class-tone-${index % 5}`}
              >
                <span className="reading-class-symbol"><BookOpen size={19} /></span>
                <strong>{c.class_name}</strong>
                <span className="reading-class-count">{c.count} <small>kitap</small></span>
                <span className="reading-class-students">{c.studentCount} öğrenci <ChevronDown size={14} /></span>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Öğrenci sıralaması */}
      {classFilter && <>
      <div className="mb-2 flex items-center justify-between">
        <h2 className="font-semibold">Öğrenci Sıralaması</h2>
        <span className="text-xs text-muted-foreground">
          {studentStats.length} öğrenci listeleniyor
        </span>
      </div>

      <DataTable
        columns={studentColumns}
        data={studentStats}
        loading={isLoading}
        emptyText="Bu filtreler için iade edilmiş kitap kaydı bulunamadı"
        getRowKey={(s) => `${s.student_number}-${s.class_name}`}
        onRowClick={setSelectedStudent}
      />
      {selectedStudent && <div className="card p-5 mt-4" role="dialog" aria-label="Öğrencinin okuduğu kitaplar">
        <button type="button" className="float-right" onClick={() => setSelectedStudent(null)}>Kapat</button>
        <h3 className="font-semibold mb-3">{selectedStudent.student_name} · Okuduğu kitaplar</h3>
        {filtered.filter((r) => r.student_number === selectedStudent.student_number && r.class_name === selectedStudent.class_name).map((r) =>
          <p key={r.reservation_id} className="border-t py-2">{r.book_name} <span className="text-muted-foreground">· {formatDate(r.returned_at)}</span></p>
        )}
      </div>}
      </>}
    </div>
  );
}
