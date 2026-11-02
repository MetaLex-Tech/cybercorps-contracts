// Deploys the registry. A universal deploy with a fixed salt gives the same address on every network.
// The deployer account pays the fee with its own fee juice.
//
// Usage: AZTEC_NODE_URL=... DEPLOYER_SECRET_KEY=... DEPLOYER_SIGNING_KEY=... DEPLOYER_SALT=... node deploy.ts

import { Fq, Fr } from '@aztec-labs/aztec.js/fields';
import { createAztecNodeClient, waitForNode } from '@aztec-labs/aztec.js/node';
import { EmbeddedWallet } from '@aztec-labs/wallets/embedded';
import { CyberAgreementRegistryContract } from './artifacts/CyberAgreementRegistry.ts';

const REGISTRY_SALT = Fr.fromHexString('0x4d6574614c6558'); // "MetaLeX"

function env(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

async function main() {
  const nodeUrl = env('AZTEC_NODE_URL');
  await waitForNode(createAztecNodeClient(nodeUrl));

  const wallet = await EmbeddedWallet.create(nodeUrl, { ephemeral: true });
  const account = await wallet.createSchnorrInitializerlessAccount(
    Fr.fromHexString(env('DEPLOYER_SECRET_KEY')),
    Fr.fromHexString(env('DEPLOYER_SALT')),
    Fq.fromHexString(env('DEPLOYER_SIGNING_KEY')),
  );
  console.log(`Configs: node=${nodeUrl} deployer=${account.address} salt=${REGISTRY_SALT}`);

  const { contract, receipt } = await CyberAgreementRegistryContract.deploy(wallet, {
    salt: REGISTRY_SALT,
    universalDeploy: true,
  }).send({ from: account.address });
  console.log(`Deployed: CyberAgreementRegistry=${contract.address} tx=${receipt.txHash}`);
  process.exit(0);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
