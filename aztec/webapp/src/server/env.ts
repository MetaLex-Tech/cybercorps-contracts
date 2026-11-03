export function env(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

// A node behind a free RPC plan can refuse large JSON-RPC batches. `AZTEC_NODE_MAX_BATCH_SIZE` caps each batch.
export function nodeClientOptions() {
  const maxBatchSize = process.env.AZTEC_NODE_MAX_BATCH_SIZE;
  return maxBatchSize ? { maxBatchSize: Number(maxBatchSize) } : {};
}
