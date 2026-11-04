// The MetaLeX contracts on each Aztec network. `deploy.ts` reads this file.
//
// Each network is keyed by its L1 chain id. Each network holds one deployment for each environment, keyed by the
// salt label of the environment (`DEPLOY_SALT_LABEL` in the env). One network can hold more than one environment,
// for example `MetaLex-v1.0.0-dev.0` for staging and `MetaLex-v1.0.0` for production.
//
// A missing deployment or address means that the environment does not have the contract yet. `deploy.ts` then
// deploys it and writes the record here. A recorded address must equal the address that `deploy.ts` computes.

export type Deployment = {
  // The deployer account. It is also the BorgAuth owner, so it controls the registry upgrades.
  owner?: string;
  auth?: string;
  registry?: string;
};

// The first version of each contract. A contract address depends on the class that the contract was deployed with.
// So a new network deploys these classes, and `deploy.ts` then upgrades the registry to the current build. Never
// change a recorded artifact: each network would get other addresses. The files are copies of the compiler output.
// See `DEPLOYMENT.md`, "New original artifacts".
export const ORIGINAL_ARTIFACTS = {
  auth: {
    path: 'res/BorgAuth.v1.json',
    classId: '0x2fd993ee30e63a213a65c788cfbc5a14398377a8faf6aff3309c56b3bf2effa6',
  },
  registry: {
    path: 'res/CyberAgreementRegistry.v1.json',
    classId: '0x2c6195f2af686c98de42be94ea60896e3ad37cf57437b70c343e96adfd920d73',
  },
};

export type Network = {
  name: string;
  deployments: Record<string, Deployment>;
};

// 31337 is `aztec start --local-network`. Its deployer is the first test account. 11155111 is the Aztec testnet on
// Sepolia. To add a network, add its L1 chain id with `deployments: {}`.
//
// `deploy.ts` writes the deployment records. It rewrites the code from the next line to the end of the file. Keep
// `NETWORKS` last, and keep no comments in it.
export const NETWORKS: Record<number, Network> = {
  31337: {
    name: 'local network',
    deployments: {
      'MetaLex-v1.0.0-dev.0': {
        owner: '0x0e900d357d0a7b9de3c0293c6b1a58dccfc1862f31c745ba5d3a5a5aaf4ac1fd',
        auth: '0x1673b63a1117306d0a8869069722dfb82ecc81d113409ad5a31c030c8d43b9d4',
        registry: '0x11a58a84a6e705665a2bfad4872993aac7f95f5e9ed798daef46df6bf34f7f95',
      },
    },
  },
  11155111: {
    name: 'Aztec testnet',
    deployments: {},
  },
};
