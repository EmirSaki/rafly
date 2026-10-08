import { useEffect, useRef, useState } from "react";
import { BrowserMultiFormatReader, type IScannerControls } from "@zxing/browser";
import { BarcodeFormat, DecodeHintType } from "@zxing/library";
import { X, Camera } from "lucide-react";

interface BarcodeScannerProps {
  open: boolean;
  onClose: () => void;
  onDetected: (code: string) => void;
  title?: string;
}

// ISBN barkodlari EAN-13'tur; kutuphane etiketlerinde CODE_128/39 de gorulebilir.
const FORMATS = [
  BarcodeFormat.EAN_13,
  BarcodeFormat.EAN_8,
  BarcodeFormat.UPC_A,
  BarcodeFormat.UPC_E,
  BarcodeFormat.CODE_128,
  BarcodeFormat.CODE_39,
];

export function BarcodeScanner({
  open,
  onClose,
  onDetected,
  title = "Barkod Tara",
}: BarcodeScannerProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const controlsRef = useRef<IScannerControls | null>(null);
  const doneRef = useRef(false);
  // USB barkod okuyucu (keyboard-wedge) icin tus tamponu.
  const wedgeBufRef = useRef("");
  const wedgeTimeRef = useRef(0);
  // Parent her render'da yeni fonksiyon verirse kamera yeniden baslamasin diye ref'te tutuyoruz.
  const onDetectedRef = useRef(onDetected);
  onDetectedRef.current = onDetected;

  const [error, setError] = useState<string | null>(null);
  const [manual, setManual] = useState("");

  useEffect(() => {
    if (!open) return;

    doneRef.current = false;
    wedgeBufRef.current = "";
    wedgeTimeRef.current = 0;
    setError(null);
    setManual("");

    // Okunan kodu (kamera veya USB okuyucu) tek yerden isle.
    const commit = (raw: string) => {
      const text = (raw || "").trim();
      if (!text || doneRef.current) return;
      doneRef.current = true;
      controlsRef.current?.stop();
      try {
        navigator.vibrate?.(60);
      } catch {
        /* yoksay */
      }
      onDetectedRef.current(text);
    };

    // ── USB barkod okuyucu (keyboard-wedge) ──
    // Cihaz kodu klavye gibi hizlica yazip Enter'a basar; kamera olmasa da calisir.
    const onKeyDown = (e: KeyboardEvent) => {
      if (doneRef.current) return;
      const t = e.target as HTMLElement | null;
      // Elle giris kutusu kendi Enter'ini isler, karismayalim.
      if (t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA")) return;
      if (e.key === "Enter" || e.key === "Tab") {
        const code = wedgeBufRef.current.trim();
        wedgeBufRef.current = "";
        if (code.length >= 3) {
          e.preventDefault();
          commit(code);
        }
        return;
      }
      if (e.key.length === 1) {
        const now = Date.now();
        // Tuslar arasi 300ms'den uzun bosluk varsa yeni okuma say.
        if (now - wedgeTimeRef.current > 300) wedgeBufRef.current = "";
        wedgeTimeRef.current = now;
        wedgeBufRef.current += e.key;
      }
    };
    window.addEventListener("keydown", onKeyDown);

    let cancelled = false;
    const hints = new Map();
    hints.set(DecodeHintType.POSSIBLE_FORMATS, FORMATS);
    // Bulanik/kucuk ISBN etiketlerinde cozulme sansini artirir (ozellikle iOS).
    hints.set(DecodeHintType.TRY_HARDER, true);
    const reader = new BrowserMultiFormatReader(hints, {
      // Varsayilan 500ms; daha sik deneme = daha cabuk yakalama.
      delayBetweenScanAttempts: 150,
      delayBetweenScanSuccess: 300,
    });

    (async () => {
      try {
        if (!window.isSecureContext) throw new Error("insecure");
        if (!navigator.mediaDevices?.getUserMedia) throw new Error("unsupported");

        const controls = await reader.decodeFromConstraints(
          {
            video: {
              facingMode: { ideal: "environment" },
              // Daha yuksek cozunurluk kucuk barkodlari netlestirir (iOS'ta onemli).
              width: { ideal: 1280 },
              height: { ideal: 720 },
            },
          },
          videoRef.current!,
          (result, _err, ctrl) => {
            if (!result || doneRef.current) return;
            const text = result.getText().trim();
            if (!text) return;
            ctrl?.stop();
            commit(text);
          }
        );

        if (cancelled) {
          controls.stop();
          return;
        }
        controlsRef.current = controls;
      } catch (e: unknown) {
        if (cancelled) return;
        const err = e as { name?: string; message?: string };
        if (err.message === "insecure") {
          setError("Kamera yalnizca guvenli (HTTPS) baglantida calisir.");
        } else if (err.message === "unsupported") {
          setError(
            "Bu tarayici kamera erisimini desteklemiyor. USB barkod okuyucuyla okutabilir veya kodu elle girebilirsiniz."
          );
        } else if (err.name === "NotAllowedError" || err.name === "SecurityError") {
          setError(
            "Kamera izni verilmedi. USB barkod okuyucuyla okutabilir ya da izin verip tekrar deneyebilirsiniz."
          );
        } else if (err.name === "NotFoundError" || err.name === "OverconstrainedError") {
          setError(
            "Kullanilabilir bir kamera bulunamadi. USB barkod okuyucuyla okutabilir veya kodu elle girebilirsiniz."
          );
        } else {
          setError(
            "Kamera baslatilamadi. USB barkod okuyucuyla okutabilir veya kodu elle girebilirsiniz."
          );
        }
      }
    })();

    return () => {
      cancelled = true;
      window.removeEventListener("keydown", onKeyDown);
      controlsRef.current?.stop();
      controlsRef.current = null;
    };
  }, [open]);

  if (!open) return null;

  function submitManual() {
    const v = manual.trim();
    if (!v) return;
    doneRef.current = true;
    controlsRef.current?.stop();
    onDetectedRef.current(v);
    setManual("");
  }

  return (
    <div className="fixed inset-0 z-[60] flex flex-col bg-black/90">
      {/* Baslik */}
      <div className="flex items-center justify-between p-4 text-white">
        <div className="flex items-center gap-2">
          <Camera size={18} />
          <span className="font-medium">{title}</span>
        </div>
        <button
          onClick={onClose}
          aria-label="Kapat"
          className="rounded-md p-2 hover:bg-white/10"
        >
          <X size={22} />
        </button>
      </div>

      {/* Kamera goruntusu */}
      <div className="relative flex-1 overflow-hidden">
        <video
          ref={videoRef}
          className="absolute inset-0 h-full w-full object-cover"
          playsInline
          muted
          autoPlay
        />
        {!error && (
          <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
            <div className="aspect-[3/2] w-64 max-w-[80%] rounded-lg border-2 border-white/80 shadow-[0_0_0_9999px_rgba(0,0,0,0.35)]" />
          </div>
        )}
        {error && (
          <div className="absolute inset-0 flex items-center justify-center p-6">
            <p className="max-w-sm rounded-lg bg-black/60 p-4 text-center text-sm text-white/90">
              {error}
            </p>
          </div>
        )}
      </div>

      {/* Alt kisim: ipucu + elle giris yedegi */}
      <div className="space-y-3 bg-black/60 p-4">
        {!error && (
          <p className="text-center text-sm text-white/70">
            Barkodu cerceveye hizalayin &mdash; veya USB okuyucuyla okutun
          </p>
        )}
        <div className="mx-auto flex max-w-md gap-2">
          <input
            value={manual}
            onChange={(e) => setManual(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.preventDefault();
                submitManual();
              }
            }}
            inputMode="numeric"
            placeholder="Kodu elle gir"
            className="h-11 flex-1 rounded-md border border-white/20 bg-white/10 px-3 text-white placeholder:text-white/50 focus:outline-none focus:ring-2 focus:ring-white/40"
          />
          <button
            onClick={submitManual}
            className="h-11 shrink-0 rounded-md bg-white px-4 font-medium text-black"
          >
            Kullan
          </button>
        </div>
      </div>
    </div>
  );
}
