# Copy Base agreement templates to Robinhood

The prepared script registers **86 missing templates** using the exact IDs,
titles, legal URIs, ordered global fields and signer fields from Base at block
**53290002**. It uses Robinhood's existing canonical CyberAgreementRegistry,
`0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134`, on chain **4663**. Template creation
is permissionless; no Safe transaction, proxy deployment or upgrade is needed.

The complete Base snapshot is [base-templates.json](base-templates.json), with
**87** definitions, including historical, bespoke and test definitions. The
default deployment input is [robinhood-base-templates.json](robinhood-base-templates.json).
Its destination audit preserves Robinhood's existing legacy SAFE ID **1**, whose
IPFS document differs from Base's. The registry has no overwrite operation for an
existing template. No replacement ID or different legal document is introduced.
The other **86** IDs were missing at Robinhood block **101773759**.

The script preflights the entire selected list before queuing registrations.
Exact definitions already on Robinhood are skipped. Any unexpected same-ID
definition difference, duplicate ID, wrong chain, malformed manifest or unexpected
registry read error aborts. A partial operator broadcast can be rerun: confirmed
exact matches skip. Field order and URI case are compared byte-for-byte.

## Dry run

From the repository root, with the existing `RPC_URL_ROBINHOOD` configuration:

```powershell
$templateArgs = @(
  'script', 'script/sync-base-templates.s.sol:SyncBaseTemplatesScript',
  '--rpc-url', 'robinhood',
  '--use', '0.8.28', '--evm-version', 'cancun', '--via-ir', '--offline',
  '-R', '@openzeppelin/contracts/=dependencies/openzeppelin-contracts/contracts/',
  '-R', '@openzeppelin/contracts-upgradeable/=dependencies/openzeppelin-contracts-upgradeable/contracts/'
)
forge @templateArgs
```

The script reads `PRIVATE_KEY_MAIN` from the environment and uses that key's
address as the registration sender. Use your existing environment configuration;
no key value is embedded in the script. The sender acquires no template admin
role. Review the selected definitions and the preserved-ID audit before sending.
Source verification is unnecessary because this registers data in an existing
contract; do not add `--verify` or change implementations.

## Operator broadcast

Use the same arguments with `PRIVATE_KEY_MAIN` available in the environment:

```powershell
forge @templateArgs --broadcast --slow
```

This script uses `vm.broadcast(deployerPrivateKey)` with the environment value;
no `--account` or `--private-key` argument is needed. Never use `--skip-simulation`.

After receipts confirm, repeat the dry run: expect **0 registrations and 86 exact
matches skipped**, assuming no intervening template registration or configuration
change. Read template 32 and the intended application's SAFE ID from Robinhood,
then repeat application signing/payment/issuance acceptance against actual state.
Legacy ID 1 will still retain Robinhood's original definition.

These commands are an operator handoff, not evidence of real signing/submission
or a replacement for independent review/integration gates. No live transaction
has been sent by this preparation task.

## Refreshing the source or destination plan

The checked-in event inventory was discovered with a complete indexed query from
genesis through block 53290002: **87 events, 87 distinct IDs**, below the response
cap. [base-template-events.json](base-template-events.json) records the exact
public Base Blockscout query. Each definition in the snapshot was then independently
read from the Base registry through RPC at that pinned block; explorer text was
not used as the template definition. All these are public on-chain definitions.

To reproduce this pinned source snapshot and refresh the destination audit:

```powershell
python script/export-base-templates.py --event-inventory script/res/base-template-events.json
python script/prepare-robinhood-templates.py
```

The exporter uses `RPC_URL_BASE`, or the existing Alchemy API configuration for
state reads, and never a signing key. The destination preparer reads only the
configured Robinhood RPC. It writes a reviewable plan that excludes/reports
conflicting immutable destination IDs; inspect its full `destinationAudit` before
running Forge. Export/preparation errors leave the previous manifest intact.

For a new complete event discovery, a historical-log-capable endpoint is needed:

```powershell
$env:BASE_LOGS_RPC_URL = '<Base RPC supporting historical eth_getLogs>'
python script/export-base-templates.py
python script/prepare-robinhood-templates.py
```

The RPC exporter scans bounded intervals from the registry's discovered deployment
boundary and caches completed intervals under `out/base-template-export/`. Its
boundary search assumes the canonical proxy's continuous deployment; use a full
genesis-indexed inventory if that assumption does not apply. A failed interval
aborts export rather than producing a partial list. Etherscan V2 indexed discovery
is optional (`--event-source etherscan`) and requires API coverage for Base; the
current free API configuration does not include that coverage.

## Local acceptance

```powershell
python script/test-base-template-sync.py
```

This runs unit safeguards and actual deployed-registry fork acceptance, including
all selected definitions, an idempotent rerun, preservation of ID 1 and the registry
implementation, full signed USDG investment and SAFE LET issuance, metadata/SVG
validation, and signature/authorization/refund refusal paths. It uses public toy
signers and local funding only. Source/target blocks, result counts and file hashes
are recorded in `notes/ai/tasks/robinhood-base-template-sync-verification-20261030.json`;
sanitized logs and rendered certificate data are local under `out/base-template-sync/`.
The prepared version passed **17 checks: 13 unit tests and 4 fork scenarios**, with
no failures or skips. The fork used Robinhood block 101773759; the Base definitions
were read at block 53290002. No registration was broadcast.

Those results predate the change to read `PRIVATE_KEY_MAIN`. At the user's explicit
request, no tests were run for that signing change and no key was read, set or
inserted during the edit.
