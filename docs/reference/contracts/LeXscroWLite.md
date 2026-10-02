# LeXscroWLite

> **There is no standalone `LeXscroWLite.sol` contract in this repository's
> `src/` tree.** The escrow layer is implemented as the **`LexScrowStorage`
> library**, embedded in the deal and round managers.

MetaLeX protocol materials refer to *LeXscroWLite* as the atomic
deal-closing escrow. In `cybercorps-contracts` it lives in:

* [`src/storage/LexScrowStorage.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/storage/LexScrowStorage.sol) —
  the escrow library: `Escrow` / `Token` structs, `EscrowStatus`
  (`PENDING → PAID → FINALIZED`, or `VOIDED`), per-escrow `ICondition`
  lists, payment intake (`handleCounterPartyPayment`, with exact-amount
  checks against fee-on-transfer tokens), `finalizeEscrow` (asset delivery
  plus platform-fee distribution), `voidAndRefund`, and `conditionCheck`.
  The library declares the escrow events (`DealPaidAt`, `DealVoidedAt`,
  `DealFinalizedAt`, `FeeDistributed`); the library code runs in the
  manager's context (linked library functions by `DELEGATECALL`), so those
  logs are emitted from the manager's address.
* [`src/interfaces/ILexScrowStorage.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ILexScrowStorage.sol) —
  the shared interface both managers implement: the escrow views
  (`getEscrowDetails`, `conditionCheck`), the fee hooks each manager
  supplies (`computeFee`, `getPlatformPayable`), and the shared
  `AgreementConditionsNotMet` error.

Both managers expose the escrow surface on their own proxies:

* [`DealManager`](DealManager.md) escrows payment and certificate effects
  across a deal's `proposeDeal` → `signDealAndPay` → `finalizeDeal`
  lifecycle (with `signToVoid`, `revokeDeal`, `voidExpiredDeal` and
  `refundVoidedDeal` for stale or voided deals), and runs a parallel
  `SecondaryEscrow` machinery for secondary-trade settlements. Primary
  escrows pay the DealManager's primary fee; secondary settlements pay its
  separate secondary fee.
* [`RoundManager`](RoundManager.md) does the equivalent across
  `submitEOI` → `allocate` / `reject` / `recallEOI`.

On each, `getEscrowDetails(agreementId)` returns the `Escrow` struct and
`conditionCheck(agreementId)` evaluates the attached conditions; both also
implement the `onERC721Received` / `onERC1155Received` hooks so assets can
be safe-transferred into escrow.

This page will be replaced with a full contract reference if and when a
standalone escrow contract lands in `src/`.
