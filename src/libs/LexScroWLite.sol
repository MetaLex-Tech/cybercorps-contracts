pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/ICyberCorp.sol";
import "../interfaces/ICyberDealRegistry.sol";
import "../interfaces/ICyberCertPrinter.sol";


abstract contract LexScroWLite is Initializable {

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

    struct PendingDeal {
        bytes32 agreementId;
        address counterParty;
        Token[] corpAssets;
        Token[] buyerAssets;
        bytes signature;
    }

    mapping(bytes32 => PendingDeal) public escrows;

    constructor() {
    }

    function __LexScroWLite_init(address _corp, address _dealRegistry) internal onlyInitializing  {
        CORP = _corp;
        DEAL_REGISTRY = ICyberDealRegistry(_dealRegistry);
    }

    function createEscrow(bytes32 agreementId, address counterParty, Token[] memory corpAssets, Token[] memory buyerAssets) public {
        bytes memory blankSignature = abi.encodePacked(bytes32(0));
        escrows[agreementId] = PendingDeal(agreementId, counterParty, corpAssets, buyerAssets, blankSignature);
    }

    function updateEscrow(bytes32 agreementId, address counterParty) public 
    {
        escrows[agreementId].counterParty = counterParty;
    }

    function finalizeDeal(bytes32 agreementId, string memory buyerName) public {
        PendingDeal storage deal = escrows[agreementId];

       for(uint256 i = 0; i < deal.buyerAssets.length; i++) {
        if(deal.buyerAssets[i].tokenType == TokenType.ERC20) {
            IERC20(deal.buyerAssets[i].tokenAddress).transferFrom(deal.counterParty, ICyberCorp(CORP).companyPayable(), deal.buyerAssets[i].amount);
        }
        else if(deal.buyerAssets[i].tokenType == TokenType.ERC721) {
            IERC721(deal.buyerAssets[i].tokenAddress).safeTransferFrom(deal.counterParty, ICyberCorp(CORP).companyPayable(), deal.buyerAssets[i].tokenId);
        }
        else if(deal.buyerAssets[i].tokenType == TokenType.ERC1155) {
            IERC1155(deal.buyerAssets[i].tokenAddress).safeTransferFrom(deal.counterParty, ICyberCorp(CORP).companyPayable(), deal.buyerAssets[i].tokenId, deal.buyerAssets[i].amount, "");
        }
       }

       endorsement memory newEndorsement = endorsement(address(this), block.timestamp, deal.signature, address(DEAL_REGISTRY), agreementId, deal.counterParty, buyerName);
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
