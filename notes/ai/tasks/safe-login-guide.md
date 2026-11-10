# Safe login documentation

Updated November 10, 2026. Owner: Codex Safe offchain-access chat. User explicitly requested clear normal Safe-login instructions on the docs site while implementing separate non-signer read access. Documentation-only branch `codex/safe-login-guide`, base `7939be7`. No contract implementation or runtime changes.

New `docs/webapp/safe-wallets.md` explains direct Ambire/Rabby account connection, profile login versus Safe owner signer, threshold message approvals, Transactions > Messages, one-hour chain-scoped app access, renewal/revocation and separate agreement delegation. Profile guide's obsolete "Safe can't be linked" claim is corrected. Summary and holders guide link the new page. Non-signer persistent read access is explicitly marked in development, not shipped.

Sources: webapp production Safe release65ed08c and local current source83718931ec0; official Ambire import/direct-connection/message-sync documentation; Safe signed-message documentation; Rabby source pending-message queue confirms separate queues but installed-extension acceptance remains unverified. No customer screenshots, addresses, balances, messages or personal data copied into docs.

Next: link/copy review, ready docs PR, verify GitBook publication separately from source merge. The independent webapp authorization review and implementation remain in the webapp safe-offchain-access task. This docs change grants no authority to deploy that feature or apply its schema migration.
