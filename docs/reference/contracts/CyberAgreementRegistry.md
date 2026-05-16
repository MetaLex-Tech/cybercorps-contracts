# CyberAgreementRegistry

**CyberAgreementRegistry** is the onchain anchor for cybernetic legal
agreements. Templates, executed agreements, party signatures, and escrow
linkage all live here.

* **Source:** [`src/CyberAgreementRegistry.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberAgreementRegistry.sol)
* **Proxy pattern:** UUPS

## Responsibilities

* Register agreement templates (content URI + content hash + optional schema).
* Instantiate executed agreements (`proposeAgreement`).
* Collect EIP-712 signatures from each party (`signAgreement`).
* Emit `AgreementExecuted` once all required signatures are gathered.
* Provide bidirectional links from agreements to cyberCERTs and deals (so a
  cert can know its governing instrument).

## Selected public interface

```solidity
function registerTemplate(TemplateData calldata) external returns (uint256 templateId);
function proposeAgreement(AgreementProposal calldata) external returns (uint256 agreementId);
function signAgreement(uint256 agreementId, bytes calldata signature) external;
function getAgreement(uint256 agreementId) external view returns (Agreement memory);
```

## See also

* [How-to: Sign a cyberAgreement](../../how-to/sign-a-cyberagreement.md)
* [Agreement templates](../templates.md)
