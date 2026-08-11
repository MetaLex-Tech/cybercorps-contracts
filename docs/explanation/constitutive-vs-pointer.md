# Constitutive vs. pointer tokenization

Most "tokenized securities" today are **pointer tokens**. The official cap
table lives at a transfer agent, on Carta, or in a law firm's filing cabinet.
The chain is a notification layer. Onchain transfers are not the legal
transfer; they are a request to update an offchain register that the issuer
or its agents may decline to honour. The blockchain does no essential work
and could be removed without changing the underlying legal reality.

cyberCORPs takes the opposite approach.

## The constitutive move

Each cyberCORP's governing documents — certificate of incorporation and
bylaws, operating agreement, articles of association, partnership agreement,
fund constitutional documents, or analogous instrument under the entity's
governing law — **designate the onchain contract system as the entity's
official register of holders**, with the fungible scrip layer authorised by
the same instruments.

The legal state-transition function and the chain state-transition function
are unified: **changing onchain state is the legal change**. There is no
offchain register to reconcile against, no transfer agent to instruct, and no
possibility of the chain and the legal record diverging.

## Why this is possible under Delaware law

* **DGCL §224** explicitly permits *any* books and records, including the
  stock ledger, to be kept in any form, including a blockchain, provided the
  records can be converted to clearly legible paper form and provide
  information required by other DGCL sections (§158 share-certificate
  requirements, §219 stockholder list rights, etc.).
* **DGCL §155** authorises scrip — meaning the cyberSCRIP layer is itself
  authorised as a form of the security, not as a synthetic derivative.
* **DGCL §158** sets the information that a certificate must convey (issuer
  name, holder name, units, class, restrictions, signatures). cyberCERT
  metadata encodes all of these directly.
* **DGCL §202** permits restrictive legends; cyberCERT extensions encode
  them.
* **DGCL §219** governs stockholder-list rights; the cyberCORP register is
  queryable onchain by anyone and can be exported to any required format.

## Why this is possible elsewhere

Delaware is the most fully worked-out reference. Comparable provisions or
contractual workarounds exist under Delaware LLC law (operating agreement
autonomy), Cayman corporate and SPC regimes, BVI corporate law, English
corporate law, and partnership / fund statutes.

The protocol does not assume any specific statute. It assumes only that the
entity's governing law permits the onchain register to be designated as
authoritative through the entity's governing documents — and offers
entity-type and jurisdiction as configuration on the `CyberCorp` contract.

## What this lets you do

* A cyberCERT is your interest in the entity *as it lives in the official
  records*. Not a pointer.
* A cyberSCRIP is *the same security in scrip form*. Not a wrapper, not a
  derivative, not a receipt for a receipt.
* You can hand a regulator, an auditor, or a court the chain itself and ask
  what the entity's holder register is. The answer is in the bytes.

This is the basis of every other design decision the protocol makes.

## Further reading

* MetaLeX, ["What Is Slop Tokenization and Why Is It Bad?"](https://metalex.substack.com/)
* MetaLeX, ["5 Ways of Tokenizing Securities (& One Which Is Best)"](https://x.com/lex_node/status/2030322576208068616)
* SEC, January 2026 Joint Staff Statement on Tokenized Securities.
