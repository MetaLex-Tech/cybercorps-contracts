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

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/ICyberAgreementRegistry.sol";
import "../libs/auth.sol";
import "./lexchex.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract LeXcheXMinter is Initializable, UUPSUpgradeable, BorgAuthACL {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    // Domain information
    string public constant name = "LeXcheXMinter";
    string public version;
    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public AUTHORITY_TYPEHASH;
    address public auth;

    // Errors
    error InvalidSignature();
    error PaymentFailed();
    error InvalidPaymentAmount();
    error MintFailed();
    error AccreditationDoesNotExist();
    error AccreditationVoided();

    // Events
    event MintRequested(address indexed requester, uint256 mintPrice, bytes32 agreementId);
    event MintCompleted(address indexed owner, uint256 tokenId, bytes32 agreementId);
    event RenewalRequested(address indexed requester, uint256 mintPrice, bytes32 agreementId);
    event RenewalCompleted(address indexed owner, uint256 tokenId, bytes32 agreementId);

    // State variables
    address public lexchex;
    address public dealRegistry;
    address public treasury;

    // Upgrade notes: Reduced gap to account for new variables (50 - 7 - 1 = 42)
    uint256[42] private __gap;

    struct MintRequest {
        uint256 uuid;
        address owner;
        string investorName;
        string investorType;
        string investorJurisdiction;
        string investorContact;
        uint256 mintPrice;
        uint256 expiry;
        address paymentToken;
    }

    struct AuthorityData {
        uint256 uuid;
        address owner;
        string investorName;
        string investorType;
        string investorJurisdiction;
        string investorContact;
        uint256 mintPrice;
        uint256 expiry;
        address paymentToken;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _auth,
        address _lexchex,
        address _dealRegistry,
        address _treasury
    ) public initializer {
        __BorgAuthACL_init(_auth);
        lexchex = _lexchex;
        dealRegistry = _dealRegistry;
        treasury = _treasury;
        auth = _auth;
        version = "1";
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                block.chainid,
                address(this)
            )
        );

        AUTHORITY_TYPEHASH = keccak256(
            "AuthorityData(uint256 uuid,address owner,string investorName,string investorType,string investorJurisdiction,string investorContact,uint256 mintPrice,uint256 expiry,address paymentToken)"
        );
    }

    function requestMint(
        MintRequest calldata request,
        bytes32 _templateId,
        uint256 _salt,
        string[] memory _globalValues,
        address[] memory _parties,
        string[][] memory _partyValues,
        bytes memory agreementSignature,  // Signature for the agreement
        bytes memory authoritySignature    // Signature from authority for verification
    ) external returns (bytes32 agreementId, uint256 tokenId) {
        // 1. Verify authority signature is from an admin using EIP-712
        _verifyAuthoritySignature(request, authoritySignature);

        // 2. Handle payment using safeTransferFrom
        if (request.mintPrice > 0) {
            IERC20(request.paymentToken).safeTransferFrom(
                msg.sender,
                treasury,
                request.mintPrice
            );
        }

        // 3. Create accreditation struct
        Accreditation memory acc = Accreditation({
            agreementId: bytes32(0), // Will be set after agreement creation
            registryAddress: dealRegistry,
            investorName: request.investorName,
            investorType: request.investorType,
            investorJurisdiction: request.investorJurisdiction,
            investorContact: request.investorContact,
            issuanceDate: block.timestamp,
            expiryDate: request.expiry,
            voided: "",
            signature: authoritySignature,  // Use authority signature here
            uuid: request.uuid
        });

        // 4. Create and sign agreement
        agreementId = ICyberAgreementRegistry(dealRegistry).createContract(
            _templateId,
            _salt,
            _globalValues,
            _parties,
            _partyValues,
            bytes32(0), // No secret hash
            address(this),
            request.expiry
        );

        // Sign the agreement with the provided agreement signature
        ICyberAgreementRegistry(dealRegistry).signContractFor(
            request.owner,
            agreementId,
            _partyValues[0],
            agreementSignature,
            false,
            ""
        );

        // Update accreditation with agreement ID
        acc.agreementId = agreementId;

        // 5. Mint LeXcheX
        tokenId = LeXcheX(lexchex).mint(request.owner, acc);

        // 6. Finalize the agreement
        ICyberAgreementRegistry(dealRegistry).finalizeContract(agreementId);

        emit MintRequested(request.owner, request.mintPrice, agreementId);
        emit MintCompleted(request.owner, tokenId, agreementId);
    }

    /// @notice Admin-only path to mint for autominting with certain conditions in investing
    /// @dev Mirrors requestMint but gated by onlyAdmin and skips _verifyAuthoritySignature
    function requestMintFor(
        MintRequest memory request,
        bytes32 _templateId,
        uint256 _salt,
        string[] memory _globalValues,
        address[] memory _parties,
        string[][] memory _partyValues,
        bytes memory agreementSignature
    ) external onlyAdmin returns (bytes32 agreementId, uint256 tokenId) {
        // 1. Handle payment using safeTransferFrom (if any)
        if (request.mintPrice > 0) {
            IERC20(request.paymentToken).safeTransferFrom(
                msg.sender,
                treasury,
                request.mintPrice
            );
        }

        // 2. Create accreditation struct (signature field can store empty bytes for admin path)
        Accreditation memory acc = Accreditation({
            agreementId: bytes32(0),
            registryAddress: dealRegistry,
            investorName: request.investorName,
            investorType: request.investorType,
            investorJurisdiction: request.investorJurisdiction,
            investorContact: request.investorContact,
            issuanceDate: block.timestamp,
            expiryDate: request.expiry,
            voided: "",
            signature: "",
            uuid: request.uuid
        });

        //if expiryDate is > 90 days, cap at 90 days from now
        if(request.expiry > block.timestamp + 90 days) 
            request.expiry = block.timestamp + 90 days;
        
        // 3. Create and sign agreement
        agreementId = ICyberAgreementRegistry(dealRegistry).createContract(
            _templateId,
            _salt,
            _globalValues,
            _parties,
            _partyValues,
            bytes32(0),
            address(this),
            request.expiry
        );

        ICyberAgreementRegistry(dealRegistry).signContractFor(
            request.owner,
            agreementId,
            _partyValues[0],
            agreementSignature,
            false,
            ""
        );

        // 4. Update accreditation with agreement ID and mint
        acc.agreementId = agreementId;
        tokenId = LeXcheX(lexchex).mint(request.owner, acc);

        // 5. Finalize the agreement
        ICyberAgreementRegistry(dealRegistry).finalizeContract(agreementId);

        emit MintRequested(request.owner, request.mintPrice, agreementId);
        emit MintCompleted(request.owner, tokenId, agreementId);
    }

    /// @notice Admin-only direct mint without creating an agreement
    /// @dev Simplest path for admin-approved accreditations - mints directly with agreementId = 0
    function adminMintFor(
        MintRequest calldata request
    ) external onlyAdmin returns (uint256 tokenId) {

        // Create accreditation struct without agreement
        Accreditation memory acc = Accreditation({
            agreementId: bytes32(0), // No agreement for admin direct mints
            registryAddress: dealRegistry,
            investorName: request.investorName,
            investorType: request.investorType,
            investorJurisdiction: request.investorJurisdiction,
            investorContact: request.investorContact,
            issuanceDate: block.timestamp,
            expiryDate: request.expiry,
            voided: "",
            signature: "",
            uuid: request.uuid
        });

        // Mint directly
        tokenId = LeXcheX(lexchex).mint(request.owner, acc);

        emit MintRequested(request.owner, request.mintPrice, bytes32(0));
        emit MintCompleted(request.owner, tokenId, bytes32(0));
    }

    function requestRenewal(
        MintRequest calldata request,
        uint256 tokenId,
        bytes memory authoritySignature
    ) external {
        // 1. Verify authority signature is from an admin using EIP-712
        _verifyAuthoritySignature(request, authoritySignature);

        // get the accreditation
        Accreditation memory acc = LeXcheX(lexchex).accreditations(tokenId);

        // Check that the accreditation exists
        if(acc.issuanceDate == 0) {
            revert AccreditationDoesNotExist();
        }

        // Check that the accreditation has not been voided
        if(bytes(acc.voided).length > 0) {
            revert AccreditationVoided();
        }

        // Note an expired token could still be renewed

        // 2. Handle payment using safeTransferFrom
        if (request.mintPrice > 0) {
            IERC20(request.paymentToken).safeTransferFrom(
                msg.sender,
                treasury,
                request.mintPrice
            );
        }

        // 3. Renew the agreement
        acc.expiryDate = request.expiry;
        acc.issuanceDate = block.timestamp;
        acc.signature = authoritySignature;

        // 4. Update LeXcheX
        LeXcheX(lexchex).setAccreditation(tokenId, acc);

        emit RenewalRequested(request.owner, request.mintPrice, acc.agreementId);
        emit RenewalCompleted(request.owner, tokenId, acc.agreementId);
    }

    /// @notice Admin-only path to renew without an authority signature
    /// @dev Mirrors requestRenewal but gated by onlyAdmin and skips _verifyAuthoritySignature
    function requestRenewalFor(
        MintRequest calldata request,
        uint256 tokenId
    ) external onlyAdmin {
        // get the accreditation
        Accreditation memory acc = LeXcheX(lexchex).accreditations(tokenId);

        // Check that the accreditation exists
        if(acc.issuanceDate == 0) {
            revert AccreditationDoesNotExist();
        }

        // Check that the accreditation has not been voided
        if(bytes(acc.voided).length > 0) {
            revert AccreditationVoided();
        }

        // Handle payment using safeTransferFrom
        if (request.mintPrice > 0) {
            IERC20(request.paymentToken).safeTransferFrom(
                msg.sender,
                treasury,
                request.mintPrice
            );
        }

        // Renew the agreement
        acc.expiryDate = request.expiry;
        acc.issuanceDate = block.timestamp;
        acc.signature = "";

        // Update LeXcheX
        LeXcheX(lexchex).setAccreditation(tokenId, acc);

        emit RenewalRequested(request.owner, request.mintPrice, acc.agreementId);
        emit RenewalCompleted(request.owner, tokenId, acc.agreementId);
    }

    function _verifyAuthoritySignature(
        MintRequest memory request,
        bytes memory signature
    ) internal view {
        // Create AuthorityData struct for signature verification
        AuthorityData memory data = AuthorityData({
            uuid: request.uuid,
            owner: request.owner,
            investorName: request.investorName,
            investorType: request.investorType,
            investorJurisdiction: request.investorJurisdiction,
            investorContact: request.investorContact,
            mintPrice: request.mintPrice,
            expiry: request.expiry,
            paymentToken: request.paymentToken
        });

        // Hash the data according to EIP-712
        bytes32 digest = _hashTypedDataV4(data);

        // Recover the signer address
        address recoveredSigner = digest.recover(signature);

        // Check if the recovered signer is at least an admin
        BorgAuth(auth).onlyRole(BorgAuth(auth).ADMIN_ROLE(), recoveredSigner);
    }

    function _hashTypedDataV4(AuthorityData memory data) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        AUTHORITY_TYPEHASH,
                        data.uuid,
                        data.owner,
                        keccak256(bytes(data.investorName)),
                        keccak256(bytes(data.investorType)),
                        keccak256(bytes(data.investorJurisdiction)),
                        keccak256(bytes(data.investorContact)),
                        data.mintPrice,
                        data.expiry,
                        data.paymentToken
                    )
                )
            )
        );
    }

    // Admin functions
    function setLexchex(address _lexchex) external onlyOwner {
        lexchex = _lexchex;
    }

    function setDealRegistry(address _dealRegistry) external onlyOwner {
        dealRegistry = _dealRegistry;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    /// @dev Only owner can upgrade it
    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}
}
