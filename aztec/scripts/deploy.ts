// Deploys and upgrades the MetaLeX contracts on an Aztec network. A run does only the work that is still open, so a
// second run on the same chain state sends no tx. Each step logs what it changed and what it did not change.
//
// Each contract goes through the same steps:
// 1. Deploys it from its original artifact, if the network does not have it. So each network gets the same
//    addresses. See `deployments.ts`.
// 2. Publishes the class of the current build, if the network does not have it.
// 3. Schedules the upgrade to the current build, if the contract runs another class and no upgrade to the current
//    build is scheduled. The new class takes effect after the default upgrade delay.
//
// The contracts, in order:
// - The MetaLeX BorgAuthV2.
// - The registry: the sub-script `deploy-registry.ts`.
// - On a testnet only, a company auth for web app tests: the sub-script `deploy-test-corp-auth.ts`.
//
// Usage:
//   node --env-file=.env.testnet deploy.ts            sends the txs that are needed
//   node --env-file=.env.testnet deploy.ts --dry-run  logs what a run would do and sends no tx
//
// Each step logs one line. 🟢 marks a step that does work, ⚫️ a step that skips. `LOG_LEVEL=warn` hides the info
// logs of the wallet.
//
// `DEPLOY_SALT_LABEL` selects the environment: `MetaLex-v1.1.0` for production, a semver pre-release such as
// `MetaLex-v1.1.0-dev.0` for staging and development. All contracts of the environment use the salt of this
// label. Keep the label of an environment the same: a new label gives a new set of contracts at new
// addresses. An upgrade keeps the label.
//
// The deployer comes from `DEPLOYER_SIGNING_KEY`, `DEPLOYER_SALT` and `DEPLOYER_ACCOUNT_TYPE`. On the local network
// only, the deployer is the first test account when `DEPLOYER_SIGNING_KEY` is not set. Its key is public. The
// deployer is the BorgAuthV2 root. The SponsoredFPC pays each fee.

import {
  addressOf,
  checkRecorded,
  deployAndSync,
  logConfigs,
  metalexAuthItemOf,
  recordDeployment,
  runFromEnv,
} from './deploy-lib.ts';
import { registryItemOf, runWithArgs as runRegistry } from './deploy-registry.ts';
import { runWithArgs as runTestCorpAuth, testCorpAuthItemOf } from './deploy-test-corp-auth.ts';

async function main() {
  const run = await runFromEnv();
  const authItem = await metalexAuthItemOf(run);
  const auth = await addressOf(authItem);

  const subItems = [await registryItemOf(run, auth), ...(run.network.testnet ? [await testCorpAuthItemOf(run)] : [])];
  logConfigs('deploy.ts', run, [authItem, ...subItems], [`test corp auth: ${run.network.testnet ? 'yes' : 'no, not a testnet'}`]);
  checkRecorded(run.deployment, 'root', run.ctx.deployer);
  checkRecorded(run.deployment, 'auth', auth);

  await deployAndSync(run.ctx, [authItem]);
  const registry = await runRegistry(run, auth);
  const testCorpAuth = run.network.testnet ? (await runTestCorpAuth(run)).toString() : undefined;

  recordDeployment(run, {
    root: run.ctx.deployer.toString(),
    auth: auth.toString(),
    registry: registry.toString(),
    ...(testCorpAuth && { testCorpAuth }),
  });
  process.exit(0);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
