import { NextRequest, NextResponse } from "next/server";
import { db } from "@/db";
import { building } from "@/db/schema";
import { completePairing } from "@/lib/pairing";

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { partA, partB, appName } = body;

    if (!partA || !partB || !appName) {
      return NextResponse.json(
        { error: "Missing required fields: partA, partB, appName" },
        { status: 400 }
      );
    }

    const result = await completePairing({ partA, partB, appName });

    if (!result.success) {
      return NextResponse.json({ error: result.error }, { status: 400 });
    }

    // Return building info
    const [buildingInfo] = await db.select().from(building).limit(1);

    return NextResponse.json({
      success: true,
      buildingId: buildingInfo?.id || null,
      buildingName: buildingInfo?.name || null,
      buildingAddress: buildingInfo?.address || null,
      keyPrefix: result.keyPrefix,
    });
  } catch {
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
