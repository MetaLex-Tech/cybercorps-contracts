import { integer, jsonb, pgTable, primaryKey, text, timestamp } from 'drizzle-orm/pg-core';
import type { AgreementJson, PublicAccount } from '../../shared/agreement';

// Onboarded users. Each row is public account data plus the name that the user picked for its role.
export const accounts = pgTable('accounts', {
  address: text('address').primaryKey(),
  name: text('name').notNull(),
  account: jsonb('account').$type<PublicAccount>().notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
});

// The document vault: ciphertext blobs (documents and signature evidence), keyed by a locator.
export const vault = pgTable('vault', {
  locator: text('locator').primaryKey(),
  blob: text('blob').notNull(), // base64
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
});

// The signature collector: each agreement without its salt.
export const agreements = pgTable('agreements', {
  id: text('id').primaryKey(),
  agreement: jsonb('agreement').$type<AgreementJson>().notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
});

export const signatures = pgTable(
  'signatures',
  {
    agreementId: text('agreement_id').notNull(),
    signer: text('signer').notNull(),
    authwit: text('authwit').notNull(),
    signedAt: timestamp('signed_at', { withTimezone: true }).notNull().defaultNow(),
  },
  t => [primaryKey({ columns: [t.agreementId, t.signer] })],
);

// The settler's work on one agreement. `settling` until the tx is sent, then `sent` with its hash, or `failed`.
export const settlements = pgTable('settlements', {
  agreementId: text('agreement_id').primaryKey(),
  status: text('status').$type<'settling' | 'sent' | 'failed'>().notNull(),
  txHash: text('tx_hash'),
  error: text('error'),
  attempts: integer('attempts').notNull().default(1),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
});

// The data key store: each salt encrypted with ENCRYPTION_KEY, readable by the parties until `retainUntil`.
export const dataKeys = pgTable('data_keys', {
  agreementId: text('agreement_id').primaryKey(),
  ciphertext: text('ciphertext').notNull(), // base64
  parties: jsonb('parties').$type<string[]>().notNull(),
  retainUntil: timestamp('retain_until', { withTimezone: true }).notNull(),
});
