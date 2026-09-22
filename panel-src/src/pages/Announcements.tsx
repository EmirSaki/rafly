import { useState, useRef } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Megaphone,
  Plus,
  Trash2,
  ImagePlus,
  X,
  Calendar,
  Users,
  GraduationCap,
  School,
} from "lucide-react";
import toast from "react-hot-toast";
import { Button } from "@/components/Button";
import { Input } from "@/components/Input";
import { Modal } from "@/components/Modal";
import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/Badge";
import { useAuthStore } from "@/store/authStore";
import { getStudents } from "@/api/students";
import {
  getAnnouncements,
  createAnnouncement,
  deleteAnnouncement,
  getAnnouncementImagesById,
  type Announcement,
} from "@/api/announcements";
import { getErrorMessage } from "@/api/client";
import { formatDate } from "@/lib/utils";
import { cn } from "@/lib/utils";

const TARGET_TYPES = [
  { value: "all", label: "Okul Geneli", icon: School },
  { value: "school_level", label: "Okul Seviyesi", icon: GraduationCap },
  { value: "class", label: "Sınıf", icon: Users },
] as const;

const SCHOOL_LEVELS = [
  { value: "ilkokul", label: "İlkokul" },
  { value: "ortaokul", label: "Ortaokul" },
  { value: "lise", label: "Lise" },
  { value: "hazırlık", label: "Hazırlık" },
  { value: "diğer", label: "Diğer" },
];

export function AnnouncementsPage() {
  const school = useAuthStore((s) => s.school);
  const user = useAuthStore((s) => s.user);
  const schoolCode = school?.school_code || "";
  const queryClient = useQueryClient();

  const [createOpen, setCreateOpen] = useState(false);

  const { data: announcements = [], isLoading } = useQuery({
    queryKey: ["announcements", schoolCode],
    queryFn: () => getAnnouncements(schoolCode),
    enabled: !!schoolCode,
  });

  const deleteMut = useMutation({
    mutationFn: (id: number) => deleteAnnouncement(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["announcements"] });
      toast.success("Bilgilendirme silindi");
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  });

  const now = new Date();

  const activeAnnouncements = announcements.filter((a) => {
    const end = new Date(a.end_date);
    return end >= now;
  });

  const pastAnnouncements = announcements.filter((a) => {
    const end = new Date(a.end_date);
    return end < now;
  });

  return (
    <div>
      <PageHeader
        title="Bilgilendirme"
        description="Öğrenci ve personele duyuru gönder"
        actions={
          <Button onClick={() => setCreateOpen(true)}>
            <Plus size={16} />
            Yeni Bilgilendirme
          </Button>
        }
      />

      {isLoading ? (
        <p className="text-sm text-muted-foreground">Yükleniyor...</p>
      ) : announcements.length === 0 ? (
        <div className="card p-12 text-center">
          <Megaphone className="mx-auto text-muted-foreground mb-3" size={40} />
          <p className="text-muted-foreground">Henüz bilgilendirme yok</p>
          <p className="text-xs text-muted-foreground mt-1">
            "Yeni Bilgilendirme" butonuna tıklayarak ilk duyurunuzu oluşturun
          </p>
        </div>
      ) : (
        <div className="space-y-6">
          {activeAnnouncements.length > 0 && (
            <div>
              <h2 className="text-sm font-semibold text-muted-foreground mb-3 uppercase tracking-wide">
                Aktif Bilgilendirmeler
              </h2>
              <div className="space-y-3">
                {activeAnnouncements.map((a) => (
                  <AnnouncementCard
                    key={a.id}
                    announcement={a}
                    onDelete={() => deleteMut.mutate(a.id)}
                    deleting={deleteMut.isPending}
                  />
                ))}
              </div>
            </div>
          )}

          {pastAnnouncements.length > 0 && (
            <div>
              <h2 className="text-sm font-semibold text-muted-foreground mb-3 uppercase tracking-wide">
                Geçmiş Bilgilendirmeler
              </h2>
              <div className="space-y-3">
                {pastAnnouncements.map((a) => (
                  <AnnouncementCard
                    key={a.id}
                    announcement={a}
                    onDelete={() => deleteMut.mutate(a.id)}
                    deleting={deleteMut.isPending}
                    past
                  />
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {createOpen && (
        <CreateAnnouncementModal
          open={createOpen}
          onClose={() => setCreateOpen(false)}
          schoolCode={schoolCode}
          senderName={`${user?.user_name ?? ""} ${user?.user_surname ?? ""}`.trim()}
        />
      )}
    </div>
  );
}

function AnnouncementCard({
  announcement: a,
  onDelete,
  deleting,
  past,
}: {
  announcement: Announcement;
  onDelete: () => void;
  deleting: boolean;
  past?: boolean;
}) {
  const targetLabel = TARGET_TYPES.find((t) => t.value === a.target_type)?.label ?? a.target_type;
  const imageCount = a.image_count ?? 0;

  const { data: images = [] } = useQuery({
    queryKey: ["announcement-images", a.id],
    queryFn: () => getAnnouncementImagesById(a.id),
    enabled: imageCount > 0,
    staleTime: 5 * 60 * 1000,
  });

  return (
    <div className={cn("card p-5", past && "opacity-60")}>
      <div className="flex items-start gap-4">
        {images.length > 0 && (
          <div className="flex gap-1.5 shrink-0">
            {images.slice(0, 3).map((url, i) => (
              <img
                key={i}
                src={url}
                alt=""
                className="w-20 h-20 rounded-lg object-cover"
              />
            ))}
            {images.length > 3 && (
              <div className="w-20 h-20 rounded-lg bg-muted flex items-center justify-center text-xs font-semibold text-muted-foreground">
                +{images.length - 3}
              </div>
            )}
          </div>
        )}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <h3 className="font-semibold truncate">{a.title}</h3>
            <Badge variant={past ? "neutral" : "success"}>
              {past ? "Sona Erdi" : "Aktif"}
            </Badge>
            {imageCount > 1 && (
              <Badge variant="info">{imageCount} foto</Badge>
            )}
          </div>
          <p className="text-sm text-muted-foreground whitespace-pre-wrap line-clamp-3">
            {a.content}
          </p>
          <div className="flex flex-wrap items-center gap-3 mt-3 text-xs text-muted-foreground">
            <span className="flex items-center gap-1">
              <Calendar size={12} />
              {formatDate(a.start_date)} – {formatDate(a.end_date)}
            </span>
            <Badge variant="info">{targetLabel}</Badge>
            {a.target_type !== "all" && a.target_values?.length > 0 && (
              <span>{a.target_values.join(", ")}</span>
            )}
            <span className="ml-auto font-medium text-foreground">
              {a.sender_name}
            </span>
          </div>
        </div>
        <button
          onClick={onDelete}
          disabled={deleting}
          className="p-2 rounded-md text-muted-foreground hover:text-destructive hover:bg-destructive/10 transition-colors shrink-0"
          title="Sil"
        >
          <Trash2 size={16} />
        </button>
      </div>
    </div>
  );
}

function CreateAnnouncementModal({
  open,
  onClose,
  schoolCode,
  senderName,
}: {
  open: boolean;
  onClose: () => void;
  schoolCode: string;
  senderName: string;
}) {
  const queryClient = useQueryClient();

  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");
  const [targetType, setTargetType] = useState<"all" | "school_level" | "class">("all");
  const [selectedValues, setSelectedValues] = useState<string[]>([]);
  const [startDate, setStartDate] = useState(() => new Date().toISOString().split("T")[0]);
  const [endDate, setEndDate] = useState("");
  const [imageFiles, setImageFiles] = useState<File[]>([]);
  const [imagePreviews, setImagePreviews] = useState<string[]>([]);

  const { data: students = [] } = useQuery({
    queryKey: ["students", schoolCode],
    queryFn: () => getStudents({ schoolCode }),
    enabled: !!schoolCode,
  });

  const classOptions = [...new Set(
    students
      .map((s) => s.class_name?.toString().trim().toUpperCase())
      .filter((c): c is string => !!c && c.length > 0)
  )].sort();

  const createMut = useMutation({
    mutationFn: () =>
      createAnnouncement(
        {
          schoolCode,
          title,
          content,
          target_type: targetType,
          target_values: targetType === "all" ? [] : selectedValues,
          start_date: startDate,
          end_date: endDate,
        },
        imageFiles.length > 0 ? imageFiles : undefined
      ),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["announcements"] });
      toast.success("Bilgilendirme gönderildi");
      onClose();
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  });

  const fileInputRef = useRef<HTMLInputElement>(null);

  function handlePickImages() {
    fileInputRef.current?.click();
  }

  function handleFilesSelected(e: React.ChangeEvent<HTMLInputElement>) {
    const selected = e.target.files;
    if (!selected || selected.length === 0) return;

    const newFiles: File[] = [];
    const newPreviews: string[] = [];

    for (const file of Array.from(selected)) {
      if (file.size > 10 * 1024 * 1024) {
        toast.error(`${file.name} 10MB'dan büyük, atlandı`);
        continue;
      }
      newFiles.push(file);
      newPreviews.push(URL.createObjectURL(file));
    }

    if (newFiles.length > 0) {
      setImageFiles((prev) => [...prev, ...newFiles]);
      setImagePreviews((prev) => [...prev, ...newPreviews]);
    }

    // Aynı dosyayı tekrar seçebilmek için input'u sıfırla
    e.target.value = "";
  }

  function removeImage(index: number) {
    URL.revokeObjectURL(imagePreviews[index]);
    setImageFiles((prev) => prev.filter((_, i) => i !== index));
    setImagePreviews((prev) => prev.filter((_, i) => i !== index));
  }

  function toggleValue(val: string) {
    setSelectedValues((prev) =>
      prev.includes(val) ? prev.filter((v) => v !== val) : [...prev, val]
    );
  }

  const targetOptions =
    targetType === "school_level"
      ? SCHOOL_LEVELS
      : targetType === "class"
      ? classOptions.map((c) => ({ value: c, label: c }))
      : [];

  const canSubmit =
    title.trim() &&
    content.trim() &&
    startDate &&
    endDate &&
    (targetType === "all" || selectedValues.length > 0);

  return (
    <Modal open={open} onClose={onClose} title="Yeni Bilgilendirme" size="lg">
      <div className="space-y-5">
        <Input
          label="Başlık"
          placeholder="Bilgilendirme başlığı"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
        />

        <div className="space-y-1.5">
          <label className="text-sm font-medium">İçerik</label>
          <textarea
            className="flex w-full rounded-md border border-input bg-background px-3 py-2 text-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-1 min-h-[100px] resize-y"
            placeholder="Bilgilendirme metni..."
            value={content}
            onChange={(e) => setContent(e.target.value)}
          />
        </div>

        <div className="space-y-1.5">
          <label className="text-sm font-medium">
            Fotoğraflar (İsteğe Bağlı)
            {imageFiles.length > 0 && (
              <span className="text-muted-foreground font-normal ml-1">
                — {imageFiles.length} seçili
              </span>
            )}
          </label>

          {imagePreviews.length > 0 && (
            <div className="flex gap-2 flex-wrap">
              {imagePreviews.map((src, i) => (
                <div key={i} className="relative group">
                  <img
                    src={src}
                    alt=""
                    className="h-24 w-24 rounded-lg object-cover"
                  />
                  <div className="absolute bottom-1 left-1 bg-black/60 text-white text-[10px] font-semibold px-1.5 py-0.5 rounded">
                    {i + 1}
                  </div>
                  <button
                    onClick={() => removeImage(i)}
                    className="absolute -top-2 -right-2 bg-destructive text-white rounded-full p-0.5 opacity-0 group-hover:opacity-100 transition-opacity"
                  >
                    <X size={14} />
                  </button>
                </div>
              ))}
            </div>
          )}

          <input
            ref={fileInputRef}
            type="file"
            accept="image/png,image/jpeg,image/webp"
            multiple
            onChange={handleFilesSelected}
            className="hidden"
          />
          <button
            type="button"
            onClick={handlePickImages}
            className="flex items-center gap-2 px-4 py-2 rounded-md border border-dashed border-input text-sm text-muted-foreground hover:border-primary hover:text-primary transition-colors"
          >
            <ImagePlus size={16} />
            {imageFiles.length === 0 ? "Fotoğraf Ekle" : "Daha Fazla Ekle"}
          </button>
        </div>

        <div className="space-y-1.5">
          <label className="text-sm font-medium">Hedef Kitle</label>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
            {TARGET_TYPES.map((t) => (
              <button
                key={t.value}
                onClick={() => {
                  setTargetType(t.value);
                  setSelectedValues([]);
                }}
                className={cn(
                  "flex items-center gap-2 px-3 py-2 rounded-md border text-sm font-medium transition-colors",
                  targetType === t.value
                    ? "border-primary bg-primary/5 text-primary"
                    : "border-input text-muted-foreground hover:border-primary/50"
                )}
              >
                <t.icon size={16} />
                {t.label}
              </button>
            ))}
          </div>
        </div>

        {targetType !== "all" && targetOptions.length > 0 && (
          <div className="space-y-1.5">
            <label className="text-sm font-medium">
              {targetType === "school_level"
                ? "Okul Seviyeleri"
                : "Sınıflar"}{" "}
              <span className="text-muted-foreground font-normal">
                (çoklu seçim)
              </span>
            </label>
            <div className="flex flex-wrap gap-2 max-h-40 overflow-y-auto p-2 border rounded-md">
              {targetOptions.map((opt) => {
                const selected = selectedValues.includes(opt.value);
                return (
                  <button
                    key={opt.value}
                    onClick={() => toggleValue(opt.value)}
                    className={cn(
                      "px-3 py-1.5 rounded-full text-xs font-medium border transition-colors",
                      selected
                        ? "bg-primary text-primary-foreground border-primary"
                        : "bg-background text-muted-foreground border-input hover:border-primary/50"
                    )}
                  >
                    {opt.label}
                  </button>
                );
              })}
            </div>
            {selectedValues.length > 0 && (
              <p className="text-xs text-muted-foreground">
                {selectedValues.length} seçili
              </p>
            )}
          </div>
        )}

        <div className="grid grid-cols-2 gap-4">
          <Input
            label="Başlangıç Tarihi"
            type="date"
            value={startDate}
            onChange={(e) => setStartDate(e.target.value)}
          />
          <Input
            label="Bitiş Tarihi"
            type="date"
            value={endDate}
            min={startDate}
            onChange={(e) => setEndDate(e.target.value)}
          />
        </div>

        <div className="flex items-center justify-between pt-2 border-t">
          <p className="text-xs text-muted-foreground">
            Gönderen: <span className="font-medium text-foreground">{senderName}</span>
          </p>
          <div className="flex items-center gap-2">
            <Button variant="ghost" onClick={onClose}>
              İptal
            </Button>
            <Button
              onClick={() => createMut.mutate()}
              disabled={!canSubmit}
              loading={createMut.isPending}
            >
              <Megaphone size={16} />
              Gönder
            </Button>
          </div>
        </div>
      </div>
    </Modal>
  );
}
