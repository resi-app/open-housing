import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { db } from "@/db";
import { externalConnections, pairingRequests } from "@/db/schema";
import { eq } from "drizzle-orm";
import { hasPermission } from "@/lib/permissions";
import type { UserRole, ApiKeyPermission } from "@/types";

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!session) {
    return NextResponse.json({ error: "Neautorizovaný prístup" }, { status: 401 });
  }

  const role = (session.user?.role || "owner") as UserRole;
  if (!hasPermission(role, "manageApiKeys")) {
    return NextResponse.json({ error: "Nedostatočné oprávnenia" }, { status: 403 });
  }

  const { id } = await params;
  const body = await request.json();
  const { name, permissions } = body;

  const [existing] = await db
    .select()
    .from(externalConnections)
    .where(eq(externalConnections.id, id))
    .limit(1);

  if (!existing) {
    return NextResponse.json({ error: "Prepojenie nenájdené" }, { status: 404 });
  }

  const updateData: Record<string, unknown> = {};
  if (name !== undefined) updateData.name = name;
  if (permissions !== undefined) {
    const validPermissions: ApiKeyPermission[] = ["read", "read_write", "full"];
    if (!validPermissions.includes(permissions)) {
      return NextResponse.json({ error: "Neplatné oprávnenie" }, { status: 400 });
    }
    updateData.permissions = permissions;
  }

  if (Object.keys(updateData).length > 0) {
    await db
      .update(externalConnections)
      .set(updateData)
      .where(eq(externalConnections.id, id));
  }

  const [updated] = await db
    .select()
    .from(externalConnections)
    .where(eq(externalConnections.id, id));

  return NextResponse.json(updated);
}

export async function DELETE(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!session) {
    return NextResponse.json({ error: "Neautorizovaný prístup" }, { status: 401 });
  }

  const role = (session.user?.role || "owner") as UserRole;
  if (!hasPermission(role, "manageApiKeys")) {
    return NextResponse.json({ error: "Nedostatočné oprávnenia" }, { status: 403 });
  }

  const { id } = await params;

  const [existing] = await db
    .select()
    .from(externalConnections)
    .where(eq(externalConnections.id, id))
    .limit(1);

  if (!existing) {
    return NextResponse.json({ error: "Prepojenie nenájdené" }, { status: 404 });
  }

  // Deactivate the connection (soft delete)
  await db
    .update(externalConnections)
    .set({ isActive: false })
    .where(eq(externalConnections.id, id));

  // Also revoke any pending pairing requests linked to this connection
  await db
    .update(pairingRequests)
    .set({ status: "revoked" })
    .where(eq(pairingRequests.connectionId, id));

  return NextResponse.json({ success: true });
}
