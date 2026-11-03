// Deploys the registry. A universal deploy with a fixed salt gives the same address on every network.
// The deployer is the settler account from the env. The SponsoredFPC pays the fee.
//
// Usage: node --env-file=.env.testnet deploy.ts

import { Fr } from '@aztec-labs/aztec.js/fields';
import { createAztecNodeClient, waitForNode } from '@aztec-labs/aztec.js/node';
import { CyberAgreementRegistryContract } from './artifacts/CyberAgreementRegistry.ts';
import { accountOf, keysFromEnv, nodeClientOptions, sponsoredFpcIn, walletAt } from './poc.ts';

const REGISTRY_SALT = Fr.fromHexString('0x4d6574614c6558'); // "MetaLeX"

async function main() {
  const nodeUrl = process.env.AZTEC_NODE_URL;
  if (!nodeUrl) throw new Error('AZTEC_NODE_URL is not set');
  await waitForNode(createAztecNodeClient(nodeUrl, nodeClientOptions()));

  const wallet = await walletAt(nodeUrl);
  const account = await accountOf(wallet, keysFromEnv('SETTLER'));
  const { address: fpc, fee } = await sponsoredFpcIn(wallet);
  console.log(`Configs: node=${nodeUrl} deployer=${account.address} fpc=${fpc} salt=${REGISTRY_SALT}`);

  const { contract, receipt } = await CyberAgreementRegistryContract.deploy(wallet, {
    salt: REGISTRY_SALT,
    universalDeploy: true,
  }).send({ from: account.address, fee });
  console.log(`Deployed: REGISTRY_ADDRESS=${contract.address} tx=${receipt.txHash}`);
  process.exit(0);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
