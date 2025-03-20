pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/ICyberCorp.sol";

abstract contract LexScroWLite is Initializable {

    address public CORP;

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
    }

    mapping(bytes32 => PendingDeal) public escrows;

    constructor() {
    }

    function __LexScroWLite_init(address _corp) internal onlyInitializing  {
        CORP = _corp;
    }

    function createEscrow(bytes32 agreementId, address counterParty, Token[] memory corpAssets, Token[] memory buyerAssets) public {
        escrows[agreementId] = PendingDeal(agreementId, counterParty, corpAssets, buyerAssets);
    }

    function updateEscrow(bytes32 agreementId, address counterParty) public 
    {
        escrows[agreementId].counterParty = counterParty;
    }

    function finalizeDeal(bytes32 agreementId) public {
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
