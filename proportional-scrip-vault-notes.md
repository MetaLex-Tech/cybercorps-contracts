# Proportional scrip-vault accounting

Every successful conversion or manager force-burn removes the converted underlying units from the
printer's shared pool. Conversion into an existing certificate consumes the legal holder's attributed
backing across their non-void certificates first. Only any excess reduces the remaining positions proportionally.
Conversion into a new approved certificate and manager force-burns reduce all positions proportionally.
ERC-20 transfers do not move certificate attribution; balances change only through the existing
mint/burn/transfer operations. An attribution reduction does not burn another holder's ERC-20 balance.

## Bounded nominal shares

After initialization, `totalNominalShares == totalAssetsWad`. A deposit mints one normalized nominal
share per raw underlying unit. A withdrawal reduces both totals by the number of underlying units
withdrawn. Direct redemption subtracts the consumed shares from the holder's certificates without
changing other holders' positions. Certificate shares are rebasing accounting values, not transferable ERC-4626 receipt tokens.
The global price getter consequently reports 1e27 for a nonempty initialized pool.

Updating every certificate would require an unbounded loop. Instead, a certificate stores its balance
and a snapshot of a cumulative proportional loss index. Getters apply subsequent index changes, and a
deposit or direct withdrawal checkpoints only the affected certificate. Proportional vault withdrawals,
deposits, and individual position reads require constant work, independent of the printer's total supply.
Direct redemption visits the caller's legal certificates in enumeration order, skips voided/zero-claim
positions, and stops as soon as enough attribution is consumed. Its gas scales with the number of the
caller's certificates visited, not every certificate in the printer. Holders with many certificates may
therefore incur substantial scan costs, particularly for excess redemption or backing late in the list.
The first non-void certificate receives all restored active units, even when several source positions
are consumed. Legal ownership, not ERC-721 custody, determines which positions are eligible.

The cumulative index has a normalized 256-bit mantissa and a separate binary exponent. Withdrawal
normalization keeps the mantissa between 2**255 and 2**256-1. An exponent change does not invalidate
positions; only an actually empty pool advances the existing vault epoch. This avoids both unbounded
nominal-share issuance and the zero-index failure of an ordinary fixed-point cumulative multiplier.

## Rounding policy and limits

- The index rounds downward. Its pre-normalization quotient has at least 254 significant bits, so
  the relative loss-index error in one update is less than 2**-253.
- Position claims use exact full-precision floor division against the stored index representation,
  including when the quotient before applying the binary exponent would need 257 bits.
- Depositing into or directly withdrawing from an existing position checkpoints its floored claim. That discards less than one
  raw underlying unit of fractional attribution, in addition to prior index error.
- Thus the sum of effective certificate shares/claims is **at most** the global share/asset total.
  The difference is unattributed rounding dust; the patch does not promise exact equality of the
  sum of independently floored positions with the pool total, or exact rational results forever.
- Dust remains backing for circulating scrip and is redeemable without a certificate claim. Even
  when all certificate claims round to zero, valid scrip can empty the pool. It is not reassigned
  to a caller or distributed by an order-dependent scan.
- At the extreme uint256 asset limit a single update can lose several raw units of attribution.
  At ordinary wad-scale supplies, the index approximation is far below one raw unit; a floor can
  still differ from the exact rational claim by one wei. Repeated updates/checkpoints accumulate
  conservative error. Consumers must not infer token balances from attribution getters.

Whole-unit displays that truncate wad values can show one less whole unit when an exact whole-unit
claim is rounded down by one wei. Applications displaying attributed backing should use a deliberate
display-rounding policy; active certificate units and ERC-20 balances are not rounded by this index.

## Fresh pools and storage layout

CyberScrip is not in production use, so this implementation assumes no existing scrip positions
need migration. A pool initializes its loss index on the first deposit. A position with a zero
snapshot index has no deposited shares. Empty-pool resets invalidate old positions in constant time.

The legacy exchange-rate fields and migration branches have been removed. Existing populated pools
are not supported by this implementation. The pre-existing reduction-debt slot remains reserved to
avoid shifting other fields in the shared certificate state. Consumers must read effective share
getters rather than interpreting a stored position snapshot as its current balance.

## Changed allocation and operational checks

Conversion now first consumes the holder's eligible claims and socializes only the excess.
For two holders each claiming 100, a 50-unit conversion by the first leaves it claiming 50 and the
second still claiming 100, while the receiving certificate gains 50 active units.
If a member deposited 900 from each of two certificates while another holder deposited 100, redeeming
the member's 1,800 consumes both 900-unit positions and leaves the other holder's 100 untouched.
Partial redemption continues through the member's positions in enumeration order; future redemptions
can consume later positions even when the receiving certificate no longer has any pool attribution.

At a 10:1 scrip-to-unit ratio, certificates A/B scripifying 10/90 units retain effective totals of 10/90.
If B directly redeems its 900 scrip, B restores 90 active units and A retains its 10 attributed units.
If B instead transfers 500 scrip to a new approved holder who certifies it, A/B retain 5/45 attributed
units and the new certificate receives 50 active units. Transfers alone do not alter attribution.

The 1000/100/750 example with a new approved recipient leaves 350 pooled units allocated approximately 318.1818 and 31.8182.
The converting holder's new certificate contains 750 active units. Re-scripifying those units mints
750 normalized shares, rather than an ever-increasing share quantity.

Tests cover this example, existing/new recipients, force burns, one- and multiple-certificate redemption,
custody distinct from legal ownership, voided-position exclusion, cross-certificate cycles, one-wei floors,
full uint256 arithmetic, empty/refill retirement, fresh-pool initialization, randomized conservation,
independent big-integer vectors, and constant proportional-withdrawal gas with many live positions.
Existing approval, compliance and ratio rules remain applicable.

This change prevents direct redemption covered by a member's eligible attribution from diluting other holders. It does not prevent
proportional reductions from recipients with no attributed position, including approved new holders.
Such reductions can still round attribution to zero. The existing permissionless empty-certificate
sweep and recertification-approval rules remain unchanged; this is not a general fix for that interaction.
