CREATE TABLE "accounts" (
	"address" text PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"account" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "agreements" (
	"id" text PRIMARY KEY NOT NULL,
	"agreement" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "data_keys" (
	"agreement_id" text PRIMARY KEY NOT NULL,
	"ciphertext" text NOT NULL,
	"parties" jsonb NOT NULL,
	"retain_until" timestamp with time zone NOT NULL
);
--> statement-breakpoint
CREATE TABLE "settlements" (
	"agreement_id" text PRIMARY KEY NOT NULL,
	"status" text NOT NULL,
	"tx_hash" text,
	"error" text,
	"attempts" integer DEFAULT 1 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "signatures" (
	"agreement_id" text NOT NULL,
	"signer" text NOT NULL,
	"authwit" text NOT NULL,
	"signed_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "signatures_agreement_id_signer_pk" PRIMARY KEY("agreement_id","signer")
);
--> statement-breakpoint
CREATE TABLE "vault" (
	"locator" text PRIMARY KEY NOT NULL,
	"blob" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
