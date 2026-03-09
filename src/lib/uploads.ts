import path from "path";

/**
 * Returns the base uploads directory.
 * Set UPLOADS_PATH in .env to use a custom path (e.g. /mnt/storage/uploads).
 * Falls back to ./uploads relative to project root.
 */
export function getUploadsDir(): string {
  return process.env.UPLOADS_PATH || path.join(process.cwd(), "uploads");
}
