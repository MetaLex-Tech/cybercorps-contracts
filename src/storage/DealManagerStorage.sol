/*    .o.                                                                                             
     .888.                                                                                            
    .8"888.                                                                                           
   .8' `888.                                                                                          
  .88ooo8888.                                                                                         
 .8'     `888.                                                                                        
o88o     o8888o                                                                                       
                                                                                                      
                                                                                                      
                                                                                                      
ooo        ooooo               .             ooooo                  ooooooo  ooooo                    
`88.       .888'             .o8             `888'                   `8888    d8'                     
 888b     d'888   .ooooo.  .o888oo  .oooo.    888          .ooooo.     Y888..8P                       
 8 Y88. .P  888  d88' `88b   888   `P  )88b   888         d88' `88b     `8888'                        
 8  `888'   888  888ooo888   888    .oP"888   888         888ooo888    .8PY888.                       
 8    Y     888  888    .o   888 . d8(  888   888       o 888    .o   d8'  `888b                      
o8o        o888o `Y8bod8P'   "888" `Y888""8o o888ooooood8 `Y8bod8P' o888o  o88888o                    
                                                                                                      
                                                                                                      
                                                                                                      
  .oooooo.                .o8                            .oooooo.                                     
 d8P'  `Y8b              "888                           d8P'  `Y8b                                    
888          oooo    ooo  888oooo.   .ooooo.  oooo d8b 888           .ooooo.  oooo d8b oo.ooooo.      
888           `88.  .8'   d88' `88b d88' `88b `888""8P 888          d88' `88b `888""8P  888' `88b     
888            `88..8'    888   888 888ooo888  888     888          888   888  888      888   888     
`88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 .o. 
 `Y8bood8P'      .8'      `Y8bod8P' `Y8bod8P' d888b     `Y8bood8P'  `Y8bod8P' d888b     888bod8P' Y8P 
             .o..P'                                                                     888           
             `Y8P'                                                                     o888o          
_______________________________________________________________________________________________________

All software, documentation and other files and information in this repository (collectively, the "Software")
are copyright MetaLeX Labs, Inc., a Delaware corporation.

All rights reserved.

The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published, 
distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
mechanical, including photocopying, recording, or by any information storage and retrieval system, 
except with the express prior written permission of the copyright holder.*/

pragma solidity 0.8.28;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/token/ERC1155/IERC1155.sol";
import "../interfaces/IIssuanceManager.sol";
import "../interfaces/ICyberAgreementRegistry.sol";
import "../interfaces/ICyberCorp.sol";
import "../interfaces/ILedgerEntryToken.sol";
import "../interfaces/IDealManagerFactory.sol";
import "../interfaces/ICondition.sol";
import "../CyberCorpConstants.sol";
import "./DealManagerFactoryStorage.sol";
import {LexScrowStorage, Escrow, Token, TokenType, EscrowStatus} from "./LexScrowStorage.sol";
import {IDealManagerStorage} from "../interfaces/IDealManagerStorage.sol";
import {ILexScrowStorage} from "../interfaces/ILexScrowStorage.sol";

/// @title DealManagerStorage
/// @notice Storage library + legacy deal lifecycle logic (propose / sign / finalize / void) for DealManager.
/// @dev Uses the unstructured storage pattern to manage deal-related data. The logic functions are `public`
/// so the library is deployed separately and linked; DealManager calls them via DELEGATECALL (msg.sender /
/// storage context preserved), keeping that logic out of DealManager's bytecode (EIP-170).
/// `proposeAndSignDeal` / `proposeAndSignNewCertsDeal` deliberately live in DealManager (not here):
/// keeping `proposeAndSignDeal` out of this library stops the via-ir Yul optimizer from inlining `proposeDeal`
/// into it and cause stack overflow.
library DealManagerStorage {
    using SafeERC20 for IERC20;

    // Storage slot for our struct
    bytes32 constant STORAGE_POSITION = keccak256("cybercorp.deal.manager.storage.v1");

    /// @notice Certificate data structure for creating new certificates
    struct CyberCertData {
        string name;
        string symbol;
        string uri;
        SecurityClass securityClass;
        SecuritySeries securitySeries;
        address extension;
        /// @notice Series-scope payload encoded by `extension`.
        bytes seriesData;
        string[] defaultLegend;
    }

    /// @notice Main storage layout struct that holds all deal manager data
    /// @dev Uses unstructured storage pattern to avoid storage collisions
    struct DealManagerData {
        /// @notice Reference to the issuance manager contract
        IIssuanceManager issuanceManager;
        address upgradeFactory;
        
        /// @notice Mapping from agreement IDs to their counter party values
        mapping(bytes32 => string[]) counterPartyValues;
    }

    /// @notice Retrieves the storage reference for the DealManagerData struct
    /// @dev Uses assembly to compute the storage position
    /// @return ds Reference to the DealManagerData struct in storage
    function dealManagerStorage() internal pure returns (DealManagerData storage ds) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    /// @notice Retrieves counter party values for a specific agreement
    /// @dev Accesses the storage mapping directly
    /// @param agreementId The unique identifier of the agreement
    /// @return string[] Array of counter party values
    function getCounterPartyValues(bytes32 agreementId) internal view returns (string[] storage) {
        return dealManagerStorage().counterPartyValues[agreementId];
    }

    /// @notice Retrieves the current issuance manager
    /// @dev Returns the stored issuance manager reference
    /// @return IIssuanceManager The current issuance manager contract
    function getIssuanceManager() internal view returns (IIssuanceManager) {
        return dealManagerStorage().issuanceManager;
    }

    /// @notice Sets counter party values for a specific agreement
    /// @dev Updates the storage mapping with new values
    /// @param agreementId The unique identifier of the agreement
    /// @param values Array of counter party values to store
    function setCounterPartyValues(bytes32 agreementId, string[] memory values) internal {
        dealManagerStorage().counterPartyValues[agreementId] = values;
    }

    /// @notice Updates the issuance manager reference
    /// @dev Sets a new issuance manager contract address
    /// @param _issuanceManager Address of the new issuance manager contract
    function setIssuanceManager(address _issuanceManager) internal {
        dealManagerStorage().issuanceManager = IIssuanceManager(_issuanceManager);
    }

    function setUpgradeFactory(address _upgradeFactory) internal {
        dealManagerStorage().upgradeFactory = _upgradeFactory;
    }

    function getUpgradeFactory() internal view returns (address) {
        return dealManagerStorage().upgradeFactory;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Legacy deal proposal (linked logic; called via delegatecall)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Proposes a new deal: creates the agreement + certificates and sets up the escrow
    /// @dev Access control (onlyOwner) is enforced by the DealManager wrapper that delegatecalls here.
    function proposeDeal(
        address[] memory _certPrinterAddress,
        address _paymentToken,
        uint256 _paymentAmount,
        bytes32 _templateId,
        uint256 _salt,
        string[] memory _globalValues,
        address[] memory _parties,
        CertificateDetails[] memory _certDetails,
        string[][] memory _partyValues,
        address[] memory conditions,
        bytes32 secretHash,
        uint256 expiry
    ) public returns (bytes32 agreementId, uint256[] memory certIds) {
        agreementId = ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).createContract(_templateId, _salt, _globalValues, _parties, _partyValues, secretHash, address(this), expiry);

        Token[] memory corpAssets = new Token[](_certDetails.length);
        certIds = new uint256[](_certDetails.length);
        for(uint256 i = 0; i < _certDetails.length; i++) {
            certIds[i] = getIssuanceManager().createCert(_certPrinterAddress[i], address(this), _certDetails[i]);
            corpAssets[i] = Token(TokenType.ERC721, _certPrinterAddress[i], certIds[i], 1, false);
        }

        Token[] memory buyerAssets = new Token[](1);
        buyerAssets[0] = Token(TokenType.ERC20, _paymentToken, 0, _paymentAmount, true); // Will be used as fee token

        Escrow memory newEscrow = Escrow({
            agreementId: agreementId,
            counterParty: _parties[1],
            corpAssets: corpAssets,
            buyerAssets: buyerAssets,
            signature: "",
            expiry: expiry,
            status: EscrowStatus.PENDING
        });

        LexScrowStorage.setEscrow(agreementId, newEscrow);

        //set conditions
        for(uint256 i = 0; i < conditions.length; i++) {
            LexScrowStorage.addConditionToEscrow(agreementId, ICondition(conditions[i]));
        }

        emit IDealManagerStorage.DealProposed(
            agreementId,
            _certPrinterAddress,
            certIds,
            _paymentToken,
            _paymentAmount,
            _templateId,
            LexScrowStorage.getCorp(),
            LexScrowStorage.getDealRegistry(),
            _parties,
            conditions,
            secretHash > 0
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Deal lifecycle (linked logic; called via delegatecall)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Signs a deal and processes payment
    /// @dev Access modifiers (if any) are carried by the DealManager wrapper that delegatecalls here.
    function signDealAndPay(
        address signer,
        bytes32 agreementId,
        bytes memory signature,
        string[] memory partyValues,
        bool _fillUnallocated,
        string memory name,
        string memory secret
    ) public {
        if (!LexScrowStorage.hasPrimaryEscrow(agreementId)) revert LexScrowStorage.DealDoesNotExist();
        address registry = LexScrowStorage.getDealRegistry();
        if(ICyberAgreementRegistry(registry).isVoided(agreementId)) revert LexScrowStorage.DealVoided();
        if(ICyberAgreementRegistry(registry).isFinalized(agreementId)) revert LexScrowStorage.DealAlreadyFinalized();
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);
        if(escrow.status != EscrowStatus.PENDING) revert IDealManagerStorage.DealNotPending();
        // expiry == 0 means no deadline (same rule as the registry and voidExpiredDeal)
        if(escrow.expiry > 0 && escrow.expiry < block.timestamp) revert LexScrowStorage.DealExpired();

        string[] storage counterPartyCheck = getCounterPartyValues(agreementId);
        if(counterPartyCheck.length > 0) {
            if (keccak256(abi.encode(counterPartyCheck)) != keccak256(abi.encode(partyValues))) revert IDealManagerStorage.CounterPartyValueMismatch();
        }
        else {
            setCounterPartyValues(agreementId, partyValues);
        }

        ICyberAgreementRegistry(registry).signContractFor(signer, agreementId, partyValues, signature, _fillUnallocated, secret);
        LexScrowStorage.updateEscrow(agreementId, signer, name);
        LexScrowStorage.handleCounterPartyPayment(agreementId);
    }

    /// @notice Signs and finalizes a deal in one call
    /// @dev Access modifiers (if any) are carried by the DealManager wrapper that delegatecalls here.
    function signAndFinalizeDeal(
        address signer,
        bytes32 agreementId,
        string[] memory partyValues,
        bytes memory signature,
        bool _fillUnallocated,
        string memory name,
        string memory secret
    ) public {
        if (!LexScrowStorage.hasPrimaryEscrow(agreementId)) revert LexScrowStorage.DealDoesNotExist();
        address registry = LexScrowStorage.getDealRegistry();
        if(ICyberAgreementRegistry(registry).isVoided(agreementId)) revert LexScrowStorage.DealVoided();
        if(ICyberAgreementRegistry(registry).isFinalized(agreementId)) revert LexScrowStorage.DealAlreadyFinalized();
        if(LexScrowStorage.getEscrow(agreementId).status != EscrowStatus.PENDING) revert IDealManagerStorage.DealNotPending();

        string[] storage counterPartyCheck = getCounterPartyValues(agreementId);
        if(counterPartyCheck.length > 0) {
            if (keccak256(abi.encode(counterPartyCheck)) != keccak256(abi.encode(partyValues))) revert IDealManagerStorage.CounterPartyValueMismatch();
        } else {
            setCounterPartyValues(agreementId, partyValues);
        }

        if (!ICyberAgreementRegistry(registry).hasSigned(agreementId, signer)) {
            // Not signed in registry yet; enforce local consistency and then sign
            ICyberAgreementRegistry(registry).signContractFor(signer, agreementId, partyValues, signature, _fillUnallocated, secret);
        } else {
            // Already signed in registry; fetch values recorded in the registry and ensure consistency
            string[] memory registryValues = ICyberAgreementRegistry(registry).getSignerValues(agreementId, signer);
            if (keccak256(abi.encode(registryValues)) != keccak256(abi.encode(partyValues))) revert IDealManagerStorage.CounterPartyValueMismatch();
        }

        LexScrowStorage.updateEscrow(agreementId, signer, name);
        if(!LexScrowStorage.conditionCheck(agreementId)) revert ILexScrowStorage.AgreementConditionsNotMet();
        LexScrowStorage.handleCounterPartyPayment(agreementId);
        finalizeDeal(agreementId);
    }

    /// @notice Finalizes a primary deal (checks signatures/conditions, settles escrow)
    /// @dev nonReentrant is carried by the DealManager wrapper that delegatecalls here.
    function finalizeDeal(bytes32 agreementId) public {
        if (!LexScrowStorage.hasPrimaryEscrow(agreementId)) revert LexScrowStorage.DealDoesNotExist();

        address registry = LexScrowStorage.getDealRegistry();
        if (ICyberAgreementRegistry(registry).isVoided(agreementId)) revert LexScrowStorage.DealVoided();
        if (ICyberAgreementRegistry(registry).isFinalized(agreementId)) revert LexScrowStorage.DealAlreadyFinalized();
        if (!ICyberAgreementRegistry(registry).allPartiesSigned(agreementId)) revert LexScrowStorage.DealNotFullySigned();

        if (LexScrowStorage.getEscrow(agreementId).status != EscrowStatus.PAID) revert LexScrowStorage.DealNotPaid();
        if (!LexScrowStorage.conditionCheck(agreementId)) revert ILexScrowStorage.AgreementConditionsNotMet();
        ICyberAgreementRegistry(registry).finalizeContract(agreementId);
        LexScrowStorage.finalizeEscrow(agreementId);

        emit IDealManagerStorage.DealFinalized(
            agreementId,
            msg.sender,
            LexScrowStorage.getCorp(),
            registry,
            false
        );
    }

    /// @notice Voids an expired primary deal
    /// @dev nonReentrant is carried by the DealManager wrapper that delegatecalls here.
    function voidExpiredDeal(bytes32 agreementId, address signer, bytes memory signature) public {
        if (!LexScrowStorage.hasPrimaryEscrow(agreementId)) revert LexScrowStorage.DealDoesNotExist();

        address registry = LexScrowStorage.getDealRegistry();
        Escrow storage deal = LexScrowStorage.getEscrow(agreementId);
        // expiry == 0 means no deadline (mirrors the registry's void semantics): such deals never
        // expire, so treating zero as expired here would tear down the escrow while the registry
        // agreement stays live — voiding them requires signToVoid (unanimous) instead.
        if (deal.expiry == 0 || block.timestamp <= deal.expiry) revert IDealManagerStorage.DealNotExpired();
        ICyberAgreementRegistry(registry).voidContractFor(agreementId, signer, signature);
        _voidCorpCerts(deal);
        if (deal.status == EscrowStatus.PAID)
            // Interaction: payment
            LexScrowStorage.voidAndRefund(agreementId);
        else if (deal.status == EscrowStatus.PENDING)
            // Effect: update status
            LexScrowStorage.voidEscrow(agreementId);
    }

    /// @notice Revokes a pending deal
    /// @dev nonReentrant is carried by the DealManager wrapper that delegatecalls here.
    ///      If this request tips the registry agreement into voided (e.g. the sole-signer proposer
    ///      revokes), the same teardown as signToVoid must run here: voidContractFor rejects repeat
    ///      requesters, so no later signToVoid could clean up and the escrow would be stranded
    ///      PENDING with its corp certificates still live.
    function revokeDeal(bytes32 agreementId, address signer, bytes memory signature) public {
        if (!LexScrowStorage.hasPrimaryEscrow(agreementId)) revert LexScrowStorage.DealDoesNotExist();
        if(msg.sender != signer) revert IDealManagerStorage.CounterPartyValueMismatch();
        Escrow storage deal = LexScrowStorage.getEscrow(agreementId);
        if(deal.status != EscrowStatus.PENDING) revert IDealManagerStorage.DealNotPending();

        address registry = LexScrowStorage.getDealRegistry();
        ICyberAgreementRegistry(registry).voidContractFor(agreementId, signer, signature);
        // The agreement is only voided once enough parties have requested; until then there is nothing to tear down.
        if (!ICyberAgreementRegistry(registry).isVoided(agreementId)) return;

        _voidCorpCerts(deal);
        // Effect: update status (the deal is PENDING per the guard above, so there is no payment to refund)
        LexScrowStorage.voidEscrow(agreementId);
    }

    /// @notice Signs to void a deal; refunds if the deal was paid
    /// @dev nonReentrant is carried by the DealManager wrapper that delegatecalls here.
    ///      When mutual void succeeds on a PAID deal, voids escrowed corp ERC721s (same teardown as
    ///      voidExpiredDeal) before refunding — otherwise certs stay locked and voidExpiredDeal cannot
    ///      clean up because every party is already in voidRequestedBy.
    function signToVoid(bytes32 agreementId, address signer, bytes memory signature) public {
        // Check: status
        if (!LexScrowStorage.hasPrimaryEscrow(agreementId)) revert LexScrowStorage.DealDoesNotExist();
        if(msg.sender != signer) revert IDealManagerStorage.CounterPartyValueMismatch();

        // Effect: update status
        address registry = LexScrowStorage.getDealRegistry();
        ICyberAgreementRegistry(registry).voidContractFor(agreementId, signer, signature);
        // The agreement is only voided once enough parties have signed; until then there is nothing to tear down.
        if (!ICyberAgreementRegistry(registry).isVoided(agreementId)) return;

        Escrow storage deal = LexScrowStorage.getEscrow(agreementId);
        _voidCorpCerts(deal);
        if (deal.status == EscrowStatus.PAID)
            // Interaction: payment
            LexScrowStorage.voidAndRefund(agreementId);
        else if (deal.status == EscrowStatus.PENDING)
            // Effect: update status
            LexScrowStorage.voidEscrow(agreementId);
    }

    /// @notice Sync the escrow of a deal whose agreement was voided externally, refunding if paid
    /// @dev nonReentrant is carried by the DealManager wrapper that delegatecalls here.
    ///      Handles PENDING as well as PAID escrows: parties can void the agreement directly in the
    ///      registry before payment, and requiring PAID here would leave that escrow stranded with
    ///      its corp certificates still live (voidAndRefund reverts EscrowNotPaid).
    function refundVoidedDeal(bytes32 agreementId) public {
        if (!LexScrowStorage.hasPrimaryEscrow(agreementId)) revert LexScrowStorage.DealDoesNotExist();
        if (!ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).isVoided(agreementId))
            revert LexScrowStorage.DealNotVoided();

        Escrow storage deal = LexScrowStorage.getEscrow(agreementId);
        if (deal.status == EscrowStatus.PAID) {
            _voidCorpCerts(deal);
            // Interaction: Re-sync Deal Manager internal escrow to VOIDED, then refund
            LexScrowStorage.voidAndRefund(agreementId);
        } else if (deal.status == EscrowStatus.PENDING) {
            _voidCorpCerts(deal);
            // Effect: update status (nothing was paid, so there is nothing to refund)
            LexScrowStorage.voidEscrow(agreementId);
        } else {
            // Already VOIDED (certs already torn down, nothing left to sync) or FINALIZED
            revert LexScrowStorage.DealVoided();
        }
    }

    /// @dev Teardown shared by every void path: the corp's certificates were minted to this manager at
    /// proposal time and are never returned, so they must be voided or they keep counting toward the
    /// printer's look-through holder tally. Idempotent — voiding an already-void lot is a no-op.
    function _voidCorpCerts(Escrow storage deal) private {
        for (uint256 i = 0; i < deal.corpAssets.length; i++) {
            if (deal.corpAssets[i].tokenType == TokenType.ERC721) {
                ILedgerEntryToken(deal.corpAssets[i].tokenAddress).voidCert(
                    deal.corpAssets[i].tokenId
                );
            }
        }
    }

}