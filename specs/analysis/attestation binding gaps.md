# Attestation binding gaps

Status: draft for owner review. Not an accepted decision.

This doc compares the current code with the [attestation binding rule](attestation%20binding%20rule.md).

## 1. Gaps in the current contracts

✓ = covered. ✗ = not covered. — = not applicable.

| Attestation                                                     | Who                     | What                                               | Where | When                                              | How often                          | Authority                                      | Related findings                                    |
|-----------------------------------------------------------------|-------------------------|----------------------------------------------------|-------|---------------------------------------------------|------------------------------------|------------------------------------------------|-----------------------------------------------------|
| Registry `SignatureData` (party signs an agreement)             | ✓                      | ✓                                                 | ✓    | ✗ expiry not in the ID or the signed data        | ✓ once for each party             | —                                              | MTLX1-39 (Medium, Acknowledged)                     |
| Registry `contractId` (agreement ID)                            | ✗ creator not included | ✓                                                 | ✓    | ✗                                                | —                                  | —                                              | MTLX1-30 (Low, Acknowledged)                        |
| Registry bound agreement (`boundIds`)                           | ✓ creator              | ✓ includes party values                           | ✓    | ✓ expiry in the terms                            | ✓                                 | —                                              | —                                                   |
| Registry `VoidSignatureData`                                    | ✓                      | ✓                                                 | ✓    | ✗                                                | ✓ void is final                   | —                                              | —                                                   |
| RoundManager `EscrowedSignatureData` (officer approves a round) | ✓                      | ✗ no hash of the agreement body or `globalValues` | ✓    | ✓ round start and end                            | Standing for the round, by design  | ✗ officer role checked only at round creation | MTLX1-24 (Low, Acknowledged); MTLX1-26 (Low, Fixed) |
| Factory `RoundSupplementalData`                                 | ✓                      | ✓                                                 | ✓    | ✗                                                | ✓ one company for each `corpSalt` | —                                              | —                                                   |
| Secondary `PostOfferAuth` / `AcceptOfferAuth` (relayer)         | ✓ `forAddr`            | ✓ full params                                     | ✓    | Partial: limited only by the offer's `validUntil` | ✓ unordered nonce                 | —                                              | —                                                   |
| Secondary `CancelOfferAuth` / `VoidSecondaryTradeAuth`          | ✓                      | ✓                                                 | ✓    | ✗                                                | ✓ nonce                           | —                                              | —                                                   |
| LeXcheX `AuthorityData` (KYC authority)                         | ✓ owner                | Partial: plaintext PII, no tokenId                 | ✓    | ✓ expiry                                         | ✗ not consumed on renewal         | —                                              | MTLX1-17 (Medium, Acknowledged)                     |
| ParentCo `EscrowAuthorization(name, contact)`                   | ✓                      | ✗ no agreement or scope                           | ✓    | ✗                                                | Standing for all agreements        | Owner can replace it                           | —                                                   |
| BorgAuth ownership transfer                                     | —                       | —                                                  | —     | —                                                 | —                                  | ✗ the old owner keeps the role                | MTLX1-14 (Low, Acknowledged)                        |

Fixed findings with the same root cause: MTLX1-26, MTLX1-31, MTLX1-37, MTLX1-41.

All findings are from the Hexens report in `audits/`. Acknowledged findings are accepted residual
risks. A refactor that changes one of them needs an explicit owner decision.

## 2. Gaps in the privacy design (webapp, not yet deployed)

| Item                                        | Gap                                                                                                              |
|---------------------------------------------|------------------------------------------------------------------------------------------------------------------|
| Planned LeXcheX signature over a commitment | Must name the subject wallet, scope, deadline and a consumed nonce. Today's LeXcheX authority path has MTLX1-17. |
| Name lookups or "known commitment" lists    | Must not use the commitment alone as the key (rule doc §3).                                                      |
| LeXcheX badge `Credential.investorName`     | Plaintext PII on the chain. Not an attestation ("display/audit only").                                           |

## 3. Refactor order

1. Apply the rule to all new code, starting with the privacy design and LeXcheX commitment
   attestations.
2. Before LeXcheX signs commitments: bind its authority signature to the wallet, tokenId, scope,
   nonce and deadline (MTLX1-17).
3. Move standalone agreement creation to the bound path. It already covers the creator and the
   expiry (MTLX1-39, MTLX1-30).
4. In the next RoundManager version, the officer signs a hash of the agreement body and
   `globalValues` (MTLX1-24). Check the officer role at use, or make the round signature
   revocable.
5. Add deadlines to relayer authorizations that lack one.
6. Replace the ParentCo standing authorization with a scoped one, or record why a standing
   authorization is necessary.

Legacy shapes are not a limit on new designs. Each step is a separate change with its own tests.
