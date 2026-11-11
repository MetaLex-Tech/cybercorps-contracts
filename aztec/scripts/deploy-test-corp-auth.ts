// Deploys a company BorgAuthV2 for web app tests: the deployer is its root and an initial officer, with the web app
// officers. So they can issue and change certificates of a LedgerEntryToken class at once, with no role delay. It then
// publishes the current build and schedules the upgrade to it, as `deploy.ts` does for the MetaLeX contracts.
//
// `deploy.ts` runs this sub-script on a testnet. It can also run alone:
//   node --env-file=.env.testnet deploy-test-corp-auth.ts            sends the txs that are needed
//   node --env-file=.env.testnet deploy-test-corp-auth.ts --dry-run  logs what a run would do and sends no tx
//
// The address depends on the deployer and the salt label, so each network gets the same address for the same
// deployer and label.

import { AztecAddress } from '@aztec-labs/aztec.js/addresses';
import {
  addressOf,
  authItemOf,
  checkRecorded,
  deployAndSync,
  logConfigs,
  OFFICER,
  recordDeployment,
  type Run,
  runFromEnv,
} from './deploy-lib.ts';

const NAME = 'test corp BorgAuthV2';

// `TEST_CORP_OFFICERS` in the env: the Aztec accounts that the web app opens for its test wallets, comma separated.
// A change gives the test corp auth a new address, so remove `testCorpAuth` from the records before the next run.
function webappOfficers(): AztecAddress[] {
  const list = process.env.TEST_CORP_OFFICERS ?? '';
  return list
    .split(',')
    .map(a => a.trim())
    .filter(a => a !== '')
    .map(a => AztecAddress.fromStringUnsafe(a));
}

export function testCorpAuthItemOf(run: Run) {
  if (!run.network.testnet) throw new Error(`${run.network.name} is not a testnet. Do not deploy a test corp auth`);
  const officers = [run.ctx.deployer, ...webappOfficers()];
  return authItemOf(
    run,
    NAME,
    officers.map(account => ({ account, roles: OFFICER })),
  );
}

// Runs the steps of the test corp auth and returns its address. The caller writes the record.
export async function runWithArgs(run: Run): Promise<AztecAddress> {
  const item = await testCorpAuthItemOf(run);
  const address = await addressOf(item);
  checkRecorded(run.deployment, 'testCorpAuth', address);
  await deployAndSync(run.ctx, [item]);
  return address;
}

async function main() {
  const run = await runFromEnv();
  logConfigs('deploy-test-corp-auth.ts', run, [await testCorpAuthItemOf(run)]);
  checkRecorded(run.deployment, 'root', run.ctx.deployer);
  const testCorpAuth = await runWithArgs(run);
  recordDeployment(run, { root: run.ctx.deployer.toString(), testCorpAuth: testCorpAuth.toString() });
  process.exit(0);
}

if (import.meta.main) {
  main().catch(err => {
    console.error(err);
    process.exit(1);
  });
}
