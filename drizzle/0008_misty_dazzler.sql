CREATE TYPE "public"."api_key_permission" AS ENUM('read', 'read_write', 'full');--> statement-breakpoint
CREATE TYPE "public"."pairing_status" AS ENUM('pending', 'completed', 'expired', 'revoked');--> statement-breakpoint
CREATE TABLE "external_connections" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" varchar(255) NOT NULL,
	"type" varchar(50) NOT NULL,
	"api_key_hash" varchar(255) NOT NULL,
	"api_key_prefix" varchar(12) NOT NULL,
	"permissions" "api_key_permission" DEFAULT 'read' NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL,
	"last_used_at" timestamp,
	"paired_at" timestamp DEFAULT now() NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "pairing_requests" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"email" varchar(255) NOT NULL,
	"part_a_hash" varchar(255) NOT NULL,
	"part_a_prefix" varchar(12) NOT NULL,
	"connection_type" varchar(50) NOT NULL,
	"permissions" "api_key_permission" DEFAULT 'read' NOT NULL,
	"status" "pairing_status" DEFAULT 'pending' NOT NULL,
	"expires_at" timestamp NOT NULL,
	"completed_at" timestamp,
	"connection_id" uuid,
	"created_by_id" uuid NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "pairing_requests" ADD CONSTRAINT "pairing_requests_connection_id_external_connections_id_fk" FOREIGN KEY ("connection_id") REFERENCES "public"."external_connections"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pairing_requests" ADD CONSTRAINT "pairing_requests_created_by_id_users_id_fk" FOREIGN KEY ("created_by_id") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;