import { NextRequest } from "next/server";
import bcrypt from "bcrypt";
import { db } from "@/db";
import { externalConnections } from "@/db/schema";
import { eq, and } from "drizzle-orm";
import type { ApiKeyPermission } from "@/types";

export interface ValidatedApiKey {
  id: string;
  name: string;
  type: string;
  permissions: ApiKeyPermission;
}

export async function validateApiKeyFromRequest(
  request: NextRequest
): Promise<ValidatedApiKey | null> {
  const apiKey = request.headers.get("X-API-Key");
  if (!apiKey) return null;

  const prefix = apiKey.substring(0, 8);

  // Look up by prefix
  const connections = await db
    .select()
    .from(externalConnections)
    .where(
      and(
        eq(externalConnections.apiKeyPrefix, prefix),
        eq(externalConnections.isActive, true)
      )
    );

  for (const conn of connections) {
    const isValid = await bcrypt.compare(apiKey, conn.apiKeyHash);
    if (isValid) {
      // Update last used timestamp (fire and forget)
      db.update(externalConnections)
        .set({ lastUsedAt: new Date() })
        .where(eq(externalConnections.id, conn.id))
        .then(() => {})
        .catch(() => {});

      return {
        id: conn.id,
        name: conn.name,
        type: conn.type,
        permissions: conn.permissions as ApiKeyPermission,
      };
    }
  }

  return null;
}
