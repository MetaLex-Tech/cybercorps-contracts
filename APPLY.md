> Historical patch instructions: the patch has already been applied. The current checkout subsequently removed legacy scrip-position migration because CyberScrip is not in production use. See proportional-scrip-vault-notes.md for current behavior.

# Apply the proportional scrip-vault adjustment

The patch was prepared from `C:\Users\micha\Documents\new\MetaLex\cybercorps-contracts`
at commit `d0d488e6f5a45bc096604caab1aa518186cc9d06`. The requested repository was read-only
under this session's permissions, so it has not been modified. Implementation and tests ran in a
workspace copy with the repository's existing dependencies, Solidity 0.8.28, and Foundry configuration.

Run these commands in PowerShell to check and apply the patch:

```powershell
Set-Location -LiteralPath 'C:\Users\micha\Documents\new\MetaLex\cybercorps-contracts'
git apply --check 'C:\Users\micha\Documents\Codex\2026-09-06\analyze-this-audit-finding-in-cyber\outputs\proportional-scrip-vault.patch'
git apply 'C:\Users\micha\Documents\Codex\2026-09-06\analyze-this-audit-finding-in-cyber\outputs\proportional-scrip-vault.patch'
forge test --offline --match-contract 'IssuanceManager|ProportionalVaultMathTest|CyberScripTest|LedgerEntryToken' --gas-limit 100000000000 -vv
```

The larger test gas limit is needed to construct the existing 6,500-certificate fixture. Its conversion
itself still has a separate 30-million-gas call limit and must use less than 3 million gas.

The patch socializes every conversion, normalizes total shares to current backing, and lazily reduces
certificate shares with a normalized cumulative loss index. It includes append-only storage fields,
lazy migration of the current legacy share layout, full-precision arithmetic, fuzz/regression tests,
and independent full-width arithmetic vectors. See `proportional-scrip-vault-notes.md` for the economic
change, rounding/dust policy, index design, and migration limitations.

No contracts were deployed or upgraded. These tests do not validate older pre-vault storage layouts
or chain-specific live deployments. Existing ABI signatures are preserved; effective nominal share
values and certificate attribution change as described in the notes.

## Verified results

- Selected regression command above: **180 passed, 0 failed, 0 skipped** across 13 suites.
- New test file: 18 tests, including four fuzz tests at 256 cases each and 64 independent BigInt vectors.
  The randomized conservation test executes 80 operations per fuzz case.
- Final conversion at 6,500 certificates: **112,537 gas**. At 8, 128 and 256 certificates:
  **112,638 gas** in each case. The live-position partial-withdrawal gas comparison also passed.
- Solidity 0.8.28, optimizer enabled with 15 runs, via IR, existing repository dependencies.
- Deployed runtime bytecode: **23,803 bytes** for IssuanceManagerStorage and **17,840 bytes** for
  IssuanceManager, both below the 24,576-byte EIP-170 limit.
- New Solidity files pass `forge fmt --check`; the patch passes `git diff --check` and
  `git apply --check` against the requested repository.
- The full repository suite and live-chain fork tests were not run; the selected suites exercise
  issuance, conversion, compliance, vault epochs, CyberScrip, and the new proportional accounting.
