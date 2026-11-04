// The MetaLeX contracts on each Aztec network. `deploy.ts` reads this file.
//
// Each network is keyed by its L1 chain id. Each network holds one deployment for each environment, keyed by the
// salt label of the environment (`DEPLOY_SALT_LABEL` in the env). One network can hold more than one environment,
// for example `MetaLex-v1.0.0-dev.0` for staging and `MetaLex-v1.0.0` for production.
//
// A missing deployment or address means that the environment does not have the contract yet. `deploy.ts` then
// deploys it and writes the record here. A recorded address must equal the address that `deploy.ts` computes.

export type Deployment = {
  // The deployer account. It is also the BorgAuthV2 root, so it controls the upgrades.
  root?: string;
  auth?: string;
  registry?: string;
};

// The first version of each contract. A contract address depends on the class that the contract was deployed with.
// So a new network deploys these classes, and `deploy.ts` then upgrades each contract to the current build. Never
// change a recorded artifact: each network would get other addresses. The files are copies of the compiler output.
// See `DEPLOYMENT.md`, "New original artifacts".
export const ORIGINAL_ARTIFACTS = {
  auth: {
    path: 'res/BorgAuthV2.v1.json',
    classId: '0x017af6dde76ac6d3db0e18ca3e935b41abf09ed5edc04199e6e97a9744d705b2',
  },
  registry: {
    path: 'res/CyberAgreementRegistry.v1.json',
    classId: '0x028c5742c14ca6edb0013d8143cd5c6fdacfc064041900d335ecb69446c3481f',
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
        root: '0x0e900d357d0a7b9de3c0293c6b1a58dccfc1862f31c745ba5d3a5a5aaf4ac1fd',
        auth: '0x168a2c8d7e04ef9768f6ab9fd1d6b408c44fe296a21aabbe5c2159569fad2fe2',
        registry: '0x0d8a32203b80c92b6c44f37a7e7cfcefb641590a6ce9cd80d43142ced6de5218',
      },
    },
  },
  11155111: {
    name: 'Aztec testnet',
    deployments: {
      'MetaLex-v1.0.0': {
        root: '0x0e39c42dd2d5a1cc8a76173b7294c90a9540bda1cd957017699c1017ad0e0c70',
        auth: '0x0970f8e12c8b3ff5dab4bb049b9802b85d313bf70f1cb8fcdef2ddb87eee0a9f',
        registry: '0x14958bb6e18e19e04358b855e4c36805814b28a86a773625fdc645b30c060380',
      },
    },
  },
};
