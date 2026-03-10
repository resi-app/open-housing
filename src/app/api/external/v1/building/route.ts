import { NextRequest, NextResponse } from "next/server";
import { db } from "@/db";
import { building, entrances, flats } from "@/db/schema";
import { eq, count } from "drizzle-orm";
import { withExternalAuth } from "@/lib/external-auth";

async function handler(_request: NextRequest) {
  const [buildingInfo] = await db.select().from(building).limit(1);

  if (!buildingInfo) {
    return NextResponse.json({ error: "Building not found" }, { status: 404 });
  }

  // Get entrance and flat counts
  const entranceList = await db
    .select({ id: entrances.id, name: entrances.name })
    .from(entrances)
    .where(eq(entrances.buildingId, buildingInfo.id));

  const [flatCount] = await db
    .select({ count: count() })
    .from(flats);

  return NextResponse.json({
    id: buildingInfo.id,
    name: buildingInfo.name,
    address: buildingInfo.address,
    ico: buildingInfo.ico,
    votingMethod: buildingInfo.votingMethod,
    entranceCount: entranceList.length,
    flatCount: flatCount.count,
    createdAt: buildingInfo.createdAt,
  });
}

export const GET = withExternalAuth(handler, "read");
