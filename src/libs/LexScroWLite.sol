pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/ICyberCorp.sol";
import "../interfaces/ICyberAgreementRegistry.sol";
import "../interfaces/ICyberCertPrinter.sol";
import "../interfaces/ICondition.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LexScrowStorage, Escrow, Token, TokenType, EscrowStatus} from "../storage/LexScrowStorage.sol";


abstract contract LexScroWLite is Initializable, ReentrancyGuard {
    using LexScrowStorage for LexScrowStorage.LexScrowData;

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

    constructor() {
    }

    function __LexScroWLite_init(address _corp, address _dealRegistry) internal onlyInitializing {
        LexScrowStorage.setCorp(_corp);
        LexScrowStorage.setDealRegistry(_dealRegistry);
    }

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
        ICyberCertPrinter(escrow.corpAssets[0].tokenAddress).addEndorsement(escrow.corpAssets[0].tokenId, newEndorsement);
    }

    function handleCounterPartyPayment(bytes32 agreementId) internal {
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);
        if(escrow.status != EscrowStatus.PENDING) revert EscrowNotPending();
        if(escrow.counterParty == address(0)) revert CounterPartyNotSet();

        for(uint256 i = 0; i < escrow.buyerAssets.length; i++) {
            if(escrow.buyerAssets[i].tokenType == TokenType.ERC20) {
                IERC20(escrow.buyerAssets[i].tokenAddress).transferFrom(escrow.counterParty, address(this), escrow.buyerAssets[i].amount);
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

    function voidAndRefund(bytes32 agreementId) internal nonReentrant {
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);
        if(escrow.status != EscrowStatus.PAID) revert EscrowNotPaid();
        if(!ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).isVoided(agreementId)) revert DealNotVoided();

        // Refund buyer assets first
        for(uint256 i = 0; i < escrow.buyerAssets.length; i++) {
            if(escrow.buyerAssets[i].tokenType == TokenType.ERC20) {
                IERC20(escrow.buyerAssets[i].tokenAddress).transfer(escrow.counterParty, escrow.buyerAssets[i].amount);
            }
            else if(escrow.buyerAssets[i].tokenType == TokenType.ERC721) {
                IERC721(escrow.buyerAssets[i].tokenAddress).safeTransferFrom(address(this), escrow.counterParty, escrow.buyerAssets[i].tokenId);
            }
            else if(escrow.buyerAssets[i].tokenType == TokenType.ERC1155) {
                IERC1155(escrow.buyerAssets[i].tokenAddress).safeTransferFrom(address(this), escrow.counterParty, escrow.buyerAssets[i].tokenId, escrow.buyerAssets[i].amount, "");
            }
        }

        voidEscrow(agreementId);
    }

    function finalizeEscrow(bytes32 agreementId) internal nonReentrant {
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);

        // Check all conditions before proceeding
        if(block.timestamp > escrow.expiry) revert DealExpired();
        if(escrow.status != EscrowStatus.PAID) revert EscrowNotPaid();

        // Update state before external calls
        escrow.status = EscrowStatus.FINALIZED;
        emit DealFinalizedAt(agreementId, LexScrowStorage.getDealRegistry(), block.timestamp);

        // Transfer buyer assets to company
        for(uint256 i = 0; i < escrow.buyerAssets.length; i++) {
            if(escrow.buyerAssets[i].tokenType == TokenType.ERC20) {
                IERC20(escrow.buyerAssets[i].tokenAddress).transfer(ICyberCorp(LexScrowStorage.getCorp()).companyPayable(), escrow.buyerAssets[i].amount);
            }
            else if(escrow.buyerAssets[i].tokenType == TokenType.ERC721) {
                IERC721(escrow.buyerAssets[i].tokenAddress).safeTransferFrom(address(this), ICyberCorp(LexScrowStorage.getCorp()).companyPayable(), escrow.buyerAssets[i].tokenId);
            }
            else if(escrow.buyerAssets[i].tokenType == TokenType.ERC1155) {
                IERC1155(escrow.buyerAssets[i].tokenAddress).safeTransferFrom(address(this), ICyberCorp(LexScrowStorage.getCorp()).companyPayable(), escrow.buyerAssets[i].tokenId, escrow.buyerAssets[i].amount, "");
            }
        }

        // Transfer corp assets to counter party
        for(uint256 i = 0; i < escrow.corpAssets.length; i++) {
            if(escrow.corpAssets[i].tokenType == TokenType.ERC20) {
                IERC20(escrow.corpAssets[i].tokenAddress).transfer(escrow.counterParty, escrow.corpAssets[i].amount);
            }
            else if(escrow.corpAssets[i].tokenType == TokenType.ERC721) {
                IERC721(escrow.corpAssets[i].tokenAddress).safeTransferFrom(address(this), escrow.counterParty, escrow.corpAssets[i].tokenId);
            }
            else if(escrow.corpAssets[i].tokenType == TokenType.ERC1155) {
                IERC1155(escrow.corpAssets[i].tokenAddress).safeTransferFrom(address(this), escrow.counterParty, escrow.corpAssets[i].tokenId, escrow.corpAssets[i].amount, "");
            }
        }
    }

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

    function voidEscrow(bytes32 agreementId) internal {
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);
        escrow.status = EscrowStatus.VOIDED;
        emit DealVoidedAt(agreementId, LexScrowStorage.getDealRegistry(), block.timestamp);
    }

    function getEscrowDetails(bytes32 agreementId) public view returns (Escrow memory) {
        return LexScrowStorage.getEscrow(agreementId);
    }

    //receiver erc721s
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4) {
        return this.onERC721Received.selector;
    }

    //receiver erc1155s
    function onERC1155Received(address operator, address from, uint256 tokenId, uint256 amount, bytes calldata data) external returns (bytes4) {
        return this.onERC1155Received.selector;
    }
}
