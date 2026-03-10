"use client";

import { useTranslations } from "next-intl";
import { useState, useEffect, useCallback } from "react";
import type { ApiKeyPermission, ConnectionType } from "@/types";

interface Connection {
  id: string;
  name: string;
  type: string;
  apiKeyPrefix: string;
  permissions: ApiKeyPermission;
  isActive: boolean;
  lastUsedAt: string | null;
  pairedAt: string;
  createdAt: string;
}

interface PendingPairing {
  id: string;
  email: string;
  connectionType: string;
  permissions: ApiKeyPermission;
  status: string;
  expiresAt: string;
  createdAt: string;
}

const CONNECTION_TYPES: { value: ConnectionType; labelKey: string }[] = [
  { value: "druzstvo", labelKey: "typeDruzstvo" },
  { value: "energy", labelKey: "typeEnergy" },
  { value: "housekeeper", labelKey: "typeHousekeeper" },
  { value: "other", labelKey: "typeOther" },
];

const PERMISSIONS: { value: ApiKeyPermission; labelKey: string }[] = [
  { value: "read", labelKey: "permissionRead" },
  { value: "read_write", labelKey: "permissionReadWrite" },
  { value: "full", labelKey: "permissionFull" },
];

export default function ExternalConnectionsTab() {
  const t = useTranslations("Settings");
  const [connections, setConnections] = useState<Connection[]>([]);
  const [pendingPairings, setPendingPairings] = useState<PendingPairing[]>([]);
  const [showModal, setShowModal] = useState(false);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [successMessage, setSuccessMessage] = useState("");

  // Form state
  const [email, setEmail] = useState("");
  const [connectionType, setConnectionType] = useState<ConnectionType>("druzstvo");
  const [permissions, setPermissions] = useState<ApiKeyPermission>("read");

  const fetchData = useCallback(async () => {
    try {
      const res = await fetch("/api/external-connections");
      if (res.ok) {
        const data = await res.json();
        setConnections(data.connections.filter((c: Connection) => c.isActive));
        setPendingPairings(
          data.pendingPairings.filter(
            (p: PendingPairing) => p.status === "pending" && new Date(p.expiresAt) > new Date()
          )
        );
      }
    } catch {
      // silently fail
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    setSuccessMessage("");

    try {
      const res = await fetch("/api/external-connections", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, connectionType, permissions }),
      });

      if (res.ok) {
        const data = await res.json();
        setSuccessMessage(
          t("pairingInitiatedDesc", { email: data.email })
        );
        setShowModal(false);
        setEmail("");
        setConnectionType("druzstvo");
        setPermissions("read");
        fetchData();
      }
    } catch {
      // silently fail
    } finally {
      setSubmitting(false);
    }
  };

  const handleRevoke = async (id: string) => {
    if (!confirm(t("confirmRevoke"))) return;

    try {
      const res = await fetch(`/api/external-connections/${id}`, {
        method: "DELETE",
      });
      if (res.ok) {
        fetchData();
      }
    } catch {
      // silently fail
    }
  };

  const getTypeBadge = (type: string) => {
    const colors: Record<string, string> = {
      druzstvo: "bg-blue-100 text-blue-800",
      energy: "bg-yellow-100 text-yellow-800",
      housekeeper: "bg-green-100 text-green-800",
      other: "bg-gray-100 text-gray-800",
    };
    const typeEntry = CONNECTION_TYPES.find((ct) => ct.value === type);
    const label = typeEntry ? t(typeEntry.labelKey as Parameters<typeof t>[0]) : type;
    return (
      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-sm font-medium ${colors[type] || colors.other}`}>
        {label}
      </span>
    );
  };

  const getPermissionLabel = (perm: ApiKeyPermission) => {
    const entry = PERMISSIONS.find((p) => p.value === perm);
    return entry ? t(entry.labelKey as Parameters<typeof t>[0]) : perm;
  };

  const formatDate = (dateStr: string | null) => {
    if (!dateStr) return t("neverUsed");
    return new Date(dateStr).toLocaleDateString("sk-SK", {
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  };

  if (loading) {
    return <div className="text-center py-8 text-gray-500">...</div>;
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h2 className="text-xl font-semibold text-gray-900">
            {t("connectionsTitle")}
          </h2>
          <p className="text-base text-gray-500 mt-1">
            {t("connectionsDescription")}
          </p>
        </div>
        <button
          onClick={() => setShowModal(true)}
          className="px-5 py-3 bg-blue-600 hover:bg-blue-700 text-white text-base font-medium rounded-lg transition-colors"
        >
          {t("addConnection")}
        </button>
      </div>

      {successMessage && (
        <div className="mb-6 p-4 bg-green-50 border border-green-200 rounded-lg text-green-800 text-base">
          {successMessage}
        </div>
      )}

      {/* Active Connections */}
      {connections.length === 0 && pendingPairings.length === 0 ? (
        <div className="text-center py-12 text-gray-500 text-base">
          {t("noConnections")}
        </div>
      ) : (
        <div className="space-y-4">
          {connections.map((conn) => (
            <div
              key={conn.id}
              className="bg-white rounded-xl border border-gray-200 p-6"
            >
              <div className="flex items-start justify-between">
                <div>
                  <div className="flex items-center gap-3 mb-2">
                    <h3 className="text-base font-semibold text-gray-900">
                      {conn.name}
                    </h3>
                    {getTypeBadge(conn.type)}
                    <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-sm font-medium bg-emerald-100 text-emerald-800">
                      {t("active")}
                    </span>
                  </div>
                  <div className="text-base text-gray-500 space-y-1">
                    <p>
                      {t("permissionLabel")}: {getPermissionLabel(conn.permissions)}
                    </p>
                    <p>
                      {t("connectedSince")}: {formatDate(conn.pairedAt)}
                    </p>
                    <p>
                      {t("lastActivity")}: {formatDate(conn.lastUsedAt)}
                    </p>
                    <p className="text-sm text-gray-400 font-mono">
                      Key: {conn.apiKeyPrefix}...
                    </p>
                  </div>
                </div>
                <button
                  onClick={() => handleRevoke(conn.id)}
                  className="px-4 py-2 text-base text-red-600 hover:text-red-700 hover:bg-red-50 rounded-lg transition-colors"
                >
                  {t("revokeConnection")}
                </button>
              </div>
            </div>
          ))}

          {/* Pending Pairings */}
          {pendingPairings.length > 0 && (
            <>
              <h3 className="text-base font-semibold text-gray-700 mt-6">
                {t("pendingPairings")}
              </h3>
              {pendingPairings.map((pairing) => (
                <div
                  key={pairing.id}
                  className="bg-white rounded-xl border border-yellow-200 p-6"
                >
                  <div className="flex items-start justify-between">
                    <div>
                      <div className="flex items-center gap-3 mb-2">
                        <h3 className="text-base font-semibold text-gray-900">
                          {pairing.email}
                        </h3>
                        {getTypeBadge(pairing.connectionType)}
                        <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-sm font-medium bg-yellow-100 text-yellow-800">
                          {t("pairingPending")}
                        </span>
                      </div>
                      <div className="text-base text-gray-500">
                        <p>
                          {t("permissionLabel")}: {getPermissionLabel(pairing.permissions)}
                        </p>
                        <p>
                          {t("expiresAt")}: {formatDate(pairing.expiresAt)}
                        </p>
                      </div>
                    </div>
                  </div>
                </div>
              ))}
            </>
          )}
        </div>
      )}

      {/* Add Connection Modal */}
      {showModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-white rounded-xl p-6 w-full max-w-md mx-4">
            <h2 className="text-xl font-semibold text-gray-900 mb-4">
              {t("addConnection")}
            </h2>
            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label className="block text-base font-medium text-gray-700 mb-1">
                  {t("connectionType")}
                </label>
                <select
                  value={connectionType}
                  onChange={(e) => setConnectionType(e.target.value as ConnectionType)}
                  className="w-full px-4 py-3 text-base border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                >
                  {CONNECTION_TYPES.map((ct) => (
                    <option key={ct.value} value={ct.value}>
                      {t(ct.labelKey as Parameters<typeof t>[0])}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-base font-medium text-gray-700 mb-1">
                  {t("connectionEmail")}
                </label>
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder={t("connectionEmailPlaceholder")}
                  required
                  className="w-full px-4 py-3 text-base border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                />
              </div>

              <div>
                <label className="block text-base font-medium text-gray-700 mb-1">
                  {t("permissionLabel")}
                </label>
                <select
                  value={permissions}
                  onChange={(e) => setPermissions(e.target.value as ApiKeyPermission)}
                  className="w-full px-4 py-3 text-base border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                >
                  {PERMISSIONS.map((p) => (
                    <option key={p.value} value={p.value}>
                      {t(p.labelKey as Parameters<typeof t>[0])}
                    </option>
                  ))}
                </select>
              </div>

              <div className="flex gap-3 pt-2">
                <button
                  type="button"
                  onClick={() => setShowModal(false)}
                  className="flex-1 px-5 py-3 text-base font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors"
                >
                  {t("cancel")}
                </button>
                <button
                  type="submit"
                  disabled={submitting}
                  className="flex-1 px-5 py-3 bg-blue-600 hover:bg-blue-700 text-white text-base font-medium rounded-lg transition-colors disabled:opacity-50"
                >
                  {submitting ? "..." : t("send")}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
