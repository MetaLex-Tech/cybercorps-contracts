# Tutorials

Tutorials are learning-oriented. Each one walks you, hand-in-hand, through a
small but complete piece of the protocol, so that at the end you have done
something concrete and understand *what just happened*.

If this is your first encounter with cyberCORPs, work through them in order.

1. [**Incorporate a cyberCORP**](incorporate-a-cybercorp.md) — deploy your
   first onchain legal entity, issue its genesis cyberCERT, and inspect the
   register.
2. [**Run a cyberRAISE round**](run-a-cyberraise-round.md) — configure a SAFE
   round, accept investor Expressions of Interest, escrow funds, and close.
3. [**Scripify and settle a secondary trade**](scripify-and-settle.md) —
   mint cyberSCRIP from a cyberCERT, trade it, and settle a buyer back onto
   the register.

## Prerequisites for all tutorials

* [Foundry](https://book.getfoundry.sh/) installed.
* An RPC endpoint for Base Sepolia (free tier is fine).
* A funded test wallet on Base Sepolia.
* A clone of [`cybercorps-contracts`](https://github.com/MetaLex-Tech/cybercorps-contracts)
  with `forge build --via-ir` succeeding locally.
* Familiarity with Solidity at the level of *can read a contract*.

> **No live funds are required.** Every tutorial runs against a forked Base
> Sepolia node. Replace `<your-rpc>` with your endpoint in commands.

## What these tutorials are not

They are not how-to recipes. They cover one path each, and they explain why
you are taking each step. For a goal-oriented recipe ("how do I disable force
transfer permanently?"), see [How-to Guides](../how-to/README.md). For dry
API detail, see [Reference](../reference/README.md).
