import { AztecAddress } from '@aztec-labs/aztec.js/addresses';
import type { ContractInstanceWithAddress } from '@aztec-labs/aztec.js/contracts';
import { Fr } from '@aztec-labs/aztec.js/fields';
import { PublicKeys } from '@aztec-labs/stdlib/keys';
import type { PublicAccount } from './agreement';

export function publicAccountOf(
  instance: ContractInstanceWithAddress,
  signingPublicKey: { x: Fr; y: Fr },
): PublicAccount {
  return {
    address: instance.address.toString(),
    signingPublicKey: { x: signingPublicKey.x.toString(), y: signingPublicKey.y.toString() },
    instance: {
      salt: instance.salt.toString(),
      deployer: instance.deployer.toString(),
      originalContractClassId: instance.originalContractClassId.toString(),
      currentContractClassId: instance.currentContractClassId.toString(),
      initializationHash: instance.initializationHash.toString(),
      immutablesHash: instance.immutablesHash.toString(),
      publicKeys: instance.publicKeys.toString(),
    },
  };
}

export function instanceOf(account: PublicAccount): ContractInstanceWithAddress {
  const i = account.instance;
  return {
    version: 2,
    address: AztecAddress.fromStringUnsafe(account.address),
    salt: Fr.fromString(i.salt),
    deployer: AztecAddress.fromStringUnsafe(i.deployer),
    originalContractClassId: Fr.fromString(i.originalContractClassId),
    currentContractClassId: Fr.fromString(i.currentContractClassId),
    initializationHash: Fr.fromString(i.initializationHash),
    immutablesHash: Fr.fromString(i.immutablesHash),
    publicKeys: PublicKeys.fromString(i.publicKeys),
  };
}
