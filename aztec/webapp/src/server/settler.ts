// The MetaLeX settler. It proves and sends `finalize` with the authwits from the collector. It runs on the server
// only: it holds the settler's signing key.

import { deriveSecretKeyFromSigningKey } from '@aztec-labs/accounts/utils';
import { NO_FROM } from '@aztec-labs/aztec.js/account';
import { AztecAddress } from '@aztec-labs/aztec.js/addresses';
import { AuthWitness } from '@aztec-labs/aztec.js/authorization';
import { getContractInstanceFromInstantiationParams, NO_WAIT } from '@aztec-labs/aztec.js/contracts';
import { SponsoredFeePaymentMethod } from '@aztec-labs/aztec.js/fee';
import { Fq, Fr } from '@aztec-labs/aztec.js/fields';
import { createAztecNodeClient } from '@aztec-labs/aztec.js/node';
import { SchnorrInitializerlessAccountContract } from '@aztec-labs/noir-contracts.js/SchnorrInitializerlessAccount';
import { SponsoredFPCContract } from '@aztec-labs/noir-contracts.js/SponsoredFPC';
import { EmbeddedWallet } from '@aztec-labs/wallets/embedded';
import { CyberAgreementRegistryContract } from '../artifacts/CyberAgreementRegistry';
import { type AgreementJson, agreementFromJson, type PublicAccount } from '../shared/agreement';
import { instanceOf } from '../shared/instance';
import { env, nodeClientOptions } from './env';

async function settlerAccount(wallet: EmbeddedWallet) {
  const signingKey = Fq.fromHexString(env('SETTLER_SIGNING_KEY'));
  const salt = Fr.fromHexString(process.env.SETTLER_SALT ?? '0x0');
  const secret = await deriveSecretKeyFromSigningKey(signingKey);
  return (process.env.SETTLER_ACCOUNT_TYPE ?? 'schnorr') === 'schnorr'
    ? wallet.createSchnorrAccount(secret, salt, signingKey)
    : wallet.createSchnorrInitializerlessAccount(secret, salt, signingKey);
}

// Sends `finalize` and returns its tx hash without waiting for a block. The browser waits for the receipt.
export async function sendFinalize(agreementJson: AgreementJson, authwits: string[], parties: PublicAccount[]) {
  // The prover downloads its reference string to CRS_PATH. On Vercel, only /tmp is writable.
  if (process.env.VERCEL) process.env.CRS_PATH ??= '/tmp/bb-crs';
  const nodeUrl = env('AZTEC_NODE_URL');
  const wallet = await EmbeddedWallet.create(nodeUrl, { ephemeral: true, nodeClientOptions: nodeClientOptions() });
  const settler = await settlerAccount(wallet);

  // The SponsoredFPC has the same address on the local network and on the testnet.
  const fpc = await getContractInstanceFromInstantiationParams(SponsoredFPCContract.artifact, { salt: new Fr(0) });
  await wallet.registerContract(fpc, SponsoredFPCContract.artifact);

  const registryAddress = AztecAddress.fromStringUnsafe(env('REGISTRY_ADDRESS'));
  const registryInstance = await createAztecNodeClient(nodeUrl, nodeClientOptions()).getContract(registryAddress);
  if (!registryInstance) throw new Error(`no contract instance at ${registryAddress}`);
  await wallet.registerContract(registryInstance, CyberAgreementRegistryContract.artifact);
  const registry = CyberAgreementRegistryContract.at(registryAddress, wallet);

  // The settler registers each party account and stores its public key. The account checks the key against its
  // immutables hash. No secret of the party is needed. The party addresses are scopes only so that the settler PXE
  // can read the stored keys.
  const scopes = parties.map(p => AztecAddress.fromStringUnsafe(p.address));
  for (const party of parties) {
    const address = AztecAddress.fromStringUnsafe(party.address);
    await wallet.registerContract(instanceOf(party), SchnorrInitializerlessAccountContract.artifact);
    await SchnorrInitializerlessAccountContract.at(address, wallet)
      .methods.constructor(Fr.fromString(party.signingPublicKey.x), Fr.fromString(party.signingPublicKey.y))
      .simulate({ from: NO_FROM, additionalScopes: [address] });
  }

  const { txHash } = await registry.methods
    .finalize(agreementFromJson(agreementJson))
    .with({ authWitnesses: authwits.map(a => AuthWitness.fromString(a)) })
    .send({
      from: settler.address,
      additionalScopes: scopes,
      fee: { paymentMethod: new SponsoredFeePaymentMethod(fpc.address) },
      wait: NO_WAIT,
    });
  return txHash.toString();
}
