# ZKPassportFinalizer (historical)

`ZKPassportFinalizer` was the separate per-party passport finalizer described
in the October 27 book. Contract source removed it on October 29 in favor of
[registry signer conditions](SignerConditions.md). New integrations should
use the conditioned creator-bound methods on a reviewed compatible registry.

For an existing agreement, read its recorded registry, finalizer and
creation identity. Removing source does not migrate or retire an already
deployed finalizer, and a new registry path cannot complete a historical
agreement merely by recomputing its id.

The historical implementation and its `PartyGate`, `signWithProof`,
`signWithoutProof`, `attest` and `finalize` APIs remain available in
[the October 27 source](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/03651994c03bf2b2ff9f8af655caee51eed7de89/src/ZKPassportFinalizer.sol).
That workflow waited for both signatures and required passport evidence
before its finalizer completed the agreement. The current app refuses
requests stored under that retired flow (`passport_finalizer_retired`).
An unfinished request needs a new request using the supported flow. An
already completed agreement remains recorded onchain under its original id;
source removal does not erase its history.
