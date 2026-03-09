import "dotenv/config";
import { drizzle } from "drizzle-orm/node-postgres";
import { Pool } from "pg";
import bcrypt from "bcrypt";
import crypto from "crypto";
import { eq } from "drizzle-orm";
import { users } from "../db/schema";

function parseArgs(): { email: string; name: string } {
  const args = process.argv.slice(2);
  let email = "";
  let name = "";

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--email" && args[i + 1]) {
      email = args[++i];
    } else if (args[i] === "--name" && args[i + 1]) {
      name = args[++i];
    }
  }

  if (!email || !name) {
    console.error("Usage: npm run create-admin -- --email admin@example.com --name \"Admin Name\"");
    process.exit(1);
  }

  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(email)) {
    console.error("Error: Invalid email format.");
    process.exit(1);
  }

  return { email, name };
}

async function main() {
  const { email, name } = parseArgs();

  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
  });
  const db = drizzle(pool);

  // Check for duplicate email
  const existing = await db
    .select({ id: users.id })
    .from(users)
    .where(eq(users.email, email))
    .limit(1);

  if (existing.length > 0) {
    console.error(`Error: User with email "${email}" already exists.`);
    await pool.end();
    process.exit(1);
  }

  // Generate random 16-char password
  const password = crypto.randomBytes(12).toString("base64url").slice(0, 16);
  const passwordHash = await bcrypt.hash(password, 12);

  const [admin] = await db
    .insert(users)
    .values({
      email,
      name,
      passwordHash,
      role: "admin",
    })
    .returning({ id: users.id, email: users.email, name: users.name });

  console.log("\nAdmin user created successfully!");
  console.log("─".repeat(40));
  console.log(`  Name:     ${admin.name}`);
  console.log(`  Email:    ${admin.email}`);
  console.log(`  Password: ${password}`);
  console.log("─".repeat(40));
  console.log("Please change this password after first login.\n");

  await pool.end();
}

main().catch((e) => {
  console.error("Failed to create admin:", e);
  process.exit(1);
});
