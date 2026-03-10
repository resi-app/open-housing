import { NextRequest, NextResponse } from "next/server";
import { db } from "@/db";
import { flats, entrances } from "@/db/schema";
import { eq } from "drizzle-orm";
import { withExternalAuth } from "@/lib/external-auth";

async function handler(_request: NextRequest) {
  const allFlats = await db
    .select({
      id: flats.id,
      flatNumber: flats.flatNumber,
      floor: flats.floor,
      shareNumerator: flats.shareNumerator,
      shareDenominator: flats.shareDenominator,
      area: flats.area,
      entranceId: flats.entranceId,
      entranceName: entrances.name,
      createdAt: flats.createdAt,
    })
    .from(flats)
    .leftJoin(entrances, eq(flats.entranceId, entrances.id));

  return NextResponse.json(allFlats);
}

export const GET = withExternalAuth(handler, "read");
