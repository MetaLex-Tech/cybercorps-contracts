# Attestation binding rule

Status: draft for owner review. Not an accepted decision.

## 1. First principle

An attestation authorizes or asserts only the bytes that it covers. The person who submits it
chooses every input that it does not cover.

An attestation is any statement that the system relies on:

- an EIP-712 or other off-chain signature,
- a signed transaction (the sender is `msg.sender`),
- a write by an authorized role (for example, the IssuanceManager writes a LET holder name),
- an allowlist, index or badge entry that a reader trusts.

So the question for each input is: "If an attacker picks this value, can the result change?"
If yes, the attestation must cover it.

### Attestation chain

Each attestation link depends on the attestation links below it.

| Attestation link                             | What it proves                                               | Evidence                                                          | Example                                                                                                                                                                                       |
|----------------------------------------------|--------------------------------------------------------------|-------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1a. Value                                    | The settlement of the value onchain                          | A signature or signed transaction over the value and its context  | A commitment or a plaintext amount                                                                                                                                                            |
| 1b. Record (collection of values) (optional) | The settlement of the record onchain                         | A signature or signed transaction over the record and its context | A commitment or a collection of values `{"chainId": 8453, "contract": "0xRegistry…", "agreementId": "0x…", "values": {"investor": "mtlxc1:…", "amount": "50000 USDC"}, "expiry": 1767225600}` |
| 1c. Private value (optional)                 | The human-readable value of the commitment                   | The opening (value and salt) matches the commitment hash          | The investor name behind a commitment `mtlxc1:…`                                                                                                                                              |
| 2a. Key                                      | That key made the attestation                                | Control of the private key                                        | The party's wallet                                                                                                                                                                            |
| 2b. Role (optional)                          | The key acts for another party, and holds that role at use   | A role grant, checked at use (rule 6 of §2)                       | An officer's wallet signs a round for the company                                                                                                                                             |
| 3. Real-world party                          | A real person or entity controls the key, or grants the role | An identity attestation (KYC, LeXcheX, a ZKPassport badge)        | A LeXcheX credential says that Alice's wallet belongs to a KYC-verified Alice                                                                                                                 |

- Attestation link 1c applies only to a private value. It adds to 1a or 1b, and does not
  replace them. Attestation link 2b applies only when a key acts for another party.
- Attestation link 1c does not prove who chose the value. Anyone can make an opening for any name.
  Only attestation links 1a or 1b, and 2a to 3, prove that.
- The binding rule (§2) applies at attestation link 1a or 1b, whichever is signed.
- A role grant is itself an attestation by the granting party, with its own chain.

## 2. The rule

An attestation covers, directly or through a hash, all six of these:

| # | Rule      | Question                                      | Typical form                                                                                                                 |
|---|-----------|-----------------------------------------------|------------------------------------------------------------------------------------------------------------------------------|
| 1 | Who       | Who attests, and for whom?                    | The signer address in the message when delegates or relayers exist. The subject wallet when the statement is about a person. |
| 2 | What      | Which values change the effect?               | Every amount, recipient, term and document. Put large or private data in as a hash or a commitment. Never omit it.           |
| 3 | Where     | In which system and which record?             | EIP-712 domain (chain, verifying contract, name, version). The record ID when the effect is for one record.                  |
| 4 | When      | For how long is it valid?                     | A deadline, checked at use.                                                                                                  |
| 5 | How often | How many times can it be used?                | A nonce or a one-time state change. If it is a standing authorization, say so, and give it a scope and a revocation path.    |
| 6 | Authority | Must the attester still have the role at use? | Check the role at use, or make the attestation revocable when the role changes.                                              |

### Rules of thumb

- **Values set after signing.** If the signer cannot know a value when it signs (for example, an
  expiry that a manager sets later), it signs a limit on the value (a maximum, a minimum or a
  range), or the rule that calculates the value from covered inputs (such as `createdAt` +
  `window` or the round end). The contract checks the limit, or calculates the value again, at
  use.
- **Claimable identifiers.** An ID that anyone can calculate and create first must include its
  creator, or only the authorized party may create it.
- **Exceptions.** An input can stay outside the attestation only if every value that an attacker
  can choose is harmless. Write that reason next to the code.

## 3. Privacy corollary

- A commitment is **content** (rule 2) at attestation link 1a. It hides a value. It is not an
  attestation.
- The opening proves attestation link 1c. For that, a commitment needs only a domain tag, the
  value and the salt.
- Commitment v1 also hashes the chain, contract, position and field. This is fine. Use it only to
  prove that the private value is the one written on the chain.
- Do not use a commitment as proof that a contract issued it on a chain. No issuer signs it, so
  anyone can compute one for any context. Most findings in [attestation binding gaps](attestation%20binding%20gaps.md) have the same root cause: an
  input that the attester did not sign.
- The context (rules 1, 3, 4, 5) goes into the attestation at attestation link 1a or 1b that
  covers the commitment. A party signature over the agreement values already does this.
- No attestation, allowlist or index may cover a commitment alone. It must also name the subject
  wallet, the scope and, where a fact can become old, a deadline.
- A verifier compares each of these with the record where it read the commitment.
