import { NextResponse } from "next/server";
import { db } from "@/db";
import { externalConnections } from "@/db/schema";
import { eq } from "drizzle-orm";

export async function GET() {
  const activeConnections = await db
    .select({ id: externalConnections.id })
    .from(externalConnections)
    .where(eq(externalConnections.isActive, true))
    .limit(1);

  return NextResponse.json({
    status: "ok",
    paired: activeConnections.length > 0,
  });
}
