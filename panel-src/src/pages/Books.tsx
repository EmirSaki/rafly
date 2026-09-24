import { FormEvent, Suspense, lazy, useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, Search, Trash2, Pencil, Download, BookOpen, Camera, Info } from "lucide-react";
import toast from "react-hot-toast";
import { Button } from "@/components/Button";
import { Input } from "@/components/Input";
import { Modal } from "@/components/Modal";
import { PageHeader } from "@/components/PageHeader";
import { DataTable, Column } from "@/components/DataTable";
import { Badge } from "@/components/Badge";
import { useAuthStore } from "@/store/authStore";
import {
  getBookByIsbn,
  getSchoolBooks,
  addBookToSchool,
  updateSchoolBookQuantity,
  deleteSchoolBook,
  type UpdateSchoolBookPayload,
} from "@/api/books";
import { getErrorMessage, getErrorStatus } from "@/api/client";
import { normalizeIsbn, exportToCsv } from "@/lib/utils";
import type { SchoolBook, IsbnLookupResult } from "@/types";

// ZXing kutuphanesi buyuk; sadece tarama acilinca yuklensin diye tembel yukleniyor.
const BarcodeScanner = lazy(() =>
  import("@/components/BarcodeScanner").then((m) => ({ default: m.BarcodeScanner }))
);

export function BooksPage() {
  const school = useAuthStore((s) => s.school);
  const schoolCode = school?.school_code || "";
  const queryClient = useQueryClient();

  const [search, setSearch] = useState("");
  const [isbnSearchOpen, setIsbnSearchOpen] = useState(false);

  const { data: books, isLoading } = useQuery({
    queryKey: ["school-books", schoolCode],
    queryFn: () => getSchoolBooks(schoolCode),
    enabled: !!schoolCode,
  });

  const filtered = useMemo(() => {
    if (!books) return [];
    const q = search.trim().toLocaleLowerCase("tr-TR");
    if (!q) return books;
    return books.filter(
      (b) =>
        (b.title || "").toLocaleLowerCase("tr-TR").includes(q) ||
        (b.authors || []).join(", ").toLocaleLowerCase("tr-TR").includes(q) ||
        String(b.isbn).includes(q)
    );
  }, [books, search]);

  const deleteMutation = useMutation({
    mutationFn: ({ bookId }: { bookId: number }) =>
      deleteSchoolBook(schoolCode, bookId),
    onSuccess: () => {
      toast.success("Kitap envanterden silindi");
      queryClient.invalidateQueries({ queryKey: ["school-books", schoolCode] });
    },
    onError: (err) => toast.error(getErrorMessage(err)),
  });

  async function handleExport() {
    if (!filtered.length) {
      toast.error("Dışa aktarılacak veri yok");
      return;
    }
    const saved = await exportToCsv(
      `kitaplar-${schoolCode}`,
      ["ISBN", "Kitap Adı", "Yazar", "Tür", "Yayınevi", "Sayfa", "Müsait", "Toplam"],
      filtered.map((b) => [
        b.isbn,
        b.title,
        (b.authors || []).join(", ") || "-",
        (b.categories || []).join(", ") || "-",
        b.publisher || "-",
        String(b.page_count || 0),
        String(b.available_quantity),
        String(b.quantity),
      ])
    );
    if (saved) toast.success("Excel dosyası kaydedildi");
  }

  function handleDelete(book: SchoolBook) {
    if (!confirm(`"${book.title}" envanterden silinsin mi?`)) return;
    deleteMutation.mutate({ bookId: book.book_id });
  }

  const columns: Column<SchoolBook>[] = [
    {
      key: "isbn",
      header: "ISBN",
      width: "140px",
      sortable: true,
      render: (b) => <span className="font-mono text-xs">{b.isbn}</span>,
    },
    {
      key: "title",
      header: "Kitap",
      sortable: true,
      sortValue: (b) => b.title || "",
      render: (b) => (
        <div className="flex items-center gap-3">
          <BookCover book={b} />
          <div className="min-w-0">
            <p className="font-medium truncate">{b.title}</p>
            <p className="text-xs text-muted-foreground truncate">
              {(b.authors || []).join(", ") || "-"}
            </p>
          </div>
        </div>
      ),
    },
    {
      key: "categories",
      header: "Tür",
      sortable: true,
      sortValue: (b) => (b.categories || []).join(", "),
      render: (b) => (
        <span className="text-muted-foreground text-xs">
          {(b.categories || []).join(", ") || "-"}
        </span>
      ),
    },
    {
      key: "publisher",
      header: "Yayınevi",
      sortable: true,
      sortValue: (b) => b.publisher || "",
      render: (b) => (
        <span className="text-muted-foreground text-xs">
          {b.publisher || "-"}
        </span>
      ),
    },
    {
      key: "page_count",
      header: "Sayfa",
      align: "center",
      width: "80px",
      sortable: true,
      sortValue: (b) => b.page_count || 0,
      render: (b) => (
        <span className="text-muted-foreground text-xs">
          {b.page_count || "-"}
        </span>
      ),
    },
    {
      key: "available_quantity",
      header: "Müsait",
      align: "center",
      width: "100px",
      render: (b) => (
        <Badge
          variant={
            b.available_quantity === 0
              ? "destructive"
              : b.available_quantity < 3
              ? "warning"
              : "success"
          }
        >
          {b.available_quantity} / {b.quantity}
        </Badge>
      ),
    },
    {
      key: "actions",
      header: "İşlem",
      align: "right",
      width: "120px",
      render: (b) => (
        <div className="flex justify-end gap-1">
          <UpdateQtyButton
            book={b}
            schoolCode={schoolCode}
            onUpdated={() =>
              queryClient.invalidateQueries({
                queryKey: ["school-books", schoolCode],
              })
            }
          />
          <Button
            variant="ghost"
            size="sm"
            onClick={() => handleDelete(b)}
            className="text-destructive hover:text-destructive"
          >
            <Trash2 size={14} />
          </Button>
        </div>
      ),
    },
  ];

  return (
    <div>
      <PageHeader
        title="Kitaplar"
        description={`Okul envanterinde ${filtered.length} kitap`}
        actions={
          <>
            <Button variant="outline" onClick={handleExport}>
              <Download size={16} />
              Excel
            </Button>
            <Button onClick={() => setIsbnSearchOpen(true)}>
              <Plus size={16} />
              Kitap Ekle
            </Button>
          </>
        }
      />

      <div className="card p-4 mb-4">
        <div className="relative">
          <Search
            size={16}
            className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground pointer-events-none"
          />
          <Input
            placeholder="Kitap adı, yazar veya ISBN ara..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-9"
          />
        </div>
      </div>

      <DataTable
        columns={columns}
        data={filtered}
        loading={isLoading}
        emptyText="Envanterde kitap yok"
        getRowKey={(b) => b.book_id}
      />

      <AddBookModal
        open={isbnSearchOpen}
        onClose={() => setIsbnSearchOpen(false)}
        schoolCode={schoolCode}
        onAdded={() =>
          queryClient.invalidateQueries({
            queryKey: ["school-books", schoolCode],
          })
        }
      />
    </div>
  );
}

function BookCover({ book }: { book: SchoolBook }) {
  const [failed, setFailed] = useState(false);
  const url = (book.cover_url || "").trim();
  const showImage = url && !failed;

  return (
    <div className="h-14 w-10 flex-shrink-0 overflow-hidden rounded-md border border-border bg-muted flex items-center justify-center">
      {showImage ? (
        <img
          src={url}
          alt={book.title}
          loading="lazy"
          className="h-full w-full object-cover"
          onError={() => setFailed(true)}
        />
      ) : (
        <BookOpen size={18} className="text-muted-foreground" />
      )}
    </div>
  );
}

interface UpdateQtyButtonProps {
  book: SchoolBook;
  schoolCode: string;
  onUpdated: () => void;
}

function UpdateQtyButton({ book, schoolCode, onUpdated }: UpdateQtyButtonProps) {
  const [open, setOpen] = useState(false);
  const [qty, setQty] = useState(book.quantity);
  const [authors, setAuthors] = useState((book.authors || []).join(", "));
  const [publisher, setPublisher] = useState(book.publisher || "");
  const [categories, setCategories] = useState((book.categories || []).join(", "));
  const [pageCount, setPageCount] = useState(book.page_count || 0);

  const mutation = useMutation({
    mutationFn: () => {
      const payload: UpdateSchoolBookPayload = {
        quantity: qty,
        authors: authors.split(",").map((a) => a.trim()).filter(Boolean),
        publisher,
        categories: categories.split(",").map((c) => c.trim()).filter(Boolean),
        page_count: pageCount,
      };
      return updateSchoolBookQuantity(schoolCode, book.book_id, payload);
    },
    onSuccess: () => {
      toast.success("Kitap bilgileri güncellendi");
      onUpdated();
      setOpen(false);
    },
    onError: (err) => toast.error(getErrorMessage(err)),
  });

  function handleOpen() {
    setQty(book.quantity);
    setAuthors((book.authors || []).join(", "));
    setPublisher(book.publisher || "");
    setCategories((book.categories || []).join(", "));
    setPageCount(book.page_count || 0);
    setOpen(true);
  }

  return (
    <>
      <Button variant="ghost" size="sm" onClick={handleOpen}>
        <Pencil size={14} />
      </Button>
      <Modal
        open={open}
        onClose={() => setOpen(false)}
        title="Kitap Düzenle"
        description={book.title}
        size="lg"
      >
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <p className="text-xs text-muted-foreground mb-1">ISBN</p>
              <p className="text-sm font-mono bg-muted/50 rounded px-2 py-1.5">{book.isbn}</p>
            </div>
            <div>
              <p className="text-xs text-muted-foreground mb-1">Kitap Adı</p>
              <p className="text-sm bg-muted/50 rounded px-2 py-1.5">{book.title}</p>
            </div>
          </div>
          <Input
            label="Yazar(lar)"
            placeholder="Virgülle ayırarak yazın"
            value={authors}
            onChange={(e) => setAuthors(e.target.value)}
          />
          <div className="grid grid-cols-2 gap-3">
            <Input
              label="Yayınevi"
              value={publisher}
              onChange={(e) => setPublisher(e.target.value)}
            />
            <Input
              label="Tür"
              placeholder="Virgülle ayırarak yazın"
              value={categories}
              onChange={(e) => setCategories(e.target.value)}
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Input
              label="Sayfa Sayısı"
              type="number"
              min={0}
              value={pageCount}
              onChange={(e) => setPageCount(Number(e.target.value))}
            />
            <Input
              label="Toplam Adet"
              type="number"
              min={0}
              value={qty}
              onChange={(e) => setQty(Number(e.target.value))}
            />
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setOpen(false)}>
              İptal
            </Button>
            <Button onClick={() => mutation.mutate()} loading={mutation.isPending}>
              Güncelle
            </Button>
          </div>
        </div>
      </Modal>
    </>
  );
}

interface AddBookModalProps {
  open: boolean;
  onClose: () => void;
  schoolCode: string;
  onAdded: () => void;
}

function AddBookModal({ open, onClose, schoolCode, onAdded }: AddBookModalProps) {
  const [isbn, setIsbn] = useState("");
  const [searching, setSearching] = useState(false);
  const [result, setResult] = useState<IsbnLookupResult | null>(null);
  const [quantity, setQuantity] = useState(1);
  const [scanOpen, setScanOpen] = useState(false);

  // Otomatik kayit bulunamadiginda elle giris formu
  const [notFound, setNotFound] = useState(false);
  const [mTitle, setMTitle] = useState("");
  const [mAuthors, setMAuthors] = useState("");
  const [mPublisher, setMPublisher] = useState("");
  const [mCategories, setMCategories] = useState("");
  const [mPageCount, setMPageCount] = useState(0);

  function resetManual() {
    setNotFound(false);
    setMTitle("");
    setMAuthors("");
    setMPublisher("");
    setMCategories("");
    setMPageCount(0);
  }

  async function lookup(rawIsbn: string) {
    const normalized = normalizeIsbn(rawIsbn);
    if (!normalized) {
      toast.error("Geçerli bir ISBN girin");
      return;
    }
    setSearching(true);
    setResult(null);
    resetManual();
    try {
      const data = await getBookByIsbn(normalized);
      if (!data) {
        // Bulunamadi -> elle ekleme formunu ac (mobildeki gibi)
        setQuantity(1);
        setNotFound(true);
        return;
      }
      setResult(data);
    } catch (err) {
      // Backend kitap bulunamayinca 404 firlatiyor -> elle ekleme formunu ac
      if (getErrorStatus(err) === 404) {
        setQuantity(1);
        setNotFound(true);
      } else {
        toast.error(getErrorMessage(err));
      }
    } finally {
      setSearching(false);
    }
  }

  function handleSearch(e: FormEvent) {
    e.preventDefault();
    lookup(isbn);
  }

  const addMutation = useMutation({
    mutationFn: () => {
      if (!result) throw new Error("Önce ISBN ile kitap arayın");
      return addBookToSchool({
        schoolCode,
        isbn: result.isbn,
        title: result.title,
        authors: result.authors,
        publisher: result.publisher,
        categories: result.categories,
        pageCount: result.pageCount,
        volumeCount: result.volumeCount,
        quantity,
      });
    },
    onSuccess: () => {
      toast.success("Kitap envantere eklendi");
      onAdded();
      handleClose();
    },
    onError: (err) => toast.error(getErrorMessage(err)),
  });

  const manualAddMutation = useMutation({
    mutationFn: () => {
      const normalized = normalizeIsbn(isbn);
      if (!normalized) throw new Error("Geçerli bir ISBN girin");
      if (!mTitle.trim()) throw new Error("Kitap adı zorunlu");
      return addBookToSchool({
        schoolCode,
        isbn: normalized,
        title: mTitle.trim(),
        authors: mAuthors
          .split(",")
          .map((a) => a.trim())
          .filter(Boolean),
        publisher: mPublisher.trim() || undefined,
        categories: mCategories
          .split(",")
          .map((c) => c.trim())
          .filter(Boolean),
        pageCount: mPageCount || 0,
        volumeCount: 0,
        quantity,
      });
    },
    onSuccess: () => {
      toast.success("Kitap envantere eklendi");
      onAdded();
      handleClose();
    },
    onError: (err) => toast.error(getErrorMessage(err)),
  });

  function handleClose() {
    setIsbn("");
    setResult(null);
    setQuantity(1);
    setScanOpen(false);
    resetManual();
    onClose();
  }

  return (
    <Modal
      open={open}
      onClose={handleClose}
      title="Kitap Ekle"
      description="ISBN ile arayıp envantere ekleyin"
      size="lg"
    >
      <form onSubmit={handleSearch} className="flex flex-wrap gap-2 mb-4">
        <Input
          placeholder="ISBN gir veya tara..."
          value={isbn}
          onChange={(e) => setIsbn(e.target.value)}
          className="min-w-[160px] flex-1"
          autoFocus
        />
        <Button
          type="button"
          variant="outline"
          onClick={() => setScanOpen(true)}
          title="Kamera ile barkod tara"
        >
          <Camera size={16} />
          Tara
        </Button>
        <Button type="submit" loading={searching}>
          <Search size={16} />
          Ara
        </Button>
      </form>

      {scanOpen && (
        <Suspense fallback={null}>
          <BarcodeScanner
            open
            onClose={() => setScanOpen(false)}
            onDetected={(code) => {
              setIsbn(code);
              setScanOpen(false);
              lookup(code);
            }}
            title="Kitap barkodunu tara"
          />
        </Suspense>
      )}

      {result && (
        <div className="card p-4 space-y-3">
          <div>
            <p className="text-xs text-muted-foreground">Başlık</p>
            <p className="font-medium">{result.title}</p>
          </div>
          <div className="grid grid-cols-2 gap-3 text-sm">
            <div>
              <p className="text-xs text-muted-foreground">Yazar(lar)</p>
              <p>{result.authors.join(", ") || "-"}</p>
            </div>
            <div>
              <p className="text-xs text-muted-foreground">Yayınevi</p>
              <p>{result.publisher}</p>
            </div>
            <div>
              <p className="text-xs text-muted-foreground">Sayfa Sayısı</p>
              <p>{result.pageCount || "-"}</p>
            </div>
            <div>
              <p className="text-xs text-muted-foreground">Kaynak</p>
              <Badge variant={result.source === "local_db" ? "info" : "neutral"}>
                {result.source === "local_db" ? "Lokal Katalog" : "Google Books"}
              </Badge>
            </div>
          </div>

          <Input
            label="Adet"
            type="number"
            min={1}
            value={quantity}
            onChange={(e) => setQuantity(Number(e.target.value))}
          />

          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={handleClose}>
              İptal
            </Button>
            <Button
              onClick={() => addMutation.mutate()}
              loading={addMutation.isPending}
            >
              <Plus size={16} />
              Envantere Ekle
            </Button>
          </div>
        </div>
      )}

      {notFound && !result && (
        <div className="card p-4 space-y-3">
          <div className="flex items-start gap-2 rounded-md border border-amber-100 bg-amber-50 p-3">
            <Info size={16} className="mt-0.5 shrink-0 text-amber-600" />
            <p className="text-xs text-amber-900">
              Bu ISBN için otomatik kayıt bulunamadı. Kitap bilgilerini elle
              girip kütüphaneye ekleyebilirsiniz.
            </p>
          </div>

          <div>
            <p className="mb-1 text-xs text-muted-foreground">ISBN</p>
            <p className="rounded bg-muted/50 px-2 py-1.5 font-mono text-sm">
              {normalizeIsbn(isbn) || isbn}
            </p>
          </div>

          <Input
            label="Kitap Adı *"
            placeholder="Kitabın adı"
            value={mTitle}
            onChange={(e) => setMTitle(e.target.value)}
            autoFocus
          />
          <Input
            label="Yazar(lar)"
            placeholder="Virgülle ayırarak yazın"
            value={mAuthors}
            onChange={(e) => setMAuthors(e.target.value)}
          />
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <Input
              label="Yayınevi"
              value={mPublisher}
              onChange={(e) => setMPublisher(e.target.value)}
            />
            <Input
              label="Tür"
              placeholder="Virgülle ayırarak yazın"
              value={mCategories}
              onChange={(e) => setMCategories(e.target.value)}
            />
          </div>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <Input
              label="Sayfa Sayısı"
              type="number"
              min={0}
              value={mPageCount}
              onChange={(e) => setMPageCount(Number(e.target.value))}
            />
            <Input
              label="Adet"
              type="number"
              min={1}
              value={quantity}
              onChange={(e) => setQuantity(Number(e.target.value))}
            />
          </div>

          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={handleClose}>
              İptal
            </Button>
            <Button
              onClick={() => manualAddMutation.mutate()}
              loading={manualAddMutation.isPending}
            >
              <Plus size={16} />
              Envantere Ekle
            </Button>
          </div>
        </div>
      )}
    </Modal>
  );
}
