// Deploys the CyberAgreementRegistry of the environment from its original artifact. It then publishes the current
// build and schedules the upgrade to it. The MetaLeX auth approves the upgrades.
//
// `deploy.ts` runs this sub-script. It can also run alone:
//   node --env-file=.env.testnet deploy-registry.ts            sends the txs that are needed
//   node --env-file=.env.testnet deploy-registry.ts --dry-run  logs what a run would do and sends no tx
//
// The address depends on the salt label and the MetaLeX auth address.

import type { AztecAddress } from '@aztec-labs/aztec.js/addresses';
import { Contract } from '@aztec-labs/aztec.js/contracts';
import { poseidon2Hash } from '@aztec-labs/foundation/crypto/poseidon';
import {
  addressOf,
  checkRecorded,
  deployAndSync,
  logConfigs,
  metalexAuthItemOf,
  recordDeployment,
  type Run,
  runFromEnv,
  upgradeableOf,
} from './deploy-lib.ts';

export async function registryItemOf(run: Run, auth: AztecAddress) {
  // The registry keeps the auth address in its immutables hash. See `update_to`.
  const immutablesHash = await poseidon2Hash([auth.toField()]);
  return upgradeableOf(
    'CyberAgreementRegistry',
    'registry',
    artifact =>
      Contract.deploy(run.ctx.wallet, artifact, [], undefined, { salt: run.salt, universalDeploy: true, immutablesHash }),
    (contract, classId) => contract.methods.update_to(auth, classId),
  );
}

// Runs the steps of the registry and returns its address. The caller writes the record.
export async function runWithArgs(run: Run, auth: AztecAddress): Promise<AztecAddress> {
  const item = await registryItemOf(run, auth);
  const address = await addressOf(item);
  checkRecorded(run.deployment, 'registry', address);
  await deployAndSync(run.ctx, [item]);
  return address;
}

async function main() {
  const run = await runFromEnv();
  const auth = await addressOf(await metalexAuthItemOf(run));
  logConfigs('deploy-registry.ts', run, [await registryItemOf(run, auth)], [`auth: ${auth}`]);
  checkRecorded(run.deployment, 'auth', auth);
  const registry = await runWithArgs(run, auth);
  recordDeployment(run, { registry: registry.toString() });
  process.exit(0);
}

if (import.meta.main) {
  main().catch(err => {
    console.error(err);
    process.exit(1);
  });
}
