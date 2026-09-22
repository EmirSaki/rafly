import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { BookOpen, TrendingUp, Users as UsersIcon, Trophy } from "lucide-react";
import { PageHeader } from "@/components/PageHeader";
import { DataTable, Column } from "@/components/DataTable";
import { Badge } from "@/components/Badge";
import { Select } from "@/components/Select";
import { Input } from "@/components/Input";
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
      availableClasses: Array.from(classes).sort(),
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
      .sort((a, b) => b.count - a.count);
  }, [filtered]);

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
      <div className="card p-4 mb-4">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
          <Select
            label="Okul Seviyesi"
            value={levelFilter}
            onChange={(e) => {
              setLevelFilter(e.target.value);
              // Seviye değişince diğer filtreleri sıfırla
              setGradeFilter("");
              setClassFilter("");
            }}
          >
            {SCHOOL_LEVELS.map((l) => (
              <option key={l.value} value={l.value}>
                {l.label}
              </option>
            ))}
          </Select>

          <Select
            label="Sınıf"
            value={gradeFilter}
            onChange={(e) => {
              setGradeFilter(e.target.value);
              setClassFilter("");
            }}
          >
            <option value="">Tüm sınıflar</option>
            {availableGrades.map((g) => (
              <option key={g} value={g}>
                {g}. Sınıf
              </option>
            ))}
          </Select>

          <Select
            label="Şube"
            value={classFilter}
            onChange={(e) => setClassFilter(e.target.value)}
          >
            <option value="">Tüm şubeler</option>
            {availableClasses
              .filter((c) =>
                gradeFilter ? extractGrade(c) === gradeFilter : true
              )
              .map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
          </Select>

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
      </div>

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

      {/* Sınıf bazlı özet (sadece sınıf seçili değilken) */}
      {!classFilter && classStats.length > 1 && (
        <div className="card p-5 mb-4">
          <h2 className="font-semibold mb-3">Sınıf Bazında Okuma</h2>
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-2">
            {classStats.map((c) => (
              <button
                key={c.class_name}
                onClick={() => setClassFilter(c.class_name)}
                className="text-left p-3 rounded-md border hover:bg-muted/30 transition-colors"
              >
                <p className="text-xs text-muted-foreground">{c.class_name}</p>
                <p className="text-xl font-bold">{c.count}</p>
                <p className="text-[10px] text-muted-foreground">
                  {c.studentCount} öğrenci
                </p>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Öğrenci sıralaması */}
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
      />
    </div>
  );
}
