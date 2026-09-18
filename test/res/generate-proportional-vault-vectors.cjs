// Run with Node.js from any directory. BigInt supplies an independent unlimited-precision oracle.
const fs = require('node:fs');
const path = require('node:path');
const max = (1n << 256n) - 1n;
const one = 1n << 255n;
let seed = 7643293n;
function random() {
  seed = (seed * 6364136223846793005n + 1442695040888963407n) & max;
  return seed;
}
const rows = [];
for (let i = 0; i < 64; i++) {
  const amount = random(), current = random() | one, snapshot = random() | one;
  const scale = random() % 300n;
  const expected = (amount * current / snapshot) >> scale;
  if (expected <= max) rows.push([amount, current, snapshot, scale, expected]);
  // Advance the seed through the three reduction inputs from the original reference run.
  random(); random(); random();
}
fs.writeFileSync(path.join(__dirname, 'proportional-vault-vectors.json'),
  '{"vectors":[' + rows.map(row => '[' + row.join(',') + ']').join(',\n') + ']}\n');
