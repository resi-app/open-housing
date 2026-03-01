"use client";

import { useState, useEffect } from "react";
import { useTranslations } from "next-intl";
import QRCode from "qrcode";

interface FlatOption {
  id: string;
  flatNumber: string;
  entranceName: string | null;
}

interface InvitationModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export default function InvitationModal({
  isOpen,
  onClose,
}: InvitationModalProps) {
  const t = useTranslations("Invitations");
  const tCommon = useTranslations("Common");
  const [flats, setFlats] = useState<FlatOption[]>([]);
  const [role, setRole] = useState("owner");
  const [flatId, setFlatId] = useState("");
  const [expiresInDays, setExpiresInDays] = useState(7);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const [generatedUrl, setGeneratedUrl] = useState("");
  const [qrDataUrl, setQrDataUrl] = useState("");
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (isOpen) {
      fetch("/api/flats")
        .then((r) => r.json())
        .then((data) => setFlats(data))
        .catch(() => setFlats([]));

      // Reset state when opening
      setGeneratedUrl("");
      setQrDataUrl("");
      setError("");
      setCopied(false);
      setRole("owner");
      setFlatId("");
      setExpiresInDays(7);
    }
  }, [isOpen]);

  if (!isOpen) return null;

  async function handleGenerate(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError("");

    const res = await fetch("/api/invitations", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        role,
        flatId: flatId || null,
        expiresInDays,
      }),
    });

    if (!res.ok) {
      const data = await res.json();
      setError(data.error || t("error"));
      setLoading(false);
      return;
    }

    const data = await res.json();
    setGeneratedUrl(data.url);

    const qr = await QRCode.toDataURL(data.url, {
      width: 256,
      margin: 2,
    });
    setQrDataUrl(qr);

    setLoading(false);
  }

  async function handleCopy() {
    await navigator.clipboard.writeText(generatedUrl);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl w-full max-w-md p-6 max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-xl font-bold text-gray-900">{t("title")}</h2>
          <button
            onClick={onClose}
            className="text-gray-500 hover:text-gray-700 text-2xl leading-none"
          >
            &times;
          </button>
        </div>

        {error && (
          <div className="bg-red-50 text-red-700 px-4 py-3 rounded-lg text-base mb-4">
            {error}
          </div>
        )}

        {!generatedUrl ? (
          <form onSubmit={handleGenerate} className="space-y-4">
            <div>
              <label className="block text-base font-medium text-gray-700 mb-1">
                {t("roleLabel")}
              </label>
              <select
                value={role}
                onChange={(e) => setRole(e.target.value)}
                className="w-full px-4 py-3 text-base border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
              >
                <option value="owner">{t("roleOwner")}</option>
                <option value="tenant">{t("roleTenant")}</option>
              </select>
            </div>

            <div>
              <label className="block text-base font-medium text-gray-700 mb-1">
                {t("flatLabel")}
              </label>
              <select
                value={flatId}
                onChange={(e) => setFlatId(e.target.value)}
                className="w-full px-4 py-3 text-base border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
              >
                <option value="">{t("noFlat")}</option>
                {flats.map((f) => (
                  <option key={f.id} value={f.id}>
                    {f.flatNumber}
                    {f.entranceName ? ` (${f.entranceName})` : ""}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-base font-medium text-gray-700 mb-1">
                {t("expiryLabel")}
              </label>
              <select
                value={expiresInDays}
                onChange={(e) => setExpiresInDays(Number(e.target.value))}
                className="w-full px-4 py-3 text-base border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
              >
                <option value={7}>{t("days7")}</option>
                <option value={14}>{t("days14")}</option>
                <option value={30}>{t("days30")}</option>
              </select>
            </div>

            <div className="flex gap-3 pt-2">
              <button
                type="button"
                onClick={onClose}
                className="flex-1 py-3 px-4 text-base font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors"
              >
                {tCommon("cancel")}
              </button>
              <button
                type="submit"
                disabled={loading}
                className="flex-1 py-3 px-4 text-base font-medium text-white bg-blue-600 hover:bg-blue-700 disabled:bg-blue-400 rounded-lg transition-colors"
              >
                {loading ? t("generating") : t("generate")}
              </button>
            </div>
          </form>
        ) : (
          <div className="space-y-4">
            <p className="text-base font-medium text-green-700 bg-green-50 px-4 py-3 rounded-lg">
              {t("linkReady")}
            </p>

            <div className="bg-gray-50 border border-gray-200 rounded-lg p-3">
              <p className="text-sm text-gray-600 break-all">{generatedUrl}</p>
            </div>

            <button
              onClick={handleCopy}
              className="w-full py-3 px-4 text-base font-medium text-white bg-blue-600 hover:bg-blue-700 rounded-lg transition-colors"
            >
              {copied ? t("copied") : t("copyLink")}
            </button>

            {qrDataUrl && (
              <div className="text-center">
                <p className="text-base font-medium text-gray-700 mb-2">
                  {t("qrCode")}
                </p>
                <img
                  src={qrDataUrl}
                  alt="QR Code"
                  className="mx-auto rounded-lg border border-gray-200"
                  width={256}
                  height={256}
                />
              </div>
            )}

            <button
              onClick={onClose}
              className="w-full py-3 px-4 text-base font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors"
            >
              {t("close")}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
