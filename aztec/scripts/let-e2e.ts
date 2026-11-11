// Runs the certificate lifecycle of one LedgerEntryToken class on a local Aztec network: mint, update details, void,
// unvoid, assign with the holder's endorsement, and a possession transfer by the holder. The officer and the holders
// sign authwits with their Schnorr keys only. The settler PXE proves and sends each officer action. Alice proves and
// sends her own transfer. An auditor PXE checks each version with the utility functions.
//
// Usage: AZTEC_NODE_URL=http://localhost:8090 node let-e2e.ts
//
// The script deploys a company BorgAuthV2 with a separate root and the officer as its one initial member. The class
// itself needs no deploy tx.

import { createHash } from 'node:crypto';
import { getInitialTestAccountsData } from '@aztec-labs/accounts/testing';
import { NO_FROM } from '@aztec-labs/aztec.js/account';
import { AztecAddress } from '@aztec-labs/aztec.js/addresses';
import { AuthWitness, computeAuthWitMessageHash, computeInnerAuthWitHash } from '@aztec-labs/aztec.js/authorization';
import { type ContractInstanceWithAddress, getContractInstanceFromInstantiationParams } from '@aztec-labs/aztec.js/contracts';
import { Fq, Fr } from '@aztec-labs/aztec.js/fields';
import { createAztecNodeClient, waitForNode } from '@aztec-labs/aztec.js/node';
import { poseidon2Hash, poseidon2HashBytes } from '@aztec-labs/foundation/crypto/poseidon';
import { Schnorr } from '@aztec-labs/foundation/crypto/schnorr';
import { SchnorrInitializerlessAccountContract } from '@aztec-labs/noir-contracts.js/SchnorrInitializerlessAccount';
import type { EmbeddedWallet } from '@aztec-labs/wallets/embedded';
import { createFundedInitializerlessAccounts } from '@aztec-labs/wallets/testing';
import { BorgAuthV2Contract } from './artifacts/BorgAuthV2.ts';
import { LedgerEntryTokenContract } from './artifacts/LedgerEntryToken.ts';
import { nodeClientOptions, sponsoredFpcIn, walletAt } from './poc.ts';

type Cert = {
  token_id: Fr;
  holder: AztecAddress;
  units: Fr;
  investment_amount: Fr;
  valuation: Fr;
  issue_date: bigint;
  details_hash: Fr;
  voided: boolean;
};
type Action = 'update_details' | 'void' | 'unvoid' | 'assign';
type Signer = { address: AztecAddress; instance: ContractInstanceWithAddress; signingKey: Fq };

// EVM `SecurityClass.CommonStock` and `SecuritySeries.NA`.
const COMMON_STOCK = 6;
const SERIES_NA = 8;

function check(condition: boolean, label: string) {
  if (!condition) throw new Error(`FAIL: ${label}`);
  console.log(`ok - ${label}`);
}

async function expectFailure(run: () => Promise<unknown>, label: string, message: string) {
  try {
    await run();
  } catch (err) {
    const text = String((err as Error).message ?? err);
    check(text.includes(message), `${label} (${message})`);
    return;
  }
  throw new Error(`FAIL: ${label} did not fail`);
}

// The authwit of a Schnorr account, as the browser makes it: a signature of the message hash, as four limbs.
async function schnorrAuthWit(signingKey: Fq, messageHash: Fr) {
  const signature = await new Schnorr().constructSignature(messageHash, signingKey);
  return new AuthWitness(messageHash, signature.toLimbFields());
}

const domain = (label: string) => poseidon2HashBytes(Buffer.from(label));

// The client copies of the formulas in `cert.nr`.
async function immutablesHashOf(config: { auth: AztecAddress; security_type: number; security_series: number; blinding: Fr }) {
  return poseidon2Hash([
    await domain('metalex.let.config.v1'),
    config.auth,
    new Fr(config.security_type),
    new Fr(config.security_series),
    config.blinding,
  ]);
}

async function versionIdOf(cert: Cert, salt: Fr) {
  return poseidon2Hash([
    await domain('metalex.let.version.v1'),
    cert.token_id,
    cert.holder,
    cert.units,
    cert.investment_amount,
    cert.valuation,
    new Fr(cert.issue_date),
    cert.details_hash,
    new Fr(cert.voided ? 1 : 0),
    salt,
  ]);
}

// The offchain strings of the certificate. The contract sees only their hash.
function detailsHashOf(details: object) {
  return Fr.fromBufferReduce(createHash('sha256').update(JSON.stringify(details)).digest());
}

// A Schnorr initializerless account. Only its signing key is secret.
async function newSigner(wallet: EmbeddedWallet, signingKey: Fq, secret: Fr): Promise<Signer> {
  const account = await wallet.createSchnorrInitializerlessAccount(secret, Fr.random(), signingKey);
  return { address: account.address, instance: account.getInstance(), signingKey };
}

// Another PXE learns the public key of `signer`, so it can check its authwits. No secret of the signer is needed.
async function learnSigner(wallet: EmbeddedWallet, signer: Signer) {
  const publicKey = await new Schnorr().computePublicKey(signer.signingKey);
  await wallet.registerContract(signer.instance, SchnorrInitializerlessAccountContract.artifact);
  await SchnorrInitializerlessAccountContract.at(signer.address, wallet)
    .methods.constructor(publicKey.x, publicKey.y)
    .simulate({ from: NO_FROM, additionalScopes: [signer.address] });
}

// `MAX_INITIAL_MEMBERS` and `OFFICER` in `borg_auth_v2/src/roles.nr`.
function initialMembers(officer: AztecAddress) {
  const empty = { account: AztecAddress.ZERO, roles: 0 };
  return [{ account: officer, roles: 2 }, empty, empty, empty];
}

async function main() {
  const nodeUrl = process.env.AZTEC_NODE_URL ?? 'http://localhost:8080';
  const node = createAztecNodeClient(nodeUrl, nodeClientOptions());
  await waitForNode(node);

  const [officerData, , settlerData] = await getInitialTestAccountsData();
  const officerKeyWallet = await walletAt(nodeUrl);
  const officerAccount = (await createFundedInitializerlessAccounts(officerKeyWallet, [officerData]))[0];
  const officer: Signer = {
    address: officerAccount.address,
    instance: officerAccount.getInstance(),
    signingKey: officerData.signingKey,
  };

  const settlerWallet = await walletAt(nodeUrl);
  const settler = (await createFundedInitializerlessAccounts(settlerWallet, [settlerData]))[0].address;
  const aliceWallet = await walletAt(nodeUrl);
  const alice = await newSigner(aliceWallet, Fq.random(), Fr.random());
  const bobWallet = await walletAt(nodeUrl);
  const bob = await newSigner(bobWallet, Fq.random(), Fr.random());
  const auditorWallet = await walletAt(nodeUrl);
  const { fee } = await sponsoredFpcIn(settlerWallet, aliceWallet, bobWallet);

  for (const signer of [officer, alice, bob]) await learnSigner(settlerWallet, signer);
  await learnSigner(aliceWallet, bob);
  await aliceWallet.registerSender(settler, 'settler');
  await bobWallet.registerSender(alice.address, 'alice');

  // The script does no root action, so the root is a new account with no tx.
  const root = (await newSigner(settlerWallet, Fq.random(), Fr.random())).address;
  const authContract = await BorgAuthV2Contract.deploy(settlerWallet, root, initialMembers(officer.address)).send({
    from: settler,
    fee,
  });
  const auth = authContract.contract.address;
  console.log(`company auth at ${auth}, root ${root}, officer ${officer.address}`);

  // One class: no deploy tx. Each wallet computes the same instance from the config and registers it.
  const config = { auth, security_type: COMMON_STOCK, security_series: SERIES_NA, blinding: Fr.random() };
  const instance = await getContractInstanceFromInstantiationParams(LedgerEntryTokenContract.artifact, {
    salt: Fr.random(),
    deployer: AztecAddress.ZERO,
    immutablesHash: await immutablesHashOf(config),
  });
  for (const wallet of [settlerWallet, aliceWallet, bobWallet, auditorWallet]) {
    await wallet.registerContract(instance, LedgerEntryTokenContract.artifact);
  }
  const token = await LedgerEntryTokenContract.at(instance.address, settlerWallet);
  const aliceToken = await LedgerEntryTokenContract.at(instance.address, aliceWallet);
  const bobToken = await LedgerEntryTokenContract.at(instance.address, bobWallet);
  const auditorToken = await LedgerEntryTokenContract.at(instance.address, auditorWallet);
  console.log(`class at ${token.address}`);

  const { result: immutablesHash } = await token.methods.immutables_hash_of(config).simulate({ from: settler });
  check(new Fr(immutablesHash).equals(instance.immutablesHash), 'client immutables hash matches the contract');
  const { result: classOf } = await token.methods.class_of(config).simulate({ from: settler });
  check(
    Number(classOf[0]) === COMMON_STOCK && Number(classOf[1]) === SERIES_NA,
    'class_of returns the committed type and series',
  );
  await expectFailure(
    () => token.methods.class_of({ ...config, security_type: COMMON_STOCK + 2 }).simulate({ from: settler }),
    'class_of rejects another type',
    'config does not match the immutables hash',
  );

  const chainInfo = await settlerWallet.getChainInfo();
  const sign = async (signer: Signer, innerHash: Fr) =>
    schnorrAuthWit(signer.signingKey, await computeAuthWitMessageHash({ consumer: token.address, innerHash }, chainInfo));

  const mintHashOf = async (cert: Cert, salt: Fr) =>
    computeInnerAuthWitHash([await domain('metalex.let.mint.v1'), await versionIdOf(cert, salt)]);
  const changeHashOf = async (action: Action, old: Cert, oldSalt: Fr, next: Cert, nextSalt: Fr) =>
    computeInnerAuthWitHash([
      await domain(`metalex.let.${action}.v1`),
      await versionIdOf(old, oldSalt),
      await versionIdOf(next, nextSalt),
    ]);
  const endorseHashOf = async (old: Cert, oldSalt: Fr, newHolder: AztecAddress) =>
    computeInnerAuthWitHash([await domain('metalex.let.endorse.v1'), await versionIdOf(old, oldSalt), newHolder]);

  const mint = async (signer: Signer, cert: Cert, salt: Fr) => {
    const authWitness = await sign(signer, await mintHashOf(cert, salt));
    return token.methods
      .mint(config, signer.address, cert, salt)
      .with({ authWitnesses: [authWitness] })
      .send({ from: settler, additionalScopes: [signer.address], fee });
  };
  const change = async (action: Action, old: Cert, oldSalt: Fr, next: Cert, nextSalt: Fr, endorser?: Signer) => {
    const authWitnesses = [await sign(officer, await changeHashOf(action, old, oldSalt, next, nextSalt))];
    if (endorser) authWitnesses.push(await sign(endorser, await endorseHashOf(old, oldSalt, next.holder)));
    return token.methods[action](config, officer.address, old, oldSalt, next, nextSalt)
      .with({ authWitnesses })
      .send({ from: settler, additionalScopes: [officer.address, old.holder], fee });
  };
  const isCurrent = async (cert: Cert, salt: Fr) =>
    (await auditorToken.methods.is_current(cert, salt).simulate({ from: NO_FROM })).result as boolean;
  const possesses = async (tokenOf: typeof aliceToken, owner: AztecAddress, tokenId: Fr) =>
    (await tokenOf.methods.possesses(owner, tokenId).simulate({ from: owner })).result as boolean;

  // 1. Mint. The client hashes match the utility functions. Alice gets the possession note.
  const v1: Cert = {
    token_id: new Fr(1n),
    holder: alice.address,
    units: new Fr(1000n),
    investment_amount: new Fr(50_000n),
    valuation: new Fr(10_000_000n),
    issue_date: 1762732800n,
    details_hash: detailsHashOf({ holderName: 'Alice Corp', officer: 'Jane Doe', title: 'CEO', legal: 'Common' }),
    voided: false,
  };
  const s1 = Fr.random();
  const { result: versionId } = await token.methods.version_id_of(v1, s1).simulate({ from: settler });
  check(new Fr(versionId).equals(await versionIdOf(v1, s1)), 'client version id matches the contract');
  const { result: mintHash } = await token.methods.mint_hash_of(v1, s1).simulate({ from: settler });
  check(new Fr(mintHash).equals(await mintHashOf(v1, s1)), 'client mint hash matches the contract');
  check(!(await isCurrent(v1, s1)), 'auditor sees no version before mint');
  const { receipt } = await mint(officer, v1, s1);
  const effects = (await node.getTxEffect(receipt.txHash))!.data;
  console.log(`mint tx ${receipt.txHash}: ${effects.nullifiers.length} nullifiers, ${effects.noteHashes.length} note hashes`);
  check(await isCurrent(v1, s1), 'auditor sees the minted version as current');
  const { result: minted } = await auditorToken.methods.is_minted(v1.token_id).simulate({ from: NO_FROM });
  check(minted as boolean, 'auditor sees token id 1 as minted');
  check(await possesses(aliceToken, alice.address, v1.token_id), 'alice holds the possession note');
  await expectFailure(() => mint(officer, { ...v1, holder: bob.address }, Fr.random()), 'second mint of token id 1 is rejected', 'nullifier');

  // 2. Update details.
  const v2: Cert = { ...v1, units: new Fr(2000n), details_hash: detailsHashOf({ holderName: 'Alice Corp', legal: 'v2' }) };
  const s2 = Fr.random();
  const { result: updateHash } = await token.methods.update_details_hash_of(v1, s1, v2, s2).simulate({ from: settler });
  check(new Fr(updateHash).equals(await changeHashOf('update_details', v1, s1, v2, s2)), 'client update hash matches the contract');
  await change('update_details', v1, s1, v2, s2);
  check(!(await isCurrent(v1, s1)) && (await isCurrent(v2, s2)), 'update details replaces the current version');
  await expectFailure(
    () => change('update_details', v1, s1, { ...v1, units: new Fr(3000n) }, Fr.random()),
    'update of a superseded version is rejected',
    'nullifier',
  );

  // 3. Void, then unvoid.
  const v3: Cert = { ...v2, voided: true };
  const s3 = Fr.random();
  await change('void', v2, s2, v3, s3);
  check(await isCurrent(v3, s3), 'void records the voided version');
  const v4: Cert = { ...v3, voided: false };
  const s4 = Fr.random();
  await change('unvoid', v3, s3, v4, s4);
  check(!(await isCurrent(v3, s3)) && (await isCurrent(v4, s4)), 'unvoid records the valid version');

  // 4. Assign to Bob. Alice, the legal owner of record, endorses the certificate to Bob.
  const v5: Cert = { ...v4, holder: bob.address, details_hash: detailsHashOf({ holderName: 'Bob LLC' }) };
  const s5 = Fr.random();
  const { result: endorseHash } = await token.methods.endorse_hash_of(v4, s4, bob.address).simulate({ from: settler });
  check(new Fr(endorseHash).equals(await endorseHashOf(v4, s4, bob.address)), 'client endorse hash matches the contract');
  await expectFailure(() => change('assign', v4, s4, v5, s5), 'assign without the endorsement is rejected', 'Unknown auth witness');
  await change('assign', v4, s4, v5, s5, alice);
  check(!(await isCurrent(v4, s4)) && (await isCurrent(v5, s5)), 'assign records the new legal owner');
  check(await possesses(aliceToken, alice.address, v1.token_id), 'assign does not move possession');

  // 5. Alice delivers the certificate to Bob. The register does not change.
  await aliceToken.methods.transfer(alice.address, bob.address, v1.token_id, 0).send({ from: alice.address, fee });
  check(!(await possesses(aliceToken, alice.address, v1.token_id)), 'alice no longer holds the possession note');
  check(await possesses(bobToken, bob.address, v1.token_id), 'bob holds the possession note');
  check(await isCurrent(v5, s5), 'the possession transfer leaves the register unchanged');

  // 6. A signer that is not an officer, and a signature of another key, are rejected.
  const v6: Cert = { ...v1, token_id: new Fr(2n) };
  await expectFailure(() => mint(bob, v6, Fr.random()), 'mint by a non-officer is rejected', 'BorgAuthV2: permission denied');
  const s6 = Fr.random();
  const forged = await schnorrAuthWit(
    settlerData.signingKey,
    await computeAuthWitMessageHash({ consumer: token.address, innerHash: await mintHashOf(v6, s6) }, chainInfo),
  );
  await expectFailure(
    () =>
      token.methods
        .mint(config, officer.address, v6, s6)
        .with({ authWitnesses: [forged] })
        .send({ from: settler, additionalScopes: [officer.address], fee }),
    'mint with an authwit of another key is rejected',
    'Message not authorized by account',
  );

  console.log('let-e2e: all checks pass');
  process.exit(0);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
