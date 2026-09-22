import { useState } from 'react';
import toast from 'react-hot-toast';
import { apiClient, getErrorMessage } from '@/api/client';
import { Modal } from './Modal';
import { Button } from './Button';

type Preview = {
  token: string;
  summary: { updated: number; added: number; removed: number; activeReservations: number };
  removed: { student_id: number; student_number: string; full_name: string; class_name: string; reason: string }[];
  changes: { student_number: string; full_name: string; old_class: string; new_class: string }[];
};

export function StudentPromotionModal({ schoolCode, onClose, onDone }: { schoolCode: string; onClose: () => void; onDone: () => void }) {
  const [scope, setScope] = useState('');
  const [files, setFiles] = useState<File[]>([]);
  const [preview, setPreview] = useState<Preview | null>(null);
  const [reportToken, setReportToken] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [busy, setBusy] = useState('');
  function reset() { setPreview(null); setReportToken(''); setConfirmed(false); }
  async function request(phase: string, token = '') {
    const body = new FormData();
    files.forEach(file => body.append('files', file));
    body.append('scope', scope);
    body.append('token', token);
    body.append('confirm', String(confirmed));
    return (await apiClient.post(`/api/students/promotion/${phase}`, body, {
      params: { schoolCode }, headers: { 'Content-Type': 'multipart/form-data' }, timeout: 120000,
    })).data;
  }
  async function run(phase: 'preview' | 'report' | 'commit') {
    setBusy(phase);
    try {
      if (phase === 'preview') { reset(); setPreview(await request('preview')); }
      if (phase === 'report') {
        const result = await request('report', preview!.token);
        const bytes = Uint8Array.from(atob(result.file), c => c.charCodeAt(0));
        const url = URL.createObjectURL(new Blob([bytes], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }));
        const link = document.createElement('a');
        link.href = url; link.download = result.filename;
        document.body.appendChild(link); link.click(); link.remove();
        window.setTimeout(() => URL.revokeObjectURL(url), 60000);
        setReportToken(result.token);
      }
      if (phase === 'commit') {
        await request('commit', reportToken);
        toast.success('Sınıflar güncellendi; yeni öğrenciler eklendi ve listede olmayanlar silindi.');
        onDone(); onClose();
      }
    } catch (error) {
      toast.error(getErrorMessage(error), { duration: 7000 });
      if (phase === 'commit') { reset(); onDone(); }
    } finally { setBusy(''); }
  }
  return <Modal open onClose={() => { if (!busy) onClose(); }} title="Sınıf Atlatma" size="xl">
    <div className="space-y-5">
      <div className="rounded-lg bg-blue-50 p-4 text-sm space-y-2">
        <p><strong>Kural:</strong> Ad + soyad + öğrenci numarası eşleşiyorsa yalnızca sınıf bilgileri güncellenir. Öğrenci hesabı, şifresi, üzerindeki kitaplar ve rezervasyon geçmişi korunur.</p>
        <p>Yeni öğrenciler eklenir. Seçilen kapsamda olup yeni listede bulunmayan öğrenciler, eski 8. ve 12. sınıflar dahil, Excel yedeğinden ve onayınızdan sonra silinir.</p>
      </div>
      <label className="block text-sm font-medium">İşlem kapsamı
        <select className="mt-2 w-full border rounded-md p-2" value={scope} disabled={!!busy} onChange={e => { setScope(e.target.value); reset(); }}>
          <option value="">Kapsam seçin</option>
          <option value="all">Okulun tamamı</option>
          <option value="ilkokul">Yalnızca ilkokul</option>
          <option value="ortaokul">Yalnızca ortaokul</option>
          <option value="lise">Yalnızca lise</option>
          <option value="hazırlık">Yalnızca hazırlık</option>
        </select>
      </label>
      <p className="text-sm text-red-700">Seçtiğiniz kapsamın yeni döneme ait TÜM sınıf dosyalarını birlikte yükleyin. Eksik sınıf dosyası, o sınıftaki öğrencilerin silme listesine girmesine neden olur. Kademe geçişleri için okulun tamamını seçin.</p>
      <label className="block text-sm font-medium">Excel dosyaları (.xls / .xlsx)
        <input type="file" multiple accept=".xls,.xlsx" disabled={!!busy} className="block mt-2 w-full text-sm" onChange={e => { setFiles(Array.from(e.target.files || [])); reset(); }} />
      </label>
      <p className="text-xs text-muted-foreground">Mevcut Excel Yükle formatı: sınıf başlığı, Öğrenci No, Adı, Soyadı. {files.length} dosya seçili.</p>
      <Button disabled={!scope || !files.length || !!busy} loading={busy === 'preview'} onClick={() => run('preview')}>Listeyi Kontrol Et</Button>
      {preview && <div className="space-y-4 border-t pt-4">
        <div className="flex flex-wrap gap-4 text-sm font-medium">
          <span>Korunacak / güncellenecek: {preview.summary.updated}</span>
          <span>Eklenecek: {preview.summary.added}</span>
          <span className="text-red-700">Silinecek: {preview.summary.removed}</span>
        </div>
        <details><summary className="cursor-pointer text-sm font-medium">Sınıf değişikliklerini incele</summary>
          <div className="max-h-48 overflow-auto mt-2 text-sm">{preview.changes.map((s, i) => <p key={i}>{s.student_number} · {s.full_name} · {s.old_class} → {s.new_class}</p>)}</div>
        </details>
        <details open={preview.summary.removed > 0}><summary className="cursor-pointer text-sm font-medium text-red-700">Silinecek öğrencileri incele</summary>
          <div className="max-h-48 overflow-auto mt-2 text-sm">{preview.removed.map(s => <p key={s.student_id}>{s.student_number} · {s.full_name} · {s.class_name} · {s.reason}</p>)}</div>
        </details>
        {preview.summary.activeReservations > 0 && <p role="alert" className="text-sm text-red-700">Silinecek öğrencilerde aktif ödünç veya rezervasyon var. Önce bu işlemleri tamamlayın, sonra listeyi tekrar kontrol edin. Şu anda onay verilemez; Excel listesini indirebilirsiniz.</p>}
        <Button variant="outline" disabled={!!busy} loading={busy === 'report'} onClick={() => run('report')}>1. Silinecek Öğrencileri Excel İndir</Button>
        <label className="flex gap-2 text-sm items-start"><input type="checkbox" checked={confirmed} disabled={!reportToken || !!busy} onChange={e => setConfirmed(e.target.checked)} /><span>Excel yedeğini kaydettim. Yüklediğim dosyalar seçtiğim kapsamın tamamını içeriyor. Yukarıdaki silme listesini ve sınıf değişikliklerini onaylıyorum.</span></label>
        <div className="flex justify-end gap-2">
          <Button variant="outline" disabled={!!busy} onClick={onClose}>Vazgeç</Button>
          <Button disabled={!reportToken || !confirmed || !!busy || preview.summary.activeReservations > 0} loading={busy === 'commit'} onClick={() => run('commit')}>2. Onayla ve Uygula</Button>
        </div>
      </div>}
    </div>
  </Modal>;
}
