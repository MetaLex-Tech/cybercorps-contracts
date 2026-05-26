# Legal mappings across jurisdictions

cyberCORPs treats entity type and jurisdiction as *configuration*. The same
contract primitives serve a Delaware C-corp, a Delaware LLC, a Cayman SPC,
a BVI fund, and an English company. The mappings below show what each
field on a cyberCERT or cyberCORP means under each regime.

## Delaware C-corp (the worked example)

| Protocol object | Statutory hook |
|---|---|
| Onchain register | DGCL §224 (books and records in any form) |
| Authorized share counts | DGCL §151 (classes / series) |
| cyberSCRIP | DGCL §155 (scrip authority) |
| Cert metadata (holder, units, class, signatures) | DGCL §158 (share-certificate requirements) |
| Restrictive legends | DGCL §202 |
| Stockholder list rights | DGCL §219 (the register is the list) |

The entity's certificate of incorporation and bylaws designate the onchain
contract system as authoritative.

## Delaware LLC

* The operating agreement designates the onchain register as authoritative.
  Delaware LLC law gives operating agreements broad latitude to define
  member-interest accounting; there is no "§224 analogue" needed.
* Membership interests use the same `ShareExtension` (configured per the
  LLC's class structure).
* Cert fields map to whatever the operating agreement requires for each
  membership-interest entry.

## Cayman LLC / SPC

* The constitutional documents (M&AA, LLC agreement) designate the onchain
  register as authoritative. Cayman LLC and SPC statutes accommodate this
  contractually.
* SPC structures use `MetaDAOFactory` (or a custom factory) to model
  segregated portfolios as logical sub-entities sharing the same parent
  cyberCORP.

## BVI fund / company

* Articles of association or the fund's constitutional documents anchor the
  onchain register.
* Cert fields map to the BVI Business Companies Act 2004 share-register
  requirements, or to the fund's constitutional analogues.

## English company

* Articles of association designate the onchain register as authoritative.
* Cert fields map to the Companies Act 2006 §113 register-of-members
  requirements.
* Note that uncertificated shares in CREST are a separate regime; the
  cyberCORP register is *the* register for purposes of the constitutional
  documents.

## Funds (LP / LLC / fund interests)

* The partnership agreement / fund LPA designates the onchain register as
  authoritative.
* Capital commitments, calls, and distributions can be modelled using the
  existing primitives (cyberCERT for the LP unit, cyberSCRIP for tradable
  fund interest, `DealManager` for capital calls).

## The common substrate

Under every regime, two things must be true for the protocol to apply:

1. The governing law permits the entity's constitutional documents to
   designate an external record-keeping system as authoritative.
2. The constitutional documents in fact do so, and identify the cyberCORP
   contract suite (by addresses or by registry reference).

Most developed corporate, LLC, partnership, and fund regimes satisfy (1).
The second is a drafting task, addressed by MetaLeX's template library.

## See also

* [Constitutive vs. pointer tokenization](constitutive-vs-pointer.md)
* [Regulatory context](regulatory-context.md)
* [Agreement templates](../reference/templates.md)
