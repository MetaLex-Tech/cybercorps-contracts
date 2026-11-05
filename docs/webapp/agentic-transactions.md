---
description: Review agent-prepared MetaLeX actions, authorize exact revisions and recover unresolved attempts
---

# Agentic transactions

An agentic transaction is a private review page of proposed MetaLeX actions.
GAIBE or an authorized MCP client can prepare and revise supported actions;
you review their terms, documents, effects and blockers before authorizing
execution. The page uses `/agentic-transactions/<id>` on a supported product
host. Open the returned link and sign in to the account that owns it.

This interface is in the November 4 production source and requires the
`AGENTIC_TRANSACTIONS_ENABLED` setting. This documentation review did not
read the hosted setting. Availability of one action does not enable another.

## Review and authorize

Read the deterministic action summary and expand its documents. Check the
company, network, wallet, amounts, recipients and any values marked as not
yet confirmed by you. GAIBE's comments supplement those values. An agent's
access to the page does not give it the company's execution authority.

Authorize the exact action revision. Depending on the action, the next
steps can include a server confirmation, message signatures, a transaction,
or a Safe proposal. The page asks for Terms of Service acceptance before
it starts an action or the server step of a wallet action. A Safe proposal
still needs the Safe's own approvals and execution.

Supported adapters include fundraising, company/class setup, cap table
records, LET and grant operations, document/governance workflows and legal
terms. The catalog checks each action's schema and prerequisites. For legal
terms, proposal, approval and activation remain separate operations; an
approved version still needs activation.

## Revisions, results and recovery

Edits create a new revision with a visible diff. Changing an action
invalidates its previous review. An action with an attempt in progress or
already completed cannot be rewritten or removed. A collection of actions
can complete partially; authorizing one is not blanket approval of later
steps, and the collection is not one atomic transaction.

Read each attempt's status and returned result links. A pending or unknown
outcome is not proof of failure. Reconcile it through the page before
retrying, so an uncertain send does not create a duplicate operation.
Deleting an unexecuted draft removes it; records with execution attempts
are archived with their revisions and evidence.

## Use an MCP client

The MCP scopes `agentic-transactions:read` and
`agentic-transactions:write` control report access and preparation.
Separate scopes govern private documents and company data. The tools can
list supported kinds, create, read, revise, delete or archive records.
They do not execute actions, sign messages or submit transactions. The
person authorizes those steps on the review page. Afterward, a client can
read the recorded status and share the result links.
