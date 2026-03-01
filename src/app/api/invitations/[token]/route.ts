import { NextRequest, NextResponse } from "next/server";
import { db } from "@/db";
import { invitations, flats, entrances } from "@/db/schema";
import { eq } from "drizzle-orm";

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ token: string }> }
) {
  const { token } = await params;

  const result = await db
    .select({
      id: invitations.id,
      role: invitations.role,
      status: invitations.status,
      expiresAt: invitations.expiresAt,
      flatNumber: flats.flatNumber,
      entranceName: entrances.name,
    })
    .from(invitations)
    .leftJoin(flats, eq(invitations.flatId, flats.id))
    .leftJoin(entrances, eq(flats.entranceId, entrances.id))
    .where(eq(invitations.token, token))
    .limit(1);

  if (result.length === 0) {
    return NextResponse.json(
      { valid: false, reason: "not_found" },
      { status: 404 }
    );
  }

  const invitation = result[0];

  if (invitation.status === "used") {
    return NextResponse.json(
      { valid: false, reason: "used" },
      { status: 410 }
    );
  }

  if (invitation.status === "expired" || new Date(invitation.expiresAt) < new Date()) {
    return NextResponse.json(
      { valid: false, reason: "expired" },
      { status: 410 }
    );
  }

  return NextResponse.json({
    valid: true,
    role: invitation.role,
    flatNumber: invitation.flatNumber,
    entranceName: invitation.entranceName,
  });
}
