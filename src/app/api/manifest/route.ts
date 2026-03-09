import { NextResponse } from "next/server";
import { db } from "@/db";
import { building } from "@/db/schema";

export async function GET() {
  let appName = process.env.APP_NAME || "OpenResiApp";

  try {
    const [result] = await db.select({ name: building.name }).from(building).limit(1);
    if (result?.name) {
      appName = result.name;
    }
  } catch {
    // DB not available — use env fallback
  }

  return NextResponse.json({
    name: appName,
    short_name: appName,
    description: "Residential building management",
    start_url: "/",
    display: "standalone",
    theme_color: "#2563eb",
    background_color: "#f9fafb",
    icons: [
      {
        src: "/icon.svg",
        sizes: "any",
        type: "image/svg+xml",
        purpose: "any",
      },
    ],
  });
}
