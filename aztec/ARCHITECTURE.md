# Private Agreement Registry on Aztec: Architecture

This document describes the proof of concept (PoC) port of `src/CyberAgreementRegistry.sol` to Aztec.
The PoC supports the happy path of one agreement: every party signs offchain, and MetaLeX settles all signatures
in one private transaction (`finalize`). See [USER-FLOWS.md](USER-FLOWS.md) for the step-by-step flows.

Toolchain: Aztec 6.0.0, aztec-nr v6.0.0, Noir 1.0.0-rc.3.

## Design rules

1. The chain keeps only nullifiers. Agreement text, field values and party addresses stay offchain.
2. Each party signs offchain with a private authwit. MetaLeX collects the authwits and sends one `finalize` tx
   when all parties signed. No party needs to send a tx or hold a fee token.
3. The parties, and the people they share an invite with, know the salt. MetaLeX may cache the invite for a fixed
   retention period to make the webapp easier to use. During that period, MetaLeX can read the agreement. Users
   accept this trust. The collector and the settler never get the salt, the terms or the document text.
4. The MetaLeX services hold no user keys.

## Components

```mermaid
flowchart LR
    subgraph User device
        App[MetaLeX webapp<br/>PII: plaintext, in memory]
        PXE[Wallet + PXE<br/>keys]
    end
    subgraph MetaLeX services
        Catalog[Template catalog<br/>public]
        Vault[Document vault<br/>PII: ciphertext only]
        Collector[Signature collector<br/>PII metadata: parties, signing times]
        Settler[Settler<br/>MetaLeX wallet + PXE<br/>PII metadata: parties]
        Cache[Invite cache<br/>PII access: salt, during retention<br/>encrypted with the KMS key]
        KMS[Key management service<br/>invite cache key]
    end
    subgraph Aztec network
        Node[Aztec node RPC<br/>network data: PXE IP, lookups]
        Registry[CyberAgreementRegistry<br/>private functions]
        Accounts[Party account contracts<br/>verify authwits]
        FPC[Fee payer contract<br/>MetaLeX deploys and funds it]
        Sequencer[Sequencer<br/>builds blocks]
        subgraph Private state
            Trees[Nullifier tree<br/>agreement nullifiers]
        end
        subgraph Public state
            FeeJuice[Public data tree<br/>FPC fee juice balance]
        end
    end
    App --> PXE
    App --> Catalog
    App --> Vault
    App -->|authwit| Collector
    App -->|invite| Cache
    Cache -->|encrypt, decrypt| KMS
    Collector --> Settler
    PXE -. runs utilities locally .-> Registry
    PXE -->|read trees| Node
    Settler -. runs finalize locally .-> Registry
    Registry -. static call .-> Accounts
    Settler -. runs locally .-> FPC
    Settler -->|send tx| Node
    Node --> Sequencer
    Sequencer -->|insert nullifiers| Trees
    Sequencer -->|deduct fee| FeeJuice

    subgraph Legend
        direction TB
        LPlain[Red: can read plaintext PII]
        LCipher[Brown: holds encrypted PII only]
        LMeta[Blue: holds metadata about people, no document content]
        LNone[No color: holds no PII]
    end

    classDef piiPlain fill:#842029,stroke:#58151c,color:#fff
    classDef piiCipher fill:#664d03,stroke:#332701,color:#fff
    classDef piiMeta fill:#084298,stroke:#052c65,color:#fff
    class App,Cache,LPlain piiPlain
    class Vault,LCipher piiCipher
    class Collector,Settler,Node,LMeta piiMeta
```

The legend explains the colors. See [PII: who can see what](#pii-who-can-see-what) for the details.

| Component                         | Who runs it                                       | What it stores                                                            | What it can read                                                  |
|-----------------------------------|---------------------------------------------------|---------------------------------------------------------------------------|-------------------------------------------------------------------|
| `CyberAgreementRegistry` contract | Aztec network                                     | Nullifiers only (private state)                                           | Nothing after the tx                                              |
| User wallet and PXE               | User (browser embedded wallet or an Aztec wallet) | Account keys                                                              | What the user opens in it                                         |
| MetaLeX webapp                    | MetaLeX (code), user (runtime)                    | The invites that the user keeps                                           | What the user opens in it                                         |
| Template catalog                  | MetaLeX                                           | Public legal templates                                                    | Public data only                                                  |
| Document vault                    | MetaLeX                                           | AES-256-GCM document blobs, keyed by a locator                            | Locator, blob size, upload and fetch times                        |
| Signature collector               | MetaLeX                                           | Onboarded account data, `Agreement` structs without salt, authwits        | Parties, expiry, agreement id, who signed and when                |
| Settler                           | MetaLeX                                           | Its own account keys, the public signing keys of the party accounts       | The same as the collector, and the finalize status                |
| Invite cache                      | MetaLeX                                           | Invites encrypted with the KMS key, until the end of the retention period | With the vault: all data of each cached agreement                 |
| Key management service (KMS)      | MetaLeX account at a cloud KMS                    | The invite cache key; the key never leaves the KMS                        | Nothing; it logs each decrypt                                     |
| Party account contracts           | Aztec network; each user owns one                 | The signing public key, in the contract instance (`immutables_hash`)      | Nothing after the tx                                              |
| Fee payer contract (FPC)          | Aztec network; MetaLeX deploys and funds it       | Fee juice balance (public state)                                          | That a sponsored tx happened                                      |
| Aztec node RPC                    | Aztec network                                     | Chain state                                                               | Queries from each PXE (nullifier lookups, tx hashes)              |
| Sequencer                         | Aztec network                                     | Nothing; it writes tx effects into the trees                              | Tx effects: nullifiers, fee payer, fee                            |

## Data model

### Agreement (circuit input)

```noir
struct Agreement {
    terms_commitment: Field,              // hides the terms; only salt holders can open it
    expiry: u64,                          // 0 means no expiry
    party_count: u32,
    parties: [AztecAddress; MAX_PARTIES], // unused slots are zero
}
```

`MAX_PARTIES` is 4. Each party adds one private call to its account contract in the finalize tx.

The struct holds no salt and no `terms_hash`. So the settler can run `finalize` and still cannot open the document.

### Derived values

| Value               | Formula                                                                                   | Where it is computed                       |
|---------------------|-------------------------------------------------------------------------------------------|--------------------------------------------|
| `terms_hash`        | `sha256(canonical JSON of the document)` reduced into the field                           | Webapp                                     |
| `terms_commitment`  | `poseidon2([terms_hash, salt], "metalex.agreement.terms.v1")`                             | Webapp, with the `terms_commitment_of` utility |
| `agreement_id`      | `poseidon2([terms_commitment, expiry, party_count, parties...], "metalex.agreement.id.v1")` | Circuit, and the `agreement_id` utility    |
| Consent hash        | `compute_inner_authwit_hash(["metalex.agreement.consent.v1", agreement_id, signer])`      | Circuit, and the `consent_hash_of` utility |
| Authwit             | The signature of the party over `poseidon2([registry, chain_id, version, consent hash])`  | Party wallet                               |
| Authwit nullifier   | `compute_authwit_nullifier(signer, consent hash)`, one per party                          | Circuit                                    |
| Padding nullifier   | `poseidon2([agreement_id, slot], "metalex.agreement.padding.v1")`, one per unused slot     | Circuit                                    |
| Finalized nullifier | `poseidon2([agreement_id], "metalex.agreement.finalized.v1")`                             | Circuit, and the `is_finalized` utility    |
| Vault locator       | `HKDF-SHA256(ikm = salt, salt = empty, info = "metalex.doc.locator.v1", 32 bytes)`        | Webapp                                     |
| Document key        | `HKDF-SHA256(ikm = salt, salt = empty, info = "metalex.doc.key.v1", 32 bytes)`            | Webapp                                     |

The consent hash holds the signer. Two parties that sign the same agreement must sign different messages. The PXE
finds an authwit by its message hash, and that hash does not hold the signer.

The PoC uses one hash for the whole document. A Poseidon Merkle root over the fields would let a party later prove
one field in a circuit without the others.

The salt is the root secret of an agreement. A holder of the salt can open the terms commitment, find the vault
blob and decrypt it. Without the salt, nobody can link the agreement id to a document. The webapp must make the
salt with a secure random source.

### Invite

The invite is what a party shares with a counterparty or an auditor. It holds the salt, the expiry and the party
addresses. With the invite and the vault blob, the webapp can rebuild the `Agreement` struct and the agreement id.

The webapp puts the invite in the URL fragment (after `#`). A browser does not send the fragment to the server, so
a shared link does not give the invite to MetaLeX. A holder of the invite can read the whole document.

The webapp also gives each invite to the MetaLeX invite cache. The cache gives it back to a signed-in party, so the
party can open the agreement on any device without the link. The cache deletes the invite at the end of the
retention period. After that, the party needs its own copy of the invite. The PoC does not include the cache. The webapp treats each
party address in an invite as untrusted and checks that it is a valid address.

### Canonical JSON

All parties must get the same `terms_hash` from the same document. So the webapp writes the document as one fixed
JSON string before it hashes it:

- It sorts the keys of each object.
- It writes no spaces and no line breaks.
- It keeps the order of each array.
- It writes strings and numbers as `JSON.stringify` does.

The standard for this is RFC 8785, the JSON Canonicalization Scheme (JCS). The PoC function `canonicalJson` in
`scripts/e2e.ts` gives the JCS output for strings, numbers, arrays and objects. A webapp in another language must use
JCS. The same string is the plaintext of the vault blob, so a party decrypts the exact bytes that were hashed.

The document holds:

- `template`: the title, the URI and the field names, from the public catalog.
- `globalValues`: the values of the fields that apply to the whole agreement.
- `partyValues`: for each party address, the values of that party. These hold the PII.

The salt is not in the document. It is in the invite. The expiry is a field of `Agreement`. The value arrays are an
open item (see [Limits and open items](#limits-and-open-items)).

Example document:

```json
{
  "template": {
    "title": "Mutual NDA",
    "uri": "ipfs://example-template",
    "globalFields": ["effectiveDate"],
    "partyFields": ["name"]
  },
  "globalValues": ["2026-11-01"],
  "partyValues": [
    ["<Alice address>", ["Alice Corp"]],
    ["<Bob address>", ["Bob LLC"]]
  ]
}
```

Its canonical JSON, which the webapp hashes:

```text
{"globalValues":["2026-11-01"],"partyValues":[["<Alice address>",["Alice Corp"]],["<Bob address>",["Bob LLC"]]],"template":{"globalFields":["effectiveDate"],"partyFields":["name"],"title":"Mutual NDA","uri":"ipfs://example-template"}}
```

### Secrets, keys and hashes

Each box is a place where a value lives. The legend explains the colors and the dashed boxes.

```mermaid
flowchart TB
    subgraph Wallet["Each party: wallet and PXE"]
        SIG["Signing key"]
    end
    subgraph Webapp["MetaLeX webapp, in browser memory"]
        INV["Invite<br/>salt, expiry, parties"]
        DOC["Document, PII<br/>template and values"]
        TH["terms_hash"]
        TC["terms_commitment"]
        AID["agreement_id"]
        CH["Consent hash<br/>one per party"]
        LOC["Vault locator"]
        KEY["Document key"]
    end
    subgraph Vault["MetaLeX vault"]
        BLOB["Encrypted document blob"]
    end
    subgraph Cache["MetaLeX invite cache, during retention"]
        CINV["Invite, encrypted"]
    end
    subgraph KMSBox["MetaLeX key management service"]
        CKEY["Invite cache key"]
    end
    subgraph Collector["MetaLeX signature collector and settler"]
        AGR["Agreement<br/>terms_commitment, expiry, parties"]
        AW["Authwit<br/>one per party"]
    end
    subgraph Chain["Aztec chain: nullifier tree"]
        AWN["Authwit nullifier<br/>one per party"]
        PAD["Padding nullifier<br/>one per unused slot"]
        FIN["Finalized nullifier"]
    end

    DOC -->|SHA-256| TH
    TH -->|Poseidon2 with salt| TC
    INV -->|salt| TC
    INV -->|cached copy| CINV
    CKEY -->|AES-256-GCM encrypts| CINV
    INV -->|HKDF, locator label| LOC
    INV -->|HKDF, key label| KEY
    KEY -->|AES-256-GCM encrypts| BLOB
    LOC -->|indexes| BLOB
    TC -->|Poseidon2 with expiry, parties| AID
    TC --> AGR
    AID -->|with signer| CH
    SIG -->|signs| AW
    CH --> AW
    AW -->|finalize checks| AWN
    AGR -->|finalize| FIN
    AGR -->|finalize| PAD

    subgraph Legend
        direction TB
        LPlain[Red: can read plaintext PII]
        LCipher[Brown: holds encrypted PII only]
        LMeta[Blue: holds metadata about people, no document content]
        LNone[No color: holds no PII]
        LDerived[Dashed: computed when needed, not stored]
    end

    classDef derived stroke-dasharray: 5 5
    classDef piiPlain fill:#842029,stroke:#58151c,color:#fff
    classDef piiCipher fill:#664d03,stroke:#332701,color:#fff
    classDef piiMeta fill:#084298,stroke:#052c65,color:#fff
    class TH,TC,AID,CH,LOC,KEY,LDerived derived
    class DOC,INV,CINV,LPlain piiPlain
    class BLOB,LCipher piiCipher
    class AGR,LMeta piiMeta
```

| Value                   | Kind           | Made by                               | Known to                                           | Stored at                                                     |
|-------------------------|----------------|---------------------------------------|----------------------------------------------------|---------------------------------------------------------------|
| Signing key             | Secret         | Party's wallet                        | That party                                         | Wallet                                                        |
| Salt                    | Secret         | Creator's webapp, random              | All parties, each holder of the invite, and MetaLeX during retention | Inside the invite; encrypted in the MetaLeX invite cache during retention; never onchain |
| Invite cache key        | Secret         | MetaLeX KMS                           | Nobody; only the KMS uses it                       | MetaLeX KMS                                                   |
| Document                | PII            | Creator's webapp                      | All parties, and each holder of the invite         | Plaintext only in webapp memory; ciphertext in the vault      |
| `terms_hash`            | Hash           | Webapp, SHA-256 of the document       | Each holder of the invite                          | Not stored                                                    |
| `terms_commitment`      | Hash           | Webapp, Poseidon2                     | Each holder of the invite, and MetaLeX             | In the collector                                              |
| `agreement_id`          | Hash           | Webapp and circuit, Poseidon2         | Each holder of the invite, and MetaLeX             | Collector index                                               |
| Consent hash            | Hash           | Webapp and circuit                    | The same as `agreement_id`                         | Not stored                                                    |
| Authwit                 | Signature      | Party's wallet                        | That party and MetaLeX                             | Collector, until the finalize tx                              |
| Authwit nullifier       | Hash           | Circuit                               | Public                                             | Nullifier tree                                                |
| Padding nullifier       | Hash           | Circuit                               | Public                                             | Nullifier tree                                                |
| Finalized nullifier     | Hash           | Circuit                               | Public                                             | Nullifier tree                                                |
| Vault locator           | Derived id     | Webapp, HKDF of the salt              | Each holder of the invite, and the MetaLeX vault   | Vault index                                                   |
| Document key            | Derived secret | Webapp, HKDF of the salt              | Each holder of the invite                          | Not stored                                                    |
| Encrypted document blob | Ciphertext     | Creator's webapp, AES-256-GCM         | MetaLeX stores it; only salt holders decrypt it, MetaLeX among them during retention | MetaLeX vault                    |

The signing key of each party protects the account. The salt protects one agreement. Without the salt, a chain
observer cannot link the three kinds of nullifiers to each other or to an agreement.

### What goes onchain

The finalize tx was measured on a local network (see [README.md](README.md#verification)):

| Tx field                                    | Value for `finalize`                                                                   |
|---------------------------------------------|----------------------------------------------------------------------------------------|
| Nullifiers                                  | 6: the tx nullifier, one per party slot (authwit or padding), the finalized nullifier |
| Note hashes                                 | 0                                                                                      |
| Private logs                                | 0                                                                                      |
| Public logs                                 | 0                                                                                      |
| Fee payer                                   | The FPC address                                                                        |
| Expiration timestamp                        | `min(expiry, anchor + 1 day)`                                                          |
| Anchor block header, gas settings, gas used | Same for all calls to this function                                                    |

The number of nullifiers does not change with the number of parties. Each unused slot adds a padding nullifier. The
local network run measured 6 nullifiers for one party and for two parties.

## Mapping from the Solidity registry

Each row compares one concept. "Today" is `src/CyberAgreementRegistry.sol`. "Proposed" is this PoC.

| Concept                 | Today                                                                                   | Proposed                                                                                                                         |
|-------------------------|-----------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------|
| Template                | Today, stored onchain in `templates` (title, URI, field name arrays).                   | Proposed, an entry in the public MetaLeX catalog. The document includes it, and `terms_hash` commits to it.                      |
| Global and party values | Today, `string[]` arrays stored onchain.                                                | Proposed, fields in the encrypted document in the vault.                                                                         |
| Parties                 | Today, `address[]` stored onchain, plus `agreementsForParty`.                           | Proposed, a fixed array in the circuit input, the invite and the collector. Nothing onchain.                                     |
| Agreement id            | Today, `keccak256` over creator, template, values, parties, expiry.                     | Proposed, Poseidon2 over `terms_commitment`, expiry and parties. No creator role.                                                |
| Create                  | Today, `createBoundContract` or `createBoundContractAndSignFor` stores the agreement.   | Proposed, nothing onchain. The creator puts the document in the vault and shares the invite.                                     |
| Signature               | Today, an EIP-712 ECDSA signature for each party, checked onchain by `signContract`.    | Proposed, a private authwit for each party, made offchain. `finalize` checks each authwit, and an authwit nullifier records it.  |
| Relayer                 | Today, any relayer submits a signature with `...For`. `delegations` lets a delegate sign. | Proposed, any account can send `finalize` with the authwits. The MetaLeX settler does this.                                     |
| Finalize                | Today, the last signature sets `finalized`, or the finalizer calls `finalizeContract`.  | Proposed, one `finalize` tx after all parties signed. The finalized nullifier records it.                                        |
| Signing time            | Today, `signedAt` stores the time of each signature.                                    | Proposed, the block of the finalize tx gives the time for all parties. Only the collector knows when each party signed.         |
| Duplicate finalize      | Today, `ContractAlreadyFinalized` checks storage.                                       | Proposed, a second finalize gives the same finalized nullifier, so the network rejects the tx.                                   |
| Expiry                  | Today, `block.timestamp` checks.                                                        | Proposed, `set_expiration_timestamp(expiry)`. The network drops the finalize tx after the expiry.                                || Yes                                    
| Status                  | Today, `isFinalized` and `hasSigned` read storage.                                      | Proposed, the `is_finalized` utility asks the node for the finalized nullifier.                                                  |
| Events                  | Today, public `ContractCreated`, `AgreementSigned` and `ContractFinalized` logs.        | Proposed, no events. A holder of the invite reads the status from the chain.                                                     |
| Gas                     | Today, the signer or a relayer pays ETH.                                                | Proposed, the MetaLeX FPC pays the fee of the finalize tx.                                                                       |

Not in this PoC: void, open party slots, secret hash, finalizer, signer conditions, escrow signatures.

## MetaLeX privacy data layer

MetaLeX runs five services and one KMS key. Only the invite cache gets the salt, and only for the retention period. The others
never get the salt, the terms or the document text.

### Signature collector

- At onboarding, the webapp gives the collector the address, the account instance and the signing public key of
  the user. These are public data. The settler needs them to run the authwit check of the account.
- The creator's webapp gives the collector the `Agreement` struct. The struct holds no salt.
- Each party's webapp gives the collector one authwit. The collector shows which parties signed.
- When all parties signed, the collector gives the struct and the authwits to the settler.

### Settler

- The settler is a MetaLeX account in its own wallet and PXE.
- For each party, the settler registers the account instance and stores the signing public key. The account
  contract checks that key against its `immutables_hash`. No secret of the party is needed.
- The settler sends `finalize` with the authwits, and adds the party addresses as PXE scopes. A scope lets the PXE
  read the key that it stored for that address. It gives no access to party keys.
- The authwit check of the account must read no private state of the owner. The initializerless Schnorr account
  meets this. An account that keeps its signing key in a private note does not, because only the owner can read
  that note.

### Document vault

- The webapp encrypts the document with the document key and uploads it at the vault locator.
- The vault cannot compute the agreement id, because it does not have the salt.
- The vault is also the backup of the legal text. A party needs the text to know what it signed.

### Invite cache

- The webapp gives the cache each invite of the user. The cache gives an invite back only to a signed-in party of
  that agreement.
- With an invite and the vault blob, MetaLeX can read the whole agreement. Users accept this trust for the
  retention period.
- The cache deletes each invite at the end of the retention period. After that, MetaLeX cannot read the agreement.
- The cache encrypts each invite with AES-256-GCM and a random IV before it writes the row. The key is in a key
  management service (KMS), not in the database. Only the cache server role can ask the KMS to decrypt. The KMS
  logs each decrypt.
- The database also encrypts its storage, but that protects only against a stolen disk or backup. The database
  gives plaintext rows to each connection with valid credentials. The cache encryption makes a database copy give
  only ciphertext.
- The cache encryption does not stop MetaLeX. The cache server can decrypt, because it must give the invite back to
  the user.

### Fee payer contract

- The FPC is an onchain contract on Aztec. MetaLeX deploys it and funds it with fee juice. Its balance is public
  state.
- The FPC pays the fee of the finalize tx, so no user needs a fee token. The tx shows the FPC as fee payer.
- The local network test uses the canonical SponsoredFPC. A mainnet FPC must limit its use, for example to the
  settler account. This PoC does not include that FPC.

### Node RPC

Each PXE asks a node for nullifier status, tx effects and block data. The node sees these queries. MetaLeX can run a
node for its users. A user who wants more privacy can use a separate node.

## Privacy analysis

### PII: who can see what

Each row is one kind of personal data. Each cell says what that viewer can see of it. "Party" means each party of
the agreement, on its own device. The webapp runs in the browser of the user, so it counts as the user's device.

| Personal data                                  | Stored at rest                                    | Party                                   | Auditor with invite | MetaLeX invite cache, during retention | MetaLeX collector and settler        | MetaLeX vault                     | Node operator                               | Chain observer, sequencer                        |
|------------------------------------------------|---------------------------------------------------|-----------------------------------------|---------------------|----------------------------------------|--------------------------------------|-----------------------------------|---------------------------------------------|--------------------------------------------------|
| Party values (names and other party fields)    | Vault, as ciphertext                              | Yes                                     | Yes                 | Yes, with the vault blob               | No                                   | Ciphertext and its size only      | No                                          | No                                               |
| Global values (deal terms)                     | Vault, as ciphertext                              | Yes                                     | Yes                 | Yes, with the vault blob               | No                                   | Ciphertext and its size only      | No                                          | No                                               |
| Party addresses (who contracts with whom)      | Collector; the invite; invite cache, encrypted    | Yes, for its own agreements             | Yes                 | Yes                                    | Yes                                  | No                                | No                                          | No                                               |
| Account instance and signing public key        | Collector; settler PXE                            | Its own only                            | No                  | No                                     | Yes, for each onboarded user         | No                                | No                                          | No                                               |
| Expiry                                         | Collector; the invite; invite cache, encrypted    | Yes                                     | Yes                 | Yes                                    | Yes                                  | No                                | No                                          | Only when it is less than one day after the anchor |
| Time that each party signed                    | Collector, until finalize                         | Its own only                            | No                  | No                                     | Yes                                  | No                                | No                                          | No                                               |
| Finalize status and time                       | Nullifier tree, not linkable without the salt     | Yes                                     | Yes                 | Yes                                    | Yes                                  | No                                | A lookup of a nullifier, not the agreement  | That a tx happened, not the agreement            |
| IP address and request times                   | Logs of each service                              | Its own only                            | Its own only        | Of the webapps that put or get invites | Of the webapps that post to it       | Of the webapps that upload or fetch | Of each PXE that queries it, and of the settler | No                                               |

Notes:

- No PII goes onchain. The chain keeps only nullifiers. Without the salt, nobody can link them to an agreement or a
  party.
- The salt is the access key to the PII of one agreement. A holder of the invite sees the same data as a party.
  A party controls who gets the invite. Nobody can take back an invite after a party shares it.
- MetaLeX can decrypt a vault blob only while it caches the invite. After the retention period, the "invite cache"
  column becomes "No" in each row. The collector, the settler and the vault never get the salt.
- MetaLeX runs both the vault and the collector. It can link a blob to an agreement by the IP and the time of the
  requests. This gives no plaintext.
- The diagrams show no MetaLeX login. If a login links an email or a name to an Aztec address, MetaLeX can link
  that person to each agreement, counterparty and signing time in the collector.
- To erase the PII of an agreement, MetaLeX deletes the vault blob, the cached invite and the collector entry. The nullifiers stay
  onchain, but they hold no PII. A party that keeps no copy of the document then loses access to it.

### Compared with the current webapp

"Today" is `metalex-webapp` at commit `a5d47d9b4` (2026-10-30), for agreements in `CyberAgreementRegistry`. Today
has two paths. A deal (an offer, a round or a corp formation) stores its values onchain. A private document
(cyberSign) stores the document in the MetaLeX database and puts only ids, hashes and party capacities onchain.
"Proposed" is this design.

The diagrams below put the two designs side by side. Each box has a tag that says what happens to it in a
migration:

- **keep:** the proposed design uses it as it is.
- **change:** the proposed design uses it, with a different job.
- **replace:** the proposed design uses a different component for the same job. The tag names it.
- **new:** the proposed design adds it.

Components:

```mermaid
flowchart LR
    subgraph Today["Today: metalex-webapp on EVM"]
        direction TB
        subgraph TUser["User device"]
            TApp["Webapp in browser<br/>PII: plaintext<br/>[change]"]
            TWallet["EVM wallet, Privy embedded or external<br/>[replace: Aztec account]"]
        end
        subgraph TMeta["MetaLeX services"]
            TServer["Webapp server<br/>holds ENCRYPTION_KEY, decrypts all PII<br/>[change: decrypts no PII]"]
            TDB[("Postgres database<br/>wrapped keys, encrypted documents<br/>[keep]")]
            TRelayer["Signing relayer<br/>EVM key in the server environment<br/>[replace: settler and FPC]"]
        end
        TPrivy["Privy<br/>login, links email to wallet<br/>[keep]"]
        subgraph TChain["EVM chain, public"]
            TReg["CyberAgreementRegistry<br/>parties, values, signatures, times<br/>values plaintext by default<br/>[keep for old agreements]"]
        end
        TApp -->|plaintext values to encrypt or decrypt| TServer
        TServer --> TDB
        TApp --> TPrivy
        TApp --> TWallet
        TWallet -->|signature, tx| TReg
        TServer --> TRelayer
        TRelayer -->|sponsored tx| TReg
    end
    subgraph Proposed["Proposed: Aztec"]
        direction TB
        subgraph PUser["User device"]
            PApp["Webapp in browser<br/>PII: plaintext, encrypts and decrypts locally<br/>[change]"]
            PWallet["Aztec wallet + PXE<br/>[new]"]
        end
        subgraph PMeta["MetaLeX services"]
            PLogin["Login, for example Privy<br/>[keep]"]
            PVault["Document vault<br/>PII: ciphertext only<br/>[new]"]
            PCache["Invite cache<br/>salt, during retention<br/>[new]"]
            PKMS["KMS<br/>invite cache key<br/>[new]"]
            PCollector["Collector and settler<br/>parties, signing times<br/>[new]"]
        end
        subgraph PChain["Aztec network"]
            PNode["Node RPC<br/>PXE IP, lookups"]
            PReg["CyberAgreementRegistry<br/>nullifiers only<br/>[new]"]
        end
        PApp --> PLogin
        PApp -->|ciphertext| PVault
        PApp -->|invite| PCache
        PCache --> PKMS
        PApp -->|authwit| PCollector
        PApp --> PWallet
        PWallet -->|read| PNode
        PCollector -->|finalize tx, FPC pays| PNode
        PNode --> PReg
    end
    Today ~~~ Proposed

    subgraph Legend
        direction TB
        LPlain[Red: can read plaintext PII]
        LCipher[Brown: holds encrypted PII only]
        LMeta[Blue: holds metadata about people, no document content]
        LNone[No color: holds no PII]
        LTag["Tag: what happens in a migration<br/>keep, change, replace, new"]
    end

    classDef piiPlain fill:#842029,stroke:#58151c,color:#fff
    classDef piiCipher fill:#664d03,stroke:#332701,color:#fff
    classDef piiMeta fill:#084298,stroke:#052c65,color:#fff
    class TApp,TServer,TReg,PApp,PCache,LPlain piiPlain
    class TDB,PVault,LCipher piiCipher
    class TRelayer,TPrivy,PLogin,PCollector,PNode,LMeta piiMeta
```

Secrets, keys and hashes:

```mermaid
flowchart LR
    subgraph Today["Today: metalex-webapp on EVM"]
        direction TB
        subgraph TEnv["Server environment"]
            TEK["ENCRYPTION_KEY<br/>[keep for old data]"]
        end
        subgraph TKeys["MetaLeX database"]
            TAK["Per-agreement key, wrapped<br/>[replace: salt]"]
            TCK["Company key, wrapped<br/>[keep for old documents]"]
            TDOC["Private document, sealed<br/>[change: moves to the vault]"]
        end
        subgraph TWal["User wallet"]
            TSIG["EVM signing key<br/>[replace: Aztec signing key]"]
        end
        subgraph TChain["EVM chain, public"]
            TSALT["Salt, public"]
            TAID["Agreement id<br/>keccak256 of template, salt,<br/>global values, parties"]
            TVAL["Deal party values<br/>plaintext by default,<br/>or AES-256-CBC ciphertext"]
            TGV["Deal global values, plaintext"]
            TSIGS["Parties, signatures, signing times"]
        end
        TEK -->|AES-256-CBC wraps| TAK
        TEK -->|AES-256-CBC wraps| TCK
        TAK -->|"AES-256-CBC, IV from agreement id"| TVAL
        TCK -->|AES-256-GCM, random IV| TDOC
        TSALT --> TAID
        TGV --> TAID
        TSIG -->|EIP-712 signs| TSIGS
    end
    subgraph Proposed["Proposed: Aztec"]
        direction TB
        subgraph PKMSBox["MetaLeX KMS"]
            PCK["Invite cache key<br/>[new]"]
        end
        subgraph PCacheBox["MetaLeX invite cache"]
            PCINV["Invite, encrypted<br/>during retention<br/>[new]"]
        end
        subgraph PWeb["Webapp, in browser memory"]
            PINV["Invite: salt, expiry, parties<br/>[new]"]
            PKEY["Document key<br/>HKDF of the salt"]
            PAID["agreement_id<br/>Poseidon2"]
        end
        subgraph PVaultBox["MetaLeX vault"]
            PBLOB["Encrypted document<br/>[new]"]
        end
        subgraph PWal["User wallet"]
            PSIG["Aztec signing key<br/>[new]"]
        end
        subgraph PCol["MetaLeX collector"]
            PAW["Authwits<br/>[new]"]
        end
        subgraph PChain["Aztec chain"]
            PNUL["Nullifiers only"]
        end
        PCK -->|AES-256-GCM encrypts| PCINV
        PINV -->|cached copy| PCINV
        PINV -->|HKDF| PKEY
        PKEY -->|AES-256-GCM, random IV| PBLOB
        PINV --> PAID
        PSIG -->|signs| PAW
        PAID --> PAW
        PAW -->|finalize| PNUL
    end
    Today ~~~ Proposed

    subgraph Legend
        direction TB
        LPlain[Red: can read plaintext PII]
        LCipher[Brown: holds encrypted PII only]
        LMeta[Blue: holds metadata about people, no document content]
        LNone[No color: holds no PII]
        LDerived[Dashed: computed when needed, not stored]
        LTag["Tag: what happens in a migration<br/>keep, change, replace, new"]
    end

    classDef derived stroke-dasharray: 5 5
    classDef piiPlain fill:#842029,stroke:#58151c,color:#fff
    classDef piiCipher fill:#664d03,stroke:#332701,color:#fff
    classDef piiMeta fill:#084298,stroke:#052c65,color:#fff
    class PKEY,PAID,LDerived derived
    class TVAL,TGV,TAK,TCK,TEK,PINV,PCINV,LPlain piiPlain
    class TDOC,PBLOB,LCipher piiCipher
    class TSIGS,TAID,PAW,LMeta piiMeta
```

| Personal data                    | Today                                                                                                                                                                                                                                                                                                  | Proposed                                                                                                       |
|----------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------|
| Party values (names, contacts)   | Today, a deal writes them onchain in `partyValues`. They are plaintext unless the user turns on encryption (`encryptionEnabledAtom` is `false` by default). Encrypted values use AES-256-CBC with a per-agreement key in the MetaLeX database. A private document keeps them in the encrypted document. | Proposed, only in the encrypted vault blob. Nothing onchain.                                                   |
| Global values (deal terms)       | Today, a deal writes them onchain in `globalValues` as plaintext. A private document puts its company or owner address, document SHA-256, template id and request id onchain as plaintext.                                                                                                              | Proposed, only in the encrypted vault blob. Nothing onchain.                                                   |
| Document file                    | Today, a private document is sealed with AES-256-GCM under a company key in the MetaLeX database.                                                                                                                                                                                                       | Proposed, sealed with AES-256-GCM under a key from the salt of the agreement, in the vault.                    |
| Party addresses                  | Today, public onchain (`getParties`, events). A private document also puts each party wallet and capacity onchain as JSON.                                                                                                                                                                            | Proposed, the collector, the invite and the invite cache. Nothing onchain.                                     |
| Signing times, finalize status   | Today, public onchain (`signedAt`, `AgreementSigned`, `ContractFinalized`).                                                                                                                                                                                                                             | Proposed, signing times only in the collector. Onchain, only a nullifier that nobody can link without the salt. |
| Who at MetaLeX can decrypt       | Today, the MetaLeX server can decrypt every encrypted value and document. It unwraps each per-agreement key and each company key with one server secret, `ENCRYPTION_KEY`.                                                                                                                              | Proposed, MetaLeX can decrypt an agreement only while the invite cache keeps its invite. No MetaLeX secret opens all agreements. |
| Top MetaLeX key                  | Today, `ENCRYPTION_KEY`, an environment variable of the server. It opens every agreement for as long as the data exists. Nothing logs its use.                                                                                                                                                        | Proposed, the invite cache key, in a KMS. It opens only the invites in the cache. The KMS logs each decrypt.   |
| Who outside MetaLeX can decrypt  | Today, nobody without the MetaLeX server. A party cannot decrypt its own encrypted values without MetaLeX.                                                                                                                                                                                             | Proposed, each holder of the invite, without MetaLeX.                                                          |

What can be migrated:

| Today                                             | Proposed                                                        | Migration                                                                                                   |
|---------------------------------------------------|-----------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------|
| Webapp in browser                                 | Webapp in browser                                               | Change. It encrypts, decrypts and hashes the document in the browser.                                       |
| Webapp server decrypts PII for parties            | Webapp server runs the vault, the collector and the invite cache | Change. The server stops decrypting PII, except the cached invites.                                         |
| Postgres database                                 | Postgres database                                               | Keep. The collector and the invite cache can use it. The vault can use it or a blob store.                  |
| Privy login                                       | Login for the invite cache                                      | Keep. The cache gives an invite only to a signed-in party.                                                  |
| `ENCRYPTION_KEY` in the server environment        | Invite cache key in a KMS                                       | Replace for new agreements. Keep `ENCRYPTION_KEY` to read old agreements.                                   |
| Per-agreement key in the database                 | Salt in the invite                                              | Replace. The webapp makes a new salt for each agreement.                                                    |
| `sealArtifact` (AES-256-GCM, random IV)           | Document encryption in the browser                              | Keep the pattern. Use the same cipher with the document key from the salt.                                  |
| AES-256-CBC deal values, IV from the agreement id | Nothing                                                         | Replace. Deal values go into the encrypted document.                                                        |
| EVM wallet and EIP-712 signature                  | Aztec account and authwit                                       | Replace. Each user needs an Aztec account. Counsel must confirm the authwit as a signature.                 |
| Signing relayer                                   | Settler and FPC                                                 | Replace. The settler sends one `finalize` tx for each agreement, and the FPC pays the fee.                  |
| EVM `CyberAgreementRegistry`                      | Aztec `CyberAgreementRegistry`                                  | New registry for new agreements. Old agreements stay on the EVM chain.                                      |

Old agreements stay public. A migration cannot remove data that is already on an EVM chain. It can only move new
agreements to the proposed design.

### What each viewer learns

| Viewer                                | What it learns                                                                                                                  | What it does not learn                                     |
|---------------------------------------|---------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------|
| Chain observer                        | That some tx emitted 6 nullifiers, its fee payer, its time, and an expiry when the expiry is less than one day after the anchor | Contract called, parties, party count, terms, agreement id |
| MetaLeX (invite cache)                | All data of each cached agreement, during the retention period                                                                  | Agreements after the retention period                      |
| MetaLeX (collector and settler)       | Parties, expiry, agreement id, who signed and when, the finalize status                                                         | Salt, terms, document text                                 |
| MetaLeX (vault)                       | Locator, blob size, upload and fetch times                                                                                      | Agreement id, parties, document text                       |
| MetaLeX (FPC)                         | That a sponsored tx happened                                                                                                    | Which function or user, from the FPC alone                 |
| Node operator                         | Nullifier lookups and tx hash lookups from a PXE, and the IP of the PXE                                                         | Terms or parties, unless it can link the lookups           |
| Counterparty, or auditor with invite  | All data of that agreement and its finalize status                                                                              | Other agreements of the parties                            |

Notes:

- A party can prove the agreement to a third party with the invite. The verifier opens the document, rebuilds the
  agreement id and checks the finalized nullifier onchain.
- The collector can link parties, because one agreement lists all of them.

## Limits and open items

- `MAX_PARTIES` is 4. More parties need more private calls in the finalize tx, or a commitment to the party list.
- A party cannot withdraw an authwit before the finalize tx. Only the expiry limits it. A void flow needs a registry
  function that a party can call to block the finalize.
- The settler works only with accounts whose authwit check reads no private state of the owner.
- The invite cache keeps an invite only for the retention period. After that, a user who lost the invite cannot
  open the document. The retention period and the cache are design items. The PoC does not include them.
- The MetaLeX FPC with use limits is a design item. The PoC uses the test SponsoredFPC.
- Counsel must confirm that an authwit is acceptable as an electronic signature. The PoC keeps no ECDSA signature
  artifact.
- The PoC is not deployed on Aztec mainnet. It has no independent review.
- No need to store "globalValues" and "partyValues" as string arrays in the canonical JSON. That was a legacy structure to fit EVM; we no longer subject to such limitation and a JSON can have dynamic structures. Find a more native way of storing the info
