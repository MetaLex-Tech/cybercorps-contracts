# Integrate from a frontend

This guide covers calling the protocol from a TypeScript / React / Next.js
front end. The reference implementation is the
[`metalex-webapp`](https://github.com/MetaLex-Tech/metalex-webapp) monorepo;
the app most directly equivalent to a generic issuer Mainframe is
[`apps/cybercorps-web`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/cybercorps-web).

## Stack used in the reference UIs

* **Next.js (App Router)** with `bun` as package manager
* **wagmi + viem** for contract interaction
* **RainbowKit / Rabby / Safe** for wallet connection
* **Privy / SIWE** for session auth (`SIWE_ALLOWED_DOMAINS` env var)
* **Tailwind + biome** for styling and linting
* **A custom indexer** (`apps/cybercorps-indexer`) for cap-table queries
* **A notifier** (`apps/notifier`) for event-driven notifications
* **An oracle** (`apps/lexchex-oracle`) for accreditation backstop

## Calling the contracts

### 1. Generate types from ABIs

With `wagmi/cli` and the package containing the protocol ABIs:

```ts
import { useReadContract, useWriteContract } from "wagmi";
import { cyberCorpAbi } from "@/abis";

const { data: legalName } = useReadContract({
  abi: cyberCorpAbi,
  address: cyberCorpAddr,
  functionName: "legalName",
});
```

### 2. Submit an EIP-712 EOI

Use `viem.signTypedData` with the schema published by `RoundManager`:

```ts
const signature = await wallet.signTypedData({
  domain: { name: "cyberRAISE", version: "1", chainId, verifyingContract: roundManagerAddr },
  types: { EOI: [...] },
  primaryType: "EOI",
  message: { investor: account.address, amount: 100_000_000_000n, /* ... */ }
});

await write({ functionName: "submitEOI", args: [roundId, eoi, signature] });
```

### 3. Read the register

A cap-table view typically pages over `CyberCertPrinter` tokens via an
indexer rather than reading on-chain. The reference
[`cybercorps-indexer`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/cybercorps-indexer)
uses **ponder** to project events into a SQL store.

### 4. Render the cert SVG

`tokenURI` returns a base64-encoded JSON whose `image` is itself a base64 SVG.
To display:

```ts
const json = JSON.parse(atob(uri.split(",")[1]));
const svg = atob(json.image.split(",")[1]);
return <img src={`data:image/svg+xml;base64,${btoa(svg)}`} />;
```

## Subdomain routing in the reference app

The webapp exposes multiple product surfaces (cyberRAISE, ACE, profile, etc.)
behind subdomains driven by env vars:

```
NEXT_PUBLIC_USE_SUBDOMAIN_ROUTING=true
NEXT_PUBLIC_APP_DOMAIN=metalex.tech
SIWE_ALLOWED_DOMAINS=cybercorps.metalex.tech,cyberraise.metalex.tech,pump.metalex.tech
```

Use the same pattern if you want to mount the issuer Mainframe at one domain
and the public ACE / cyberRAISE views at others.

## Related

* Explanation: [Application stack](../explanation/application-stack.md).
* See the `cybercorps-web` `README.md` in `metalex-webapp` for env setup.
