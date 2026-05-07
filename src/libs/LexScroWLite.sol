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

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/ICyberCorp.sol";
import "../interfaces/ICyberAgreementRegistry.sol";
import "../interfaces/ICyberCertPrinter.sol";
import "../interfaces/ICondition.sol";
import {LexScrowStorage, Escrow, Token, TokenType, EscrowStatus} from "../storage/LexScrowStorage.sol";


abstract contract LexScroWLite is Initializable {
    using LexScrowStorage for LexScrowStorage.LexScrowData;
    using SafeERC20 for IERC20;

    error DealExpired();
    error EscrowNotPending();
    error EscrowNotPaid();
    error CounterPartyNotSet();
    error DealNotFullySigned();
    error DealNotFinalized();
    error DealAlreadyFinalized();
    error DealNotVoided();
    error DealNotPaid();
    error DealVoided();

    event DealVoidedAt(bytes32 indexed agreementId, address agreementRegistry, uint256 timestamp);
    event DealPaidAt(bytes32 indexed agreementId, address agreementRegistry, uint256 timestamp);
    event DealFinalizedAt(bytes32 indexed agreementId, address agreementRegistry, uint256 timestamp);
    event FeeDistributed(bytes32 indexed agreementId, address indexed feeToken, uint256 totalFe);

    constructor() {
    }

    /// @notice Initialize core addresses for the escrow subsystem
    /// @param _corp Address of the `ICyberCorp` implementation
    /// @param _dealRegistry Address of the `ICyberAgreementRegistry` implementation
    function __LexScroWLite_init(address _corp, address _dealRegistry) internal onlyInitializing {
        LexScrowStorage.setCorp(_corp);
        LexScrowStorage.setDealRegistry(_dealRegistry);
    }

    /// @notice Create a new escrow record for an agreement
    /// @param agreementId Unique identifier of the agreement
    /// @param counterParty Counterparty/buyer address
    /// @param corpAssets Assets the company will deliver upon finalization
    /// @param buyerAssets Assets the counterparty will deliver into escrow
    /// @param expiry Unix timestamp after which the deal is considered expired
    function createEscrow(bytes32 agreementId, address counterParty, Token[] memory corpAssets, Token[] memory buyerAssets, uint256 expiry) internal {
        bytes memory blankSignature = abi.encodePacked(bytes32(0));
        Escrow memory newEscrow = Escrow({
            agreementId: agreementId,
            counterParty: counterParty,
            corpAssets: corpAssets,
            buyerAssets: buyerAssets,
            signature: blankSignature,
            expiry: expiry,
            status: EscrowStatus.PENDING
        });
        LexScrowStorage.setEscrow(agreementId, newEscrow);
    }

    /// @notice Update escrow counterparty and add endorsement to corp ERC721 certificates
    /// @param agreementId Unique identifier of the agreement
    /// @param counterParty Counterparty/buyer address to set
    /// @param buyerName Human-readable buyer name stored in endorsements
    function updateEscrow(bytes32 agreementId, address counterParty, string memory buyerName) internal {
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);
        escrow.counterParty = counterParty;

        Endorsement memory newEndorsement = Endorsement(
            address(this),
            block.timestamp,
            escrow.signature,
            LexScrowStorage.getDealRegistry(),
            agreementId,
            escrow.counterParty,
            buyerName
        );
        for(uint256 i = 0; i < escrow.corpAssets.length; i++) {
            if(escrow.corpAssets[i].tokenType == TokenType.ERC721) {
                ICyberCertPrinter(escrow.corpAssets[i].tokenAddress).addEndorsement(escrow.corpAssets[i].tokenId, newEndorsement);
                // check if there is an escrowed officer signature in cybercorp
                bytes memory officerSignature = "";
                address corp = LexScrowStorage.getCorp();
                try ICyberCorp(corp).getEscrowedOfficerSignatureCount() returns (
                    uint256 count
                ) {
                    if (count > 0) {
                        try ICyberCorp(corp).getEscrowedOfficerSignature(0) returns (bytes memory sig) {
                            officerSignature = sig;
                        } catch {}
                    }
                } catch {}
                if (officerSignature.length > 0) {
                    ICyberCertPrinter(escrow.corpAssets[i].tokenAddress).addIssuerSignature(
                        escrow.corpAssets[i].tokenId,
                        officerSignature
                    );
                }
            }
        }
    }

    /// @notice Pull buyer assets into escrow and mark the escrow as PAID
    /// @param agreementId Unique identifier of the agreement
    function handleCounterPartyPayment(bytes32 agreementId) internal {
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);
        if(escrow.status != EscrowStatus.PENDING) revert EscrowNotPending();
        if(escrow.counterParty == address(0)) revert CounterPartyNotSet();

        for(uint256 i = 0; i < escrow.buyerAssets.length; i++) {
            if(escrow.buyerAssets[i].tokenType == TokenType.ERC20) {
                IERC20(escrow.buyerAssets[i].tokenAddress).safeTransferFrom(escrow.counterParty, address(this), escrow.buyerAssets[i].amount);
            }
            else if(escrow.buyerAssets[i].tokenType == TokenType.ERC721) {
                IERC721(escrow.buyerAssets[i].tokenAddress).safeTransferFrom(escrow.counterParty, address(this), escrow.buyerAssets[i].tokenId);
            }
            else if(escrow.buyerAssets[i].tokenType == TokenType.ERC1155) {
                IERC1155(escrow.buyerAssets[i].tokenAddress).safeTransferFrom(escrow.counterParty, address(this), escrow.buyerAssets[i].tokenId, escrow.buyerAssets[i].amount, "");
            }
        }

        emit DealPaidAt(agreementId, LexScrowStorage.getDealRegistry(), block.timestamp);
        escrow.status = EscrowStatus.PAID;
    }

    /// @notice Void a PAID escrow and refund all buyer assets
    /// @dev External callers should implement reentrancy guards
    /// @param agreementId Unique identifier of the agreement
    function voidAndRefund(bytes32 agreementId) internal {
        // Check: check status
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);
        if(escrow.status != EscrowStatus.PAID) revert EscrowNotPaid();
        if(!ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).isVoided(agreementId)) revert DealNotVoided();

        // Effect: update status
        voidEscrow(agreementId);

        // Interaction: Refund buyer assets
        for(uint256 i = 0; i < escrow.buyerAssets.length; i++) {
            if(escrow.buyerAssets[i].tokenType == TokenType.ERC20) {
                IERC20(escrow.buyerAssets[i].tokenAddress).safeTransfer(escrow.counterParty, escrow.buyerAssets[i].amount);
            }
            else if(escrow.buyerAssets[i].tokenType == TokenType.ERC721) {
                IERC721(escrow.buyerAssets[i].tokenAddress).safeTransferFrom(address(this), escrow.counterParty, escrow.buyerAssets[i].tokenId);
            }
            else if(escrow.buyerAssets[i].tokenType == TokenType.ERC1155) {
                IERC1155(escrow.buyerAssets[i].tokenAddress).safeTransferFrom(address(this), escrow.counterParty, escrow.buyerAssets[i].tokenId, escrow.buyerAssets[i].amount, "");
            }
        }
    }

    /// @notice Finalize a PAID escrow, transferring assets and distributing any fees
    /// @dev External callers should implement reentrancy guards
    /// @param agreementId Unique identifier of the agreement
    function finalizeEscrow(bytes32 agreementId) internal {
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);

        // Check: Check all conditions before proceeding
        if(block.timestamp > escrow.expiry) revert DealExpired();
        if(escrow.status != EscrowStatus.PAID) revert EscrowNotPaid();

        // Effect: Update state before external calls
        escrow.status = EscrowStatus.FINALIZED;
        emit DealFinalizedAt(agreementId, LexScrowStorage.getDealRegistry(), block.timestamp);

        // Interaction: Transfer buyer assets to company and collect fees
        for(uint256 i = 0; i < escrow.buyerAssets.length; i++) {
            if(escrow.buyerAssets[i].tokenType == TokenType.ERC20) {
                uint256 amountToCompany = escrow.buyerAssets[i].amount;
                uint256 fee = 0;

                // Check: if the asset is fee token
                if (escrow.buyerAssets[i].isFee) {
                    // Effect: Calculate fees
                    fee = computeFee(escrow.buyerAssets[i].amount);
                    amountToCompany -= fee;

                    emit FeeDistributed(agreementId, escrow.buyerAssets[i].tokenAddress, fee);
                }

                // Interaction: Distribute payment and fees
                if (amountToCompany > 0) {
                    IERC20(escrow.buyerAssets[i].tokenAddress).safeTransfer(ICyberCorp(LexScrowStorage.getCorp()).companyPayable(), amountToCompany);
                }
                if (fee > 0) {
                    IERC20(escrow.buyerAssets[i].tokenAddress).safeTransfer(getPlatformPayable(), fee);
                }
            }
            else if(escrow.buyerAssets[i].tokenType == TokenType.ERC721) {
                IERC721(escrow.buyerAssets[i].tokenAddress).safeTransferFrom(address(this), ICyberCorp(LexScrowStorage.getCorp()).companyPayable(), escrow.buyerAssets[i].tokenId);
            }
            else if(escrow.buyerAssets[i].tokenType == TokenType.ERC1155) {
                IERC1155(escrow.buyerAssets[i].tokenAddress).safeTransferFrom(address(this), ICyberCorp(LexScrowStorage.getCorp()).companyPayable(), escrow.buyerAssets[i].tokenId, escrow.buyerAssets[i].amount, "");
            }
        }

        // Interaction: Transfer corp assets to counter party
        for(uint256 i = 0; i < escrow.corpAssets.length; i++) {
            if(escrow.corpAssets[i].tokenType == TokenType.ERC20) {
                IERC20(escrow.corpAssets[i].tokenAddress).safeTransfer(escrow.counterParty, escrow.corpAssets[i].amount);
            }
            else if(escrow.corpAssets[i].tokenType == TokenType.ERC721) {
                IERC721(escrow.corpAssets[i].tokenAddress).safeTransferFrom(address(this), escrow.counterParty, escrow.corpAssets[i].tokenId);
            }
            else if(escrow.corpAssets[i].tokenType == TokenType.ERC1155) {
                IERC1155(escrow.corpAssets[i].tokenAddress).safeTransferFrom(address(this), escrow.counterParty, escrow.corpAssets[i].tokenId, escrow.corpAssets[i].amount, "");
            }
        }
    }

    /// @notice Check all conditions attached to the escrow for the given agreement
    /// @param agreementId Unique identifier of the agreement
    /// @return True if all conditions pass, false otherwise
    function conditionCheck(bytes32 agreementId) public view returns (bool) {
        ICondition[] storage conditions = LexScrowStorage.getConditionsByEscrow(agreementId);
        //convert bytes32 to bytes
        bytes memory agreementIdBytes = abi.encodePacked(agreementId);

        for(uint256 i = 0; i < conditions.length; i++) {
            if(!ICondition(conditions[i]).checkCondition(address(this), msg.sig, agreementIdBytes))
                return false;
        }
        return true;
    }

    /// @notice Mark an escrow as VOIDED and emit an event
    /// @param agreementId Unique identifier of the agreement
    function voidEscrow(bytes32 agreementId) internal {
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);
        escrow.status = EscrowStatus.VOIDED;
        emit DealVoidedAt(agreementId, LexScrowStorage.getDealRegistry(), block.timestamp);
    }

    /// @notice Get escrow details for a given agreement id
    /// @param agreementId Unique identifier of the agreement
    /// @return Escrow struct containing current state
    function getEscrowDetails(bytes32 agreementId) public view returns (Escrow memory) {
        return LexScrowStorage.getEscrow(agreementId);
    }

    /// @notice Compute fee based on ticket size
    /// @dev Child contract should implement the actual logic
    /// @return Fee amount
    function computeFee(uint256 size) public virtual view returns (uint256);

    /// @notice Get the payable address for the fees
    /// @dev Child contract should implement the actual logic
    /// @return Payable address for the fees
    function getPlatformPayable() public virtual view returns (address);

    /// @notice ERC721 receiver hook for safe transfers into escrow
    /// @param operator Address which initiated the transfer
    /// @param from Previous owner of the token
    /// @param tokenId Identifier of the token being transferred
    /// @param data Additional data with no specified format
    /// @return Selector to confirm the token transfer
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /// @notice ERC1155 receiver hook for safe transfers into escrow
    /// @param operator Address which initiated the transfer
    /// @param from Previous owner of the token(s)
    /// @param tokenId Identifier of the token being transferred
    /// @param amount Amount of tokens being transferred
    /// @param data Additional data with no specified format
    /// @return Selector to confirm the token transfer
    function onERC1155Received(address operator, address from, uint256 tokenId, uint256 amount, bytes calldata data) external returns (bytes4) {
        return this.onERC1155Received.selector;
    }
}
