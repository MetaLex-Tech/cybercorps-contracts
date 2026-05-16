# Calling the protocol from the app

This page is the web-app-specific companion to the protocol how-to
[Integrate from a frontend](../how-to/integrate-from-frontend.md). It
describes how `metalex-webapp` itself talks to the contracts.

## The pieces

| Piece | Package / library |
|---|---|
| Contract ABIs | `packages/abis` |
| Chain config and addresses | `packages/config` |
| viem clients / transports | `packages/evmClients` |
| React contract hooks | [wagmi](https://wagmi.sh/) + [viem](https://viem.sh/) |
| Wallet connection | injected wallets (MetaMask, Rabby) + WalletConnect |
| Safe multisig | the `multisig` feature module + Safe SDK |

RPC access uses `NEXT_PUBLIC_ALCHEMY_RPC_KEY`; WalletConnect uses
`NEXT_PUBLIC_WALLETCONNECT_APP_ID`.

## Reading contract state

Use the ABIs from `packages/abis` with wagmi's read hooks:

```ts
import { useReadContract } from "wagmi";
import { cyberCorpAbi } from "@metalex-web/abis";

const { data: legalName } = useReadContract({
  abi: cyberCorpAbi,
  address: cyberCorpAddress,
  functionName: "legalName",
});
```

For list/aggregate reads (a full cap table, all rounds), prefer the
[`cybercorps-indexer`](apps/cybercorps-indexer.md) over many on-chain reads.

## Writing / transactions

Writes go through wagmi's `useWriteContract`. The `transactions` feature
module in `cybercorps-web` wraps this with status tracking and toasts; reuse
it rather than calling `useWriteContract` raw.

## EIP-712 signatures

cyberRAISE Expressions of Interest, deal counter-signatures, and cyberSign
agreements are EIP-712 typed-data signatures. Use `viem`'s `signTypedData`
with the domain/schema published by the relevant contract
(`RoundManager`, `DealManager`, `CyberAgreementRegistry`). The `signatures`
feature module centralises these.

## Conditions and gating

The `conditions` and `zkpassport` feature modules surface the protocol's
`ICondition` gating in the UI — e.g. prompting a user to obtain a LeXcheX
credential or complete a zkPassport proof before an action that an on-chain
condition would otherwise revert. Always treat these as UX hints: the chain
still enforces the condition regardless of what the UI shows.

## Multisig flows

Many issuer actions are executed by a Safe multisig (the board / officers).
The `multisig` feature module builds Safe transactions; `NEXT_PUBLIC_SAFE_API_KEY`
configures Safe API access.

## Keeping ABIs in sync

`packages/abis` must track the deployed protocol contracts. When the protocol
ships new implementations, update the ABIs there so the apps' typed calls
stay correct.
