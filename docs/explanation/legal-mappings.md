---
description: >-
  Which statutes and governing documents anchor the onchain register for
  Delaware corporations and LLCs, Cayman and BVI entities, English companies
  and funds.
---

# Legal mappings across jurisdictions

The contracts encode no jurisdiction. `CyberCorp` stores the entity type and
jurisdiction as configuration, and the same contracts serve a Delaware
C-corp, a Delaware LLC, a Cayman SPC, a BVI fund and an English company.
What changes from one regime to the next is the law that lets the entity
designate the onchain register and the document that does it.

Under any regime, the onchain register is the entity's legal record only
when two things hold. The governing law must let the entity's governing
documents designate an external record-keeping system as authoritative, and
the documents must in fact do so, identifying the cyberCORP contracts by
address or by registry reference. Most developed corporate, LLC, partnership
and fund regimes allow the designation. Writing it is a drafting task, and
for Delaware corporations formed through the cyberCORPs app, MetaLeX's form
bylaws do it.

## Delaware corporations

Delaware is the worked example. Each protocol object relies on a DGCL
provision:

| Protocol object | DGCL provision |
|---|---|
| Onchain register | §224: records, the stock ledger included, may be kept on electronic networks or databases, distributed ones among them |
| Classes and series, authorized share counts | §151 |
| Ledger Entry Tokens (LETs) for uncertificated shares | §158 permits uncertificated shares. The holder notice §§151(f), 156, 202(a) and 218(a) require can be carried in LET metadata where the bylaws allow it, as MetaLeX-form bylaws do |
| Restriction legends | §202 |
| Scrip | §155 |
| Stockholder list | §219, drawn from the stock ledger |

MetaLeX-form bylaws make the onchain system the stock ledger for the shares
the board designates as Tokenized Shares and keep any other shares on an
offchain stock ledger. The two parts together are the corporation's stock
ledger. [Constitutive vs. pointer tokenization](constitutive-vs-pointer.md)
describes that structure.

## Other entities and jurisdictions

| Entity | Document that designates the register | What the LET fields map to |
|---|---|---|
| Delaware LLC | Operating agreement | Whatever the operating agreement requires for each membership-interest entry. Delaware LLC law gives operating agreements broad latitude over how interests are recorded, so no §224 analogue is needed. |
| Cayman LLC or SPC | Constitutional documents (memorandum and articles, LLC agreement) | The register the constitutional documents define. Cayman LLC and SPC statutes accommodate the designation by contract. |
| BVI company or fund | Articles of association, or the fund's constitutional documents | The share-register requirements of the BVI Business Companies Act 2004, or the fund's constitutional equivalents. |
| English company | Articles of association | The register-of-members requirements of Companies Act 2006 §113. CREST's regime for uncertificated shares is separate. For the purposes of the constitutional documents, the cyberCORP register is the register. |
| Fund (LP, LLC or other fund interests) | Partnership agreement or fund LPA | The interest entries the agreement requires. |

LLC membership interests use the same `ShareExtension` as stock, configured
for the LLC's class structure. A Cayman SPC uses `MetaDAOFactory`, or a
custom factory, to model its segregated portfolios as sub-entities that share
a parent cyberCORP. A fund can model capital commitments, calls and
distributions with the existing contracts: a LET for each LP unit, scrip for
a tradable fund interest, and the `DealManager` for capital calls.

## See also

* [Regulatory context](regulatory-context.md)
* [Agreement templates](../reference/templates.md)
* [Factories](../reference/factories.md)
