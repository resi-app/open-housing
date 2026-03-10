import crypto from "crypto";
import bcrypt from "bcrypt";
import { db } from "@/db";
import { pairingRequests, externalConnections } from "@/db/schema";
import { eq, and } from "drizzle-orm";
import type { ApiKeyPermission, ConnectionType } from "@/types";

const PART_A_PREFIX = "orai_";
const EXPIRY_HOURS = 1;
const BCRYPT_ROUNDS = 12;

export function generatePartA(): string {
  return PART_A_PREFIX + crypto.randomBytes(32).toString("hex");
}

export function getTokenPrefix(token: string): string {
  return token.substring(0, 12);
}

export function deriveApiKey(partA: string, partB: string): string {
  return crypto
    .createHmac("sha256", partA)
    .update(partB)
    .digest("hex");
}

export async function createPairingRequest(params: {
  email: string;
  connectionType: ConnectionType;
  permissions: ApiKeyPermission;
  createdById: string;
}): Promise<{ partA: string; pairingId: string }> {
  const partA = generatePartA();
  const partAHash = await bcrypt.hash(partA, BCRYPT_ROUNDS);
  const partAPrefix = getTokenPrefix(partA);
  const expiresAt = new Date(Date.now() + EXPIRY_HOURS * 60 * 60 * 1000);

  const [request] = await db
    .insert(pairingRequests)
    .values({
      email: params.email,
      partAHash,
      partAPrefix,
      connectionType: params.connectionType,
      permissions: params.permissions,
      status: "pending",
      expiresAt,
      createdById: params.createdById,
    })
    .returning({ id: pairingRequests.id });

  return { partA, pairingId: request.id };
}

export async function completePairing(params: {
  partA: string;
  partB: string;
  appName: string;
}): Promise<{
  success: boolean;
  error?: string;
  connectionId?: string;
  keyPrefix?: string;
}> {
  const partAPrefix = getTokenPrefix(params.partA);

  // Find matching pending pairing request by prefix
  const [request] = await db
    .select()
    .from(pairingRequests)
    .where(
      and(
        eq(pairingRequests.partAPrefix, partAPrefix),
        eq(pairingRequests.status, "pending")
      )
    )
    .limit(1);

  if (!request) {
    return { success: false, error: "Párovacia požiadavka nebola nájdená" };
  }

  // Check expiry
  if (new Date() > request.expiresAt) {
    await db
      .update(pairingRequests)
      .set({ status: "expired" })
      .where(eq(pairingRequests.id, request.id));
    return { success: false, error: "Párovací kód vypršal" };
  }

  // Verify Part A hash
  const isValid = await bcrypt.compare(params.partA, request.partAHash);
  if (!isValid) {
    return { success: false, error: "Neplatný párovací kód" };
  }

  // Derive API key from both parts
  const apiKey = deriveApiKey(params.partA, params.partB);
  const apiKeyHash = await bcrypt.hash(apiKey, BCRYPT_ROUNDS);
  const apiKeyPrefix = apiKey.substring(0, 8);

  // Create external connection
  const [connection] = await db
    .insert(externalConnections)
    .values({
      name: params.appName,
      type: request.connectionType,
      apiKeyHash,
      apiKeyPrefix,
      permissions: request.permissions,
      isActive: true,
      pairedAt: new Date(),
    })
    .returning({ id: externalConnections.id });

  // Mark pairing request as completed
  await db
    .update(pairingRequests)
    .set({
      status: "completed",
      completedAt: new Date(),
      connectionId: connection.id,
    })
    .where(eq(pairingRequests.id, request.id));

  return {
    success: true,
    connectionId: connection.id,
    keyPrefix: apiKeyPrefix,
  };
}
