import { FormEvent, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Eye, EyeOff } from "lucide-react";
import toast from "react-hot-toast";
import { Button } from "@/components/Button";
import { Input } from "@/components/Input";
import { loginUser } from "@/api/auth";
import { useAuthStore } from "@/store/authStore";
import { useLogoStore } from "@/store/logoStore";
import { getErrorMessage } from "@/api/client";

export function LoginPage() {
  const navigate = useNavigate();
  const login = useAuthStore((s) => s.login);
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  const fetchLogo = useLogoStore((s) => s.fetchLogo);

  const [schoolCode, setSchoolCode] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);

  if (isAuthenticated) {
    navigate("/", { replace: true });
    return null;
  }

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!schoolCode || !email || !password) {
      toast.error("Tüm alanlar zorunludur");
      return;
    }
    setLoading(true);
    try {
      const res = await loginUser({ schoolCode, email, password });
      if (!res.token || !res.data) {
        throw new Error(res.message || "Giriş başarısız");
      }
      login(res.token, res.data.user, res.data.school);

      // Fetch school logo after login
      fetchLogo(res.data.school.school_code || schoolCode);

      toast.success("Hoş geldin!");
      navigate("/", { replace: true });
    } catch (err) {
      toast.error(getErrorMessage(err));
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-gray-50 to-gray-100 p-4">
      <div className="w-full max-w-md">
        <div className="text-center mb-8">
          <img
            src="/logo.png"
            alt="Rafly"
            className="w-20 h-20 mx-auto mb-3 object-contain"
            onError={(e) => {
              (e.target as HTMLImageElement).style.display = "none";
            }}
          />
          <h1 className="text-3xl font-bold tracking-tight text-primary">Rafly</h1>
          <p className="text-xs text-muted-foreground mt-1 uppercase tracking-wider">
            School Library Automation
          </p>
        </div>

        <form
          onSubmit={handleSubmit}
          className="bg-white rounded-xl shadow-sm border p-6 space-y-4"
        >
          <Input
            label="Okul Kodu"
            name="schoolCode"
            placeholder="Örn: 12345"
            value={schoolCode}
            onChange={(e) => setSchoolCode(e.target.value)}
            autoFocus
          />
          <Input
            label="E-posta"
            name="email"
            type="email"
            placeholder="ornek@okul.com"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
          <div className="relative">
            <Input
              label="Şifre"
              name="password"
              type={showPassword ? "text" : "password"}
              placeholder="••••••••"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
            <button
              type="button"
              onClick={() => setShowPassword((v) => !v)}
              className="absolute right-3 top-[34px] text-muted-foreground hover:text-foreground"
              tabIndex={-1}
            >
              {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
            </button>
          </div>

          <Button type="submit" loading={loading} className="w-full" size="lg">
            Giriş Yap
          </Button>
        </form>

        <p className="text-center text-xs text-muted-foreground mt-6">
          Rafly v0.1.0
        </p>
      </div>
    </div>
  );
}
