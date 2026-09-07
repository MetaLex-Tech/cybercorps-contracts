# Proportional scrip-vault accounting

Every successful conversion or manager force-burn removes the converted underlying units from the
printer's shared pool. All certificate positions lose the same proportion of their attributed backing,
including the certificate receiving a conversion. ERC-20 balances change only through the existing
mint/burn/transfer operations; an attribution reduction does not burn another holder's ERC-20 balance.

## Bounded nominal shares

After initialization, `totalNominalShares == totalAssetsWad`. A deposit mints one normalized nominal
share per raw underlying unit. A withdrawal reduces both totals by the number of underlying units
withdrawn. Certificate shares are rebasing accounting values, not transferable ERC-4626 receipt tokens.
The global price getter consequently reports 1e27 for a nonempty initialized pool.

Updating every certificate would require an unbounded loop. Instead, a certificate stores its balance
and a snapshot of a cumulative proportional loss index. Getters apply subsequent index changes, and a
deposit checkpoints only the depositing certificate. Withdrawals, deposits, and position reads require
constant work, independent of the number of certificates or previous withdrawals.

The cumulative index has a normalized 256-bit mantissa and a separate binary exponent. Withdrawal
normalization keeps the mantissa between 2**255 and 2**256-1. An exponent change does not invalidate
positions; only an actually empty pool advances the existing vault epoch. This avoids both unbounded
nominal-share issuance and the zero-index failure of an ordinary fixed-point cumulative multiplier.

## Rounding policy and limits

- The index rounds downward. Its pre-normalization quotient has at least 254 significant bits, so
  the relative loss-index error in one update is less than 2**-253.
- Position claims use exact full-precision floor division against the stored index representation,
  including when the quotient before applying the binary exponent would need 257 bits.
- Depositing into an existing position checkpoints its floored claim. That discards less than one
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

The previous implementation first consumed the destination certificate's own claim and socialized
only the excess. This implementation socializes the whole amount. For two positions each claiming
100, a 50-unit conversion leaves each claiming 75, while the destination gains 50 active units.
This is an intentional change in certificate attribution, including any reporting based on it.

The 1000/100/750 example leaves 350 pooled units allocated approximately 318.1818 and 31.8182.
The converting holder's new certificate contains 750 active units. Re-scripifying those units mints
750 normalized shares, rather than an ever-increasing share quantity.

Tests cover this example, existing/new recipients, force burns, one-certificate round trips,
cross-certificate cycles, one-wei floors, full uint256 arithmetic, empty/refill retirement, fresh-pool initialization, randomized conservation, independent big-integer vectors, and constant withdrawal
gas with many live positions. Existing approval, compliance and ratio rules remain applicable.
