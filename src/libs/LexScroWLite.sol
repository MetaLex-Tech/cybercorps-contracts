pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/ICyberCorp.sol";
import "../interfaces/ICyberDealRegistry.sol";
import "../interfaces/ICyberCertPrinter.sol";
import "../interfaces/ICondition.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


abstract contract LexScroWLite is Initializable, ReentrancyGuard {

    address public CORP;
    ICyberDealRegistry public DEAL_REGISTRY;

    enum TokenType {
        ERC20,
        ERC721,
        ERC1155
    }

    struct Token {
        TokenType tokenType;
        address tokenAddress;
        uint256 tokenId;
        uint256 amount;
    }

    enum EscrowStatus {
        PENDING,
        PAID,
        FINALIZED,
        VOIDED
    }

    struct Escrow {
        bytes32 agreementId;
        address counterParty;
        Token[] corpAssets;
        Token[] buyerAssets;
        bytes signature;
        uint256 expiry;
        EscrowStatus status;
    }

    mapping(bytes32 => Escrow) public escrows;
    mapping(bytes32 => ICondition[]) public conditionsByEscrow;

    error DealExpired();
    error EscrowNotPending();
    error EscrowNotPaid();
    error CounterPartyNotSet();

    constructor() {
    }

    function __LexScroWLite_init(address _corp, address _dealRegistry) internal onlyInitializing  {
        CORP = _corp;
        DEAL_REGISTRY = ICyberDealRegistry(_dealRegistry);
    }

    function createEscrow(bytes32 agreementId, address counterParty, Token[] memory corpAssets, Token[] memory buyerAssets, uint256 expiry) public {
        bytes memory blankSignature = abi.encodePacked(bytes32(0));
        escrows[agreementId] =  Escrow(agreementId, counterParty, corpAssets, buyerAssets, blankSignature, expiry, EscrowStatus.PENDING);
    }

    function updateEscrow(bytes32 agreementId, address counterParty) public 
    {
        escrows[agreementId].counterParty = counterParty;
    }

    function handleCounterPartyPayment(bytes32 agreementId) public {
        Escrow storage deal = escrows[agreementId];
        if(deal.status != EscrowStatus.PENDING) revert EscrowNotPending();
        if(deal.counterParty == address(0)) revert CounterPartyNotSet();

        for(uint256 i = 0; i < deal.buyerAssets.length; i++) {
            if(deal.buyerAssets[i].tokenType == TokenType.ERC20) {
                IERC20(deal.buyerAssets[i].tokenAddress).transferFrom(deal.counterParty, address(this), deal.buyerAssets[i].amount);
            }
            else if(deal.buyerAssets[i].tokenType == TokenType.ERC721) {
                IERC721(deal.buyerAssets[i].tokenAddress).safeTransferFrom(deal.counterParty, address(this), deal.buyerAssets[i].tokenId);
            }
            else if(deal.buyerAssets[i].tokenType == TokenType.ERC1155) {
                IERC1155(deal.buyerAssets[i].tokenAddress).safeTransferFrom(deal.counterParty, address(this), deal.buyerAssets[i].tokenId, deal.buyerAssets[i].amount, "");
            }
        }

       deal.status = EscrowStatus.PAID;
    }

    function finalizeDeal(bytes32 agreementId, string memory buyerName) public {
        Escrow storage deal = escrows[agreementId];
        if(block.timestamp > deal.expiry) revert DealExpired();
        if(deal.status != EscrowStatus.PAID) revert EscrowNotPaid();

       for(uint256 i = 0; i < deal.buyerAssets.length; i++) {
        if(deal.buyerAssets[i].tokenType == TokenType.ERC20) {
            IERC20(deal.buyerAssets[i].tokenAddress).transfer(ICyberCorp(CORP).companyPayable(), deal.buyerAssets[i].amount);
        }
        else if(deal.buyerAssets[i].tokenType == TokenType.ERC721) {
            IERC721(deal.buyerAssets[i].tokenAddress).safeTransferFrom(address(this), ICyberCorp(CORP).companyPayable(), deal.buyerAssets[i].tokenId);
        }
        else if(deal.buyerAssets[i].tokenType == TokenType.ERC1155) {
            IERC1155(deal.buyerAssets[i].tokenAddress).safeTransferFrom(address(this), ICyberCorp(CORP).companyPayable(), deal.buyerAssets[i].tokenId, deal.buyerAssets[i].amount, "");
        }
       }

       Endorsement memory newEndorsement = Endorsement(address(this), block.timestamp, deal.signature, address(DEAL_REGISTRY), agreementId, deal.counterParty, buyerName);
       ICyberCertPrinter(deal.corpAssets[0].tokenAddress).addEndorsement(deal.corpAssets[0].tokenId, newEndorsement);

       //transfer tokens
       for(uint256 i = 0; i < deal.corpAssets.length; i++) {
        if(deal.corpAssets[i].tokenType == TokenType.ERC20) {
            IERC20(deal.corpAssets[i].tokenAddress).transfer(deal.counterParty, deal.corpAssets[i].amount);
        }
        else if(deal.corpAssets[i].tokenType == TokenType.ERC721) {
            IERC721(deal.corpAssets[i].tokenAddress).safeTransferFrom(address(this), deal.counterParty, deal.corpAssets[i].tokenId);
        }
        else if(deal.corpAssets[i].tokenType == TokenType.ERC1155) {
            IERC1155(deal.corpAssets[i].tokenAddress).safeTransferFrom(address(this), deal.counterParty, deal.corpAssets[i].tokenId, deal.corpAssets[i].amount, "");
        }
       }

       deal.status = EscrowStatus.FINALIZED;   
    }

    function conditionCheck(bytes32 agreementId) public view returns (bool) {
        ICondition[] memory conditionsToCheck = conditionsByEscrow[agreementId];
        Escrow memory deal = escrows[agreementId];
        //convert bytes32 to bytes
        bytes memory agreementIdBytes = abi.encodePacked(agreementId);
        
        for(uint256 i = 0; i < conditionsToCheck.length; i++) {
                if(!ICondition(conditionsToCheck[i]).checkCondition(address(this), msg.sig, agreementIdBytes)) 
                    return false;
        }
        return true;
    }

    function voidAndRefund(bytes32 agreementId  ) public {
        if(escrows[agreementId].status != EscrowStatus.PAID) revert EscrowNotPaid();
        voidEscrow(agreementId);
        for(uint256 i = 0; i < escrows[agreementId].corpAssets.length; i++) {
            IERC20(escrows[agreementId].corpAssets[i].tokenAddress).transfer(escrows[agreementId].counterParty, escrows[agreementId].corpAssets[i].amount);
        }
        
    }

    function voidEscrow(bytes32 agreementId) internal {
        escrows[agreementId].status = EscrowStatus.VOIDED;
    }

    function getEscrowDetails(bytes32 agreementId) public view returns (Escrow memory) {
        return escrows[agreementId];
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
