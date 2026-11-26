# Deploying ZKPassportEligibilityConditionFactory

This script deploys `ZKPassportEligibilityCondition`, `ZKPassportEligibilityConditionFactory`, and the factory's `ERC1967Proxy` through Foundry's deterministic `CREATE2` deployer.

## Security properties

- **No deployer role:** The factory uses the chain's existing core `BorgAuth` (`0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01`), where the MetaLeX Safe (`0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C`) holds role `200` (`>= OWNER_ROLE`) on Ethereum, Base, and Sepolia.
- **Dev mode restricted to testnets:** `devModeAllowed` is `true` only on Sepolia (`11155111`) and `false` on Ethereum (`1`) and Base (`8453`).
- **Live helper preflight:** The script verifies that `ZKPassportRootVerifier` (`0x1D000001000EFD9a6371f4d90bB8920D5431c0D8`) and its `v0.21.0` `VerifierHelper` (`0x00000015...`, which exposes `getNullifierType`, `isNationalityIn`, and `isAgeAboveOrEqual`) are deployed before broadcasting. Chains without a verifier (Arbitrum, Base Sepolia) refuse cleanly.
- **Same address on Ethereum and Base:** Because the core `BorgAuth`, verifier, domain (`cyberraise.metalex.tech`), validity period (`30 days`), `devModeAllowed` (`false`), and `CREATE2` salts match, the factory deploys to the same address on both chains.

## 1. Simulate (no broadcast)

```bash
forge script script/deploy-zkpassport-eligibility-condition.s.sol --rpc-url sepolia
forge script script/deploy-zkpassport-eligibility-condition.s.sol --rpc-url base
forge script script/deploy-zkpassport-eligibility-condition.s.sol --rpc-url ethereum
```

## 2. Broadcast on Sepolia and test a live mock-passport proof

```bash
forge script script/deploy-zkpassport-eligibility-condition.s.sol \
  --rpc-url sepolia \
  --account <your-signer> \
  --broadcast \
  --verify
```

To deploy the sample Sepolia test condition (`GBR`/`USA`, `18+`, `enforceSanctions = false`) and print its `expectedDomain` and `expectedScope` for a mock-passport proof test from the ZKPassport app:

```bash
forge script script/deploy-zkpassport-eligibility-condition.s.sol \
  --sig "deploySepoliaSampleCondition(address)" <SEPOLIA_FACTORY_PROXY> \
  --rpc-url sepolia \
  --account <your-signer> \
  --broadcast
```

(Optional: set `ZKPASSPORT_DOMAIN=localhost` when deploying on Sepolia if testing locally before staging; the script rejects `ZKPASSPORT_DOMAIN` overrides on production chains.)

## 3. Broadcast on Base and Ethereum

After the Sepolia live mock-passport proof succeeds:

```bash
forge script script/deploy-zkpassport-eligibility-condition.s.sol \
  --rpc-url base \
  --account <your-signer> \
  --broadcast \
  --verify

forge script script/deploy-zkpassport-eligibility-condition.s.sol \
  --rpc-url ethereum \
  --account <your-signer> \
  --broadcast \
  --verify
```
