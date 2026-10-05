# LeXscroWLite

LeXscroWLite is the atomic deal-closing escrow. It is implemented as the
**`LexScrowStorage` library**, linked into the deal and round managers;
the repository has no standalone `LeXscroWLite.sol` contract.

* [`src/storage/LexScrowStorage.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/storage/LexScrowStorage.sol)
  is the escrow library: `Escrow` and `Token` structs, `EscrowStatus`
  (`PENDING → PAID → FINALIZED`, or `VOIDED`), per-escrow `ICondition`
  lists, payment intake (`handleCounterPartyPayment`, with exact-amount
  checks against fee-on-transfer tokens), `finalizeEscrow` (asset delivery
  plus platform-fee distribution), `voidAndRefund`, and `conditionCheck`.
  The library declares the escrow events (`DealPaidAt`, `DealVoidedAt`,
  `DealFinalizedAt`, `FeeDistributed`). Linked library functions run in the
  manager's context by `DELEGATECALL`, so those logs come from the
  manager's address.
* [`src/interfaces/ILexScrowStorage.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ILexScrowStorage.sol)
  is the interface both managers implement: the escrow views
  (`getEscrowDetails`, `conditionCheck`), the fee hooks each manager
  supplies (`computeFee`, `getPlatformPayable`), and the shared
  `AgreementConditionsNotMet` error.

Both managers expose the escrow on their own proxies:

* [`DealManager`](DealManager.md) escrows payment and Ledger Entry Token
  (LET) effects across a deal's `proposeDeal` → `signDealAndPay` →
  `finalizeDeal` lifecycle, with `signToVoid`, `revokeDeal`,
  `voidExpiredDeal` and `refundVoidedDeal` for stale or voided deals. It
  runs a parallel `SecondaryEscrow` for secondary-trade settlements.
  Primary escrows pay the DealManager's primary fee; secondary settlements
  pay its separate secondary fee.
* [`RoundManager`](RoundManager.md) does the same across `submitEOI` →
  `allocate` / `reject` / `recallEOI`.

On each, `getEscrowDetails(agreementId)` returns the `Escrow` struct and
`conditionCheck(agreementId)` evaluates the attached conditions. Both
managers also implement `onERC721Received` / `onERC1155Received`, so assets
can be safe-transferred into escrow.
