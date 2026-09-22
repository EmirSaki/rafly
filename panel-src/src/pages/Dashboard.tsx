import { useQuery } from "@tanstack/react-query";
import { Users, BookOpen, ClipboardList, Clock, Library } from "lucide-react";
import { useAuthStore } from "@/store/authStore";
import { getStudents } from "@/api/students";
import { getSchoolBooks } from "@/api/books";
import { getReservations } from "@/api/reservations";
import { PageHeader } from "@/components/PageHeader";
import { cn } from "@/lib/utils";

interface StatCardProps {
  label: string;
  value: number | string;
  icon: any;
  loading?: boolean;
  color?: "blue" | "green" | "amber" | "purple" | "teal";
  hint?: string;
}

function StatCard({
  label,
  value,
  icon: Icon,
  loading,
  color = "blue",
  hint,
}: StatCardProps) {
  const colorClasses = {
    blue: "bg-blue-50 text-blue-600",
    green: "bg-green-50 text-green-600",
    amber: "bg-amber-50 text-amber-600",
    purple: "bg-purple-50 text-purple-600",
    teal: "bg-teal-50 text-teal-600",
  };
  return (
    <div className="card p-5">
      <div className="flex items-center justify-between">
        <div className="min-w-0">
          <p className="text-sm text-muted-foreground">{label}</p>
          <p className="text-3xl font-bold mt-2">
            {loading ? <span className="text-muted-foreground">...</span> : value}
          </p>
          {hint && !loading && (
            <p className="text-xs text-muted-foreground mt-1">{hint}</p>
          )}
        </div>
        <div className={cn("p-3 rounded-lg shrink-0", colorClasses[color])}>
          <Icon size={24} />
        </div>
      </div>
    </div>
  );
}

export function DashboardPage() {
  const school = useAuthStore((s) => s.school);
  const schoolCode = school?.school_code || "";

  const { data: students, isLoading: studentsLoading } = useQuery({
    queryKey: ["students", schoolCode],
    queryFn: () => getStudents({ schoolCode }),
    enabled: !!schoolCode,
  });

  const { data: books, isLoading: booksLoading } = useQuery({
    queryKey: ["school-books", schoolCode],
    queryFn: () => getSchoolBooks(schoolCode),
    enabled: !!schoolCode,
  });

  const { data: reservations, isLoading: reservationsLoading } = useQuery({
    queryKey: ["reservations", schoolCode],
    queryFn: () => getReservations({ schoolCode }),
    enabled: !!schoolCode,
  });

  const pendingCount =
    reservations?.filter((r) => r.status === "pending_approval").length ?? 0;
  const loanedCount =
    reservations?.filter((r) => r.status === "loaned").length ?? 0;

  const totalQuantity =
    books?.reduce((sum, b) => sum + (Number(b.quantity) || 0), 0) ?? 0;
  const totalAvailable =
    books?.reduce((sum, b) => sum + (Number(b.available_quantity) || 0), 0) ?? 0;

  return (
    <div>
      <PageHeader
        title="Anasayfa"
        description="Kütüphane genel görünümü"
      />

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">
        <StatCard
          label="Toplam Öğrenci"
          value={students?.length ?? 0}
          icon={Users}
          loading={studentsLoading}
          color="blue"
        />
        <StatCard
          label="Kitap Çeşidi"
          value={books?.length ?? 0}
          icon={BookOpen}
          loading={booksLoading}
          color="green"
          hint="farklı başlık"
        />
        <StatCard
          label="Toplam Kitap Adedi"
          value={totalQuantity}
          icon={Library}
          loading={booksLoading}
          color="teal"
          hint={`${totalAvailable} müsait`}
        />
        <StatCard
          label="Bekleyen Talep"
          value={pendingCount}
          icon={Clock}
          loading={reservationsLoading}
          color="amber"
        />
        <StatCard
          label="Ödünç Verilen"
          value={loanedCount}
          icon={ClipboardList}
          loading={reservationsLoading}
          color="purple"
        />
      </div>

      <div className="mt-8 grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div className="card p-5">
          <h2 className="font-semibold mb-3">Son Rezervasyonlar</h2>
          {reservationsLoading ? (
            <p className="text-sm text-muted-foreground">Yükleniyor...</p>
          ) : reservations && reservations.length > 0 ? (
            <div className="space-y-2">
              {reservations.slice(0, 5).map((r) => (
                <div
                  key={r.reservation_id}
                  className="flex items-center justify-between py-2 border-b last:border-0 text-sm"
                >
                  <div className="min-w-0 flex-1">
                    <p className="font-medium truncate">{r.book_name}</p>
                    <p className="text-xs text-muted-foreground truncate">
                      {r.student_name} · {r.class_name || "-"}
                    </p>
                  </div>
                  <span className="text-xs text-muted-foreground ml-3">
                    {r.status}
                  </span>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-sm text-muted-foreground">Rezervasyon yok</p>
          )}
        </div>

        <div className="card p-5">
          <h2 className="font-semibold mb-3">Hızlı İşlemler</h2>
          <div className="space-y-2 text-sm">
            <p className="text-muted-foreground">
              Soldaki menüden öğrenci ve kitap yönetimine, rezervasyonlara
              ulaşabilirsiniz. "Hızlı Ödünç" sayfasında öğrenci numarası ve
              ISBN'i girerek tek tıkla ödünç verme işlemi yapabilirsiniz.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
