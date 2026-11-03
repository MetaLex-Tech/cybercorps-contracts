// WebCrypto, so the browser (the user device) and the server run the same code.

const subtle = () => globalThis.crypto.subtle;
// WebCrypto takes buffers backed by an ArrayBuffer. These bytes are.
const source = (bytes: Uint8Array) => bytes as Uint8Array<ArrayBuffer>;
const utf8 = new TextEncoder();

export async function sha256(data: Uint8Array | string): Promise<Uint8Array> {
  const bytes = typeof data === 'string' ? utf8.encode(data) : data;
  return new Uint8Array(await subtle().digest('SHA-256', source(bytes)));
}

// HKDF-SHA256 with an empty HKDF salt. The input key material is random, so it needs no salt.
export async function hkdf(ikm: Uint8Array, label: string): Promise<Uint8Array> {
  const key = await subtle().importKey('raw', source(ikm), 'HKDF', false, ['deriveBits']);
  const bits = await subtle().deriveBits(
    { name: 'HKDF', hash: 'SHA-256', salt: new Uint8Array(0), info: utf8.encode(label) },
    key,
    256,
  );
  return new Uint8Array(bits);
}

// AES-256-GCM. The blob is the 12-byte IV, then the ciphertext with its tag.
export async function encrypt(key: Uint8Array, plaintext: string): Promise<Uint8Array> {
  const iv = globalThis.crypto.getRandomValues(new Uint8Array(12));
  const aes = await subtle().importKey('raw', source(key), 'AES-GCM', false, ['encrypt']);
  const body = new Uint8Array(await subtle().encrypt({ name: 'AES-GCM', iv }, aes, utf8.encode(plaintext)));
  const blob = new Uint8Array(12 + body.length);
  blob.set(iv);
  blob.set(body, 12);
  return blob;
}

export async function decrypt(key: Uint8Array, blob: Uint8Array): Promise<string> {
  const aes = await subtle().importKey('raw', source(key), 'AES-GCM', false, ['decrypt']);
  const plain = await subtle().decrypt({ name: 'AES-GCM', iv: source(blob.subarray(0, 12)) }, aes, source(blob.subarray(12)));
  return new TextDecoder().decode(plain);
}

export const toHex = (bytes: Uint8Array) => Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');

export const fromHex = (hex: string) => Uint8Array.from(hex.match(/../g) ?? [], b => parseInt(b, 16));

export function toBase64Url(text: string): string {
  const bytes = utf8.encode(text);
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function fromBase64Url(encoded: string): string {
  const binary = atob(encoded.replace(/-/g, '+').replace(/_/g, '/'));
  return new TextDecoder().decode(Uint8Array.from(binary, c => c.charCodeAt(0)));
}
