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
  // Parent her render'da yeni fonksiyon verirse kamera yeniden baslamasin diye ref'te tutuyoruz.
  const onDetectedRef = useRef(onDetected);
  onDetectedRef.current = onDetected;

  const [error, setError] = useState<string | null>(null);
  const [manual, setManual] = useState("");

  useEffect(() => {
    if (!open) return;

    doneRef.current = false;
    setError(null);
    setManual("");

    let cancelled = false;
    const hints = new Map();
    hints.set(DecodeHintType.POSSIBLE_FORMATS, FORMATS);
    const reader = new BrowserMultiFormatReader(hints);

    (async () => {
      try {
        if (!window.isSecureContext) throw new Error("insecure");
        if (!navigator.mediaDevices?.getUserMedia) throw new Error("unsupported");

        const controls = await reader.decodeFromConstraints(
          { video: { facingMode: { ideal: "environment" } } },
          videoRef.current!,
          (result, _err, ctrl) => {
            if (!result || doneRef.current) return;
            const text = result.getText().trim();
            if (!text) return;
            doneRef.current = true;
            ctrl?.stop();
            try {
              navigator.vibrate?.(60);
            } catch {
              /* yoksay */
            }
            onDetectedRef.current(text);
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
          setError("Bu tarayici kamera erisimini desteklemiyor. Kodu elle girebilirsiniz.");
        } else if (err.name === "NotAllowedError" || err.name === "SecurityError") {
          setError(
            "Kamera izni verilmedi. Tarayici ayarlarindan kamera erisimine izin verip tekrar deneyin."
          );
        } else if (err.name === "NotFoundError" || err.name === "OverconstrainedError") {
          setError("Kullanilabilir bir kamera bulunamadi. Kodu elle girebilirsiniz.");
        } else {
          setError("Kamera baslatilamadi. Kodu elle girebilirsiniz.");
        }
      }
    })();

    return () => {
      cancelled = true;
      controlsRef.current?.stop();
      controlsRef.current = null;
    };
  }, [open]);

  if (!open) return null;

  function submitManual() {
    const v = manual.trim();
    if (!v) return;
    doneRef.current = true;
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
            Barkodu cerceveye hizalayin
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
