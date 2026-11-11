// The MetaLeX contracts on each Aztec network. `deploy.ts` reads this file.
//
// Each network is keyed by its L1 chain id. Each network holds one deployment for each environment, keyed by the
// salt label of the environment (`DEPLOY_SALT_LABEL` in the env). One network can hold more than one environment,
// for example `MetaLex-v1.1.0-dev.0` for staging and `MetaLex-v1.1.0` for production.
//
// A missing deployment or address means that the environment does not have the contract yet. `deploy.ts` then
// deploys it and writes the record here. A recorded address must equal the address that `deploy.ts` computes.

export type Deployment = {
  // The deployer account. It is also the BorgAuthV2 root, so it controls the upgrades.
  root?: string;
  auth?: string;
  registry?: string;
  // A company auth for web app tests, on a testnet only. The deployer is its root and an officer, with the web app
  // officers of `deploy-test-corp-auth.ts`.
  testCorpAuth?: string;
};

// The first version of each contract. A contract address depends on the class that the contract was deployed with.
// So a new network deploys these classes, and `deploy.ts` then upgrades each contract to the current build. Never
// change a recorded artifact: each network would get other addresses. The files are copies of the compiler output.
// See `DEPLOYMENT.md`, "New original artifacts".
export const ORIGINAL_ARTIFACTS = {
  auth: {
    path: 'res/BorgAuthV2.v1.1.0.json',
    classId: '0x14f40ac8a99d4ee9c90cdd0bc691d6103338541e7e7b7a79dab38ae1888016b0',
  },
  registry: {
    path: 'res/CyberAgreementRegistry.v1.1.0.json',
    classId: '0x10823aae1e34cfc021cc0759e00760451963a2e7316a78ac1bf5ae7f77bf94c3',
  },
};

export type Network = {
  name: string;
  // `deploy.ts` deploys the test company auth only on a testnet.
  testnet: boolean;
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
    testnet: true,
    deployments: {
      'MetaLex-v1.1.0-dev.0': {
        root: '0x0e900d357d0a7b9de3c0293c6b1a58dccfc1862f31c745ba5d3a5a5aaf4ac1fd',
        auth: '0x10d567185bc5c55985577e807f25165227f01973c0718ab6d16b89b7ada488ae',
        registry: '0x19118ac9c061990b9186e6c829de0f6e4083dfa11fd20859be5636917245fb55',
      },
    },
  },
  11155111: {
    name: 'Aztec testnet',
    testnet: true,
    deployments: {
      'MetaLex-v1.1.0': {
        root: '0x0e39c42dd2d5a1cc8a76173b7294c90a9540bda1cd957017699c1017ad0e0c70',
        auth: '0x2f4658aca296fe4b4fb57c7f2ac2e76c45649f46ffdeb47be053773470e217be',
        registry: '0x0bc3fa71906a299e43c0d7f0f9544d0034c34b6df60d5933bce3bd89febd1339',
        testCorpAuth: '0x111425e53bbbc46550872398b9adf84c025a45867c1673f0d8de00a5bf99bc2a',
      },
    },
  },
};
