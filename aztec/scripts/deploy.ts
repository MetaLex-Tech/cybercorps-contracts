// Deploys and upgrades the MetaLeX contracts on an Aztec network. A run does only the work that is still open, so a
// second run on the same chain state sends no tx. Each step logs what it changed and what it did not change.
//
// 1. Deploys BorgAuthV2 and the registry from their original artifacts, if the network does not have them. So each
//    network gets the same addresses. See `deployments.ts`.
// 2. For each of the two contracts, publishes the class of the current build, if the network does not have it.
// 3. For each of the two contracts, schedules the upgrade to the current build, if the contract runs another class
//    and no upgrade to the current build is scheduled. The new class takes effect after the default upgrade delay.
//
// Usage:
//   node --env-file=.env.testnet deploy.ts            sends the txs that are needed
//   node --env-file=.env.testnet deploy.ts --dry-run  logs what a run would do and sends no tx
//
// Each step logs one line. 🟢 marks a step that does work, ⚫️ a step that skips. `LOG_LEVEL=warn` hides the info
// logs of the wallet.
//
// `DEPLOY_SALT_LABEL` selects the environment: `MetaLex-v1.0.0` for production, a semver pre-release such as
// `MetaLex-v1.0.0-dev.0` for staging and development. All contracts of the environment use the salt of this
// label. Keep the label of an environment the same: a new label gives a new set of contracts at new
// addresses. An upgrade keeps the label.
//
// The deployer comes from `DEPLOYER_SIGNING_KEY`, `DEPLOYER_SALT` and `DEPLOYER_ACCOUNT_TYPE`. On the local network
// only, the deployer is the first test account when `DEPLOYER_SIGNING_KEY` is not set. Its key is public. The
// deployer is the BorgAuthV2 root. The SponsoredFPC pays each fee.

import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { getInitialTestAccountsData } from '@aztec-labs/accounts/testing';
import { type ContractArtifact, loadContractArtifact } from '@aztec-labs/aztec.js/abi';
import { AztecAddress } from '@aztec-labs/aztec.js/addresses';
import { Contract, getContractClassFromArtifact } from '@aztec-labs/aztec.js/contracts';
import { publishContractClass } from '@aztec-labs/aztec.js/deployment';
import { Fr } from '@aztec-labs/aztec.js/fields';
import { type AztecNode, createAztecNodeClient, waitForNode } from '@aztec-labs/aztec.js/node';
import { ProtocolContractAddress } from '@aztec-labs/aztec.js/protocol';
import { poseidon2Hash } from '@aztec-labs/foundation/crypto/poseidon';
import {
  DelayedPublicMutableValues,
  DelayedPublicMutableValuesWithHash,
} from '@aztec-labs/stdlib/delayed-public-mutable';
import type { EmbeddedWallet } from '@aztec-labs/wallets/embedded';
import { createFundedInitializerlessAccounts } from '@aztec-labs/wallets/testing';
import { type Deployment, NETWORKS, ORIGINAL_ARTIFACTS } from './deployments.ts';
import { accountOf, keysFromEnv, nodeClientOptions, sponsoredFpcIn, walletAt } from './poc.ts';

const LOCAL_NETWORK_CHAIN_ID = 31337;
const CURRENT_ARTIFACT_PATHS = {
  auth: '../target/borg_auth_v2_contract-BorgAuthV2.json',
  registry: '../target/agreement_registry_contract-CyberAgreementRegistry.json',
};
const DEPLOYMENTS_FILE = new URL('deployments.ts', import.meta.url);
const NETWORKS_DECLARATION = 'export const NETWORKS: Record<number, Network> = ';

type Fee = Awaited<ReturnType<typeof sponsoredFpcIn>>['fee'];
type Context = { node: AztecNode; wallet: EmbeddedWallet; deployer: AztecAddress; fee: Fee; dryRun: boolean };

// Log markers, the same as the EVM `DeploymentScript`. A step that does work (sends, deploys, writes, or would do so
// in a dry run) logs RUN. A step that skips logs SKIP.
const RUN = '🟢 ';
const SKIP = '⚫️ ';

function logRun(logLabel: string, message: string) {
  console.log(`${RUN}${logLabel} ${message}`);
}

function logSkip(logLabel: string, message: string) {
  console.log(`${SKIP}${logLabel} ${message}`);
}

// Like the EVM scripts, the salt is the hash of a versioned label. The hash is reduced into the field.
function saltOf(label: string): Fr {
  return Fr.fromBufferReduce(createHash('sha256').update(label).digest());
}

function artifactAt(path: string): ContractArtifact {
  return loadContractArtifact(JSON.parse(readFileSync(new URL(path, import.meta.url), 'utf8')));
}

async function classIdOf(artifact: ContractArtifact): Promise<Fr> {
  return (await getContractClassFromArtifact(artifact)).id;
}

// A recorded artifact must give its recorded class id. Otherwise each network would get other addresses.
async function originalArtifact(name: keyof typeof ORIGINAL_ARTIFACTS): Promise<ContractArtifact> {
  const { path, classId } = ORIGINAL_ARTIFACTS[name];
  const artifact = artifactAt(path);
  const actual = await classIdOf(artifact);
  if (!actual.equals(Fr.fromHexString(classId))) {
    throw new Error(`${path} has class id ${actual}, but deployments.ts records ${classId}`);
  }
  return artifact;
}

// The test account key is public, so a shared network must get its deployer from the env.
function checkDeployerKey(chainId: number) {
  if (!process.env.DEPLOYER_SIGNING_KEY && chainId !== LOCAL_NETWORK_CHAIN_ID) {
    throw new Error(
      `DEPLOYER_SIGNING_KEY is not set. Only the local network (${LOCAL_NETWORK_CHAIN_ID}) can use a test account`,
    );
  }
}

async function deployerOf(wallet: EmbeddedWallet) {
  if (process.env.DEPLOYER_SIGNING_KEY) return accountOf(wallet, keysFromEnv('DEPLOYER'));
  const [testAccount] = await getInitialTestAccountsData();
  return (await createFundedInitializerlessAccounts(wallet, [testAccount]))[0];
}

// A recorded value must equal the value that this run computes.
function checkRecorded(deployment: Deployment, field: keyof Deployment, computed: AztecAddress) {
  const recorded = deployment[field];
  if (recorded !== undefined && !AztecAddress.fromStringUnsafe(recorded).equals(computed)) {
    throw new Error(`deployments.ts records ${field}=${recorded}, but this run computes ${computed}`);
  }
}

// Writes a value in the code style of `deployments.ts`.
function tsOf(value: unknown, indent: string): string {
  if (typeof value === 'string') return `'${value}'`;
  const inner = `${indent}  `;
  const keyOf = (key: string) => (/^[A-Za-z_$][\w$]*$|^\d+$/.test(key) ? key : `'${key}'`);
  const entries = Object.entries(value as object).map(([k, v]) => `${inner}${keyOf(k)}: ${tsOf(v, inner)},\n`);
  return entries.length === 0 ? '{}' : `{\n${entries.join('')}${indent}}`;
}

// Writes the deployment of `label` into `deployments.ts`, if its record differs. A dry run does not write.
function recordDeployment(ctx: Context, chainId: number, label: string, deployment: Required<Deployment>) {
  const logLabel = '[record]';
  const key = `NETWORKS[${chainId}].deployments['${label}']`;
  const recorded = NETWORKS[chainId].deployments[label];
  if (recorded && Object.entries(deployment).every(([k, v]) => recorded[k as keyof Deployment] === v)) {
    return logSkip(logLabel, `${key} unchanged, skipping`);
  }
  if (ctx.dryRun) return logRun(logLabel, `would write ${key}`);
  const networks = structuredClone(NETWORKS);
  networks[chainId].deployments[label] = deployment;
  const source = readFileSync(DEPLOYMENTS_FILE, 'utf8');
  const start = source.indexOf(NETWORKS_DECLARATION);
  if (start < 0) throw new Error(`deployments.ts has no line that starts with "${NETWORKS_DECLARATION}"`);
  writeFileSync(DEPLOYMENTS_FILE, `${source.slice(0, start)}${NETWORKS_DECLARATION}${tsOf(networks, '')};\n`);
  logRun(logLabel, `wrote ${key} in deployments.ts`);
}

async function deployIfMissing(ctx: Context, name: string, deploy: ReturnType<typeof Contract.deploy>) {
  const logLabel = '[deploy]';
  const { address } = await deploy.getInstance();
  if (await ctx.node.getContract(address)) return logSkip(logLabel, `${name} already exists, skipping: ${address}`);
  if (ctx.dryRun) return logRun(logLabel, `would deploy new ${name}: ${address}`);
  const { receipt } = await deploy.send({ from: ctx.deployer, fee: ctx.fee });
  logRun(logLabel, `deployed new ${name}: ${address}, tx ${receipt.txHash}`);
}

async function latestTimestamp(node: AztecNode): Promise<bigint> {
  const block = await node.getBlock('latest');
  if (!block) throw new Error('the node has no block');
  return block.header.globalVariables.timestamp;
}

// The class of a contract now, and the class of a scheduled upgrade that has not taken effect yet.
async function classesOf(node: AztecNode, address: AztecAddress, originalClassId: Fr) {
  const { delayedPublicMutableSlot } = await DelayedPublicMutableValuesWithHash.getContractUpdateSlots(address);
  const values = await DelayedPublicMutableValues.readFromTree(delayedPublicMutableSlot, slot =>
    node.getPublicStorageAt('latest', ProtocolContractAddress.ContractInstanceRegistry, slot),
  );
  const now = await latestTimestamp(node);
  const current = values.svc.getCurrentAt(now)[0];
  const scheduled = values.svc.timestampOfChange > now ? values.svc.post[0] : undefined;
  return {
    current: current.isZero() ? originalClassId : current,
    scheduled,
    timestampOfChange: values.svc.timestampOfChange,
  };
}

function timeOf(timestamp: bigint): string {
  return new Date(Number(timestamp) * 1000).toISOString();
}

// An upgradeable contract of the environment. `updateTo` gives the `update_to` call of the contract.
type Upgradeable = {
  name: string;
  deploy: ReturnType<typeof Contract.deploy>;
  originalArtifact: ContractArtifact;
  currentArtifact: ContractArtifact;
  originalClassId: Fr;
  targetClassId: Fr;
  updateTo: (contract: Contract, classId: Fr) => ReturnType<Contract['methods'][string]>;
};

async function upgradeableOf(
  name: string,
  key: keyof typeof ORIGINAL_ARTIFACTS,
  deployOf: (artifact: ContractArtifact) => ReturnType<typeof Contract.deploy>,
  updateTo: Upgradeable['updateTo'],
): Promise<Upgradeable> {
  const original = await originalArtifact(key);
  const currentArtifact = artifactAt(CURRENT_ARTIFACT_PATHS[key]);
  return {
    name,
    deploy: deployOf(original),
    originalArtifact: original,
    currentArtifact,
    originalClassId: await classIdOf(original),
    targetClassId: await classIdOf(currentArtifact),
    updateTo,
  };
}

// `publishedByDeploy`: the deploy of this run publishes the class. This is so when the contract does not exist yet
// and the current build is the original class. Only a dry run needs it, because it does not deploy.
async function publishClassIfMissing(ctx: Context, item: Upgradeable, publishedByDeploy: boolean) {
  const logLabel = '[publish class]';
  const name = `${item.name} class`;
  const classId = item.targetClassId;
  if (await ctx.node.getContractClass(classId)) {
    return logSkip(logLabel, `${name} already published, skipping: ${classId}`);
  }
  if (ctx.dryRun && publishedByDeploy) {
    return logSkip(logLabel, `${name} is published by the ${item.name} deploy, skipping: ${classId}`);
  }
  if (ctx.dryRun) return logRun(logLabel, `would publish ${name}: ${classId}`);
  const publish = await publishContractClass(ctx.wallet, item.currentArtifact);
  const { receipt } = await publish.send({ from: ctx.deployer, fee: ctx.fee });
  logRun(logLabel, `published ${name}: ${classId}, tx ${receipt.txHash}`);
}

async function upgradeIfNeeded(ctx: Context, item: Upgradeable, contract: Contract) {
  const logLabel = '[upgrade]';
  const { name, originalClassId, targetClassId } = item;
  const classes = await classesOf(ctx.node, contract.address, originalClassId);
  if (classes.scheduled?.equals(targetClassId)) {
    const at = timeOf(classes.timestampOfChange);
    return logSkip(logLabel, `${name} upgrade already scheduled, takes effect at ${at}, skipping: ${targetClassId}`);
  }
  if (classes.current.equals(targetClassId) && classes.scheduled === undefined) {
    return logSkip(logLabel, `${name} already runs the current build, skipping: ${targetClassId}`);
  }
  if (ctx.dryRun) return logRun(logLabel, `would schedule ${name} upgrade: ${classes.current} -> ${targetClassId}`);
  const { receipt } = await item.updateTo(contract, targetClassId).send({ from: ctx.deployer, fee: ctx.fee });
  const at = timeOf((await classesOf(ctx.node, contract.address, originalClassId)).timestampOfChange);
  logRun(
    logLabel,
    `scheduled ${name} upgrade: ${classes.current} -> ${targetClassId}, takes effect at ${at}, tx ${receipt.txHash}`,
  );
}

// Publishes the class of the current build and schedules the upgrade to it, if needed. `existed`: the contract
// existed before the deploy step of this run.
async function syncClass(ctx: Context, item: Upgradeable, existed: boolean) {
  const { name, originalClassId, targetClassId } = item;
  await publishClassIfMissing(ctx, item, !existed && targetClassId.equals(originalClassId));

  const instance = await item.deploy.getInstance();
  // The wallet needs the artifact of the class that the contract runs now to send `update_to`.
  await ctx.wallet.registerContractClass(item.currentArtifact);
  await ctx.wallet.registerContract(instance, item.originalArtifact);
  // Only a dry run on a network without the contract gets here with no instance. The deploy of a real run gives the
  // original class, so the dry run compares the current build with it.
  if (await ctx.node.getContract(instance.address)) {
    return upgradeIfNeeded(ctx, item, await Contract.at(instance.address, item.originalArtifact, ctx.wallet));
  }
  if (targetClassId.equals(originalClassId)) {
    return logSkip('[upgrade]', `${name} deploy runs the current build, skipping: ${targetClassId}`);
  }
  logRun('[upgrade]', `would schedule ${name} upgrade: ${originalClassId} -> ${targetClassId}`);
}

async function main() {
  const dryRun = process.argv.includes('--dry-run');
  const nodeUrl = process.env.AZTEC_NODE_URL;
  if (!nodeUrl) throw new Error('AZTEC_NODE_URL is not set');
  const node = createAztecNodeClient(nodeUrl, nodeClientOptions());
  await waitForNode(node);

  const label = process.env.DEPLOY_SALT_LABEL;
  if (!label) throw new Error('DEPLOY_SALT_LABEL is not set');
  const salt = saltOf(label);

  const { l1ChainId, rollupVersion } = await node.getNodeInfo();
  const network = NETWORKS[l1ChainId];
  if (!network) throw new Error(`deployments.ts has no network for L1 chain id ${l1ChainId}`);
  const deployment = network.deployments[label] ?? {};

  checkDeployerKey(l1ChainId);
  const wallet = await walletAt(nodeUrl);
  const deployer = (await deployerOf(wallet)).address;
  const { address: fpc, fee } = await sponsoredFpcIn(wallet);
  const ctx: Context = { node, wallet, deployer, fee, dryRun };

  const authItem = await upgradeableOf(
    'BorgAuthV2',
    'auth',
    artifact => Contract.deploy(wallet, artifact, [deployer], 'constructor', { salt, universalDeploy: true }),
    (contract, classId) => contract.methods.update_to(classId),
  );
  const auth = (await authItem.deploy.getInstance()).address;
  // The registry keeps the auth address in its immutables hash. See `update_to`.
  const immutablesHash = await poseidon2Hash([auth.toField()]);
  const registryItem = await upgradeableOf(
    'CyberAgreementRegistry',
    'registry',
    artifact => Contract.deploy(wallet, artifact, [], undefined, { salt, universalDeploy: true, immutablesHash }),
    (contract, classId) => contract.methods.update_to(auth, classId),
  );
  const registry = (await registryItem.deploy.getInstance()).address;
  const items = [authItem, registryItem];

  console.log('==== deploy.ts Configs ====');
  console.log(`[config] network: ${network.name}, L1 chain id ${l1ChainId}, rollup version ${rollupVersion}`);
  console.log(`[config] node: ${nodeUrl}`);
  console.log(`[config] deployer: ${deployer}`);
  console.log(`[config] fee payer: ${fpc}`);
  console.log(`[config] label: ${label}, salt ${salt}`);
  console.log(`[config] record: ${network.deployments[label] ? 'found' : 'none, a new environment'}`);
  for (const item of items) {
    console.log(`[config] ${item.name} class: original ${item.originalClassId}, current build ${item.targetClassId}`);
  }
  console.log(`[config] dry run: ${dryRun}`);
  console.log('==== deploy.ts Steps ====');

  checkRecorded(deployment, 'root', deployer);
  checkRecorded(deployment, 'auth', auth);
  checkRecorded(deployment, 'registry', registry);

  const addresses = [auth, registry];
  const existed = await Promise.all(addresses.map(async address => (await node.getContract(address)) !== undefined));
  for (const item of items) await deployIfMissing(ctx, item.name, item.deploy);
  for (const [i, item] of items.entries()) await syncClass(ctx, item, existed[i]);

  recordDeployment(ctx, l1ChainId, label, {
    root: deployer.toString(),
    auth: auth.toString(),
    registry: registry.toString(),
  });
  process.exit(0);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
