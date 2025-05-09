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

pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./libs/auth.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract CyberAgreementRegistry is Initializable, UUPSUpgradeable, BorgAuthACL {
    using ECDSA for bytes32;
    // Domain information
    string public constant name = "CyberAgreementRegistry";
    string public version;
    bytes32 public DOMAIN_SEPARATOR;
    // Type hash for AgreementData
    bytes32 public SIGNATUREDATA_TYPEHASH;
    bytes32 public VOIDSIGNATUREDATA_TYPEHASH;

    struct Template {
        string legalContractUri; // Off-chain legal contract URI
        string title;
        string[] globalFields; // Field names that are the same for all agreements
        string[] partyFields; // party Fields that will be different per party
    }

    struct AgreementData {
        bytes32 templateId; // ID of the template this contract uses
        string[] globalValues; // Values for the global fields
        address[] parties; // List of parties who should sign. Use zeroAddress for unknown counterparty
        mapping(address => string[]) partyValues; // Each signer's field data
        mapping(address => uint256) signedAt; // Timestamp when each party signed (0 if unsigned)
        uint256 numSignatures; // Number of parties who have signed
        address finalizer;
        bool finalized;
        bool voided;
        bytes32 secretHash;
        uint256 expiry;
        address[] voidRequestedBy;
    }

    // This data is what is signed by each party
    struct SignatureData {
        bytes32 contractId;
        string legalContractUri;
        string[] globalFields;
        string[] partyFields;
        string[] globalValues;
        string[] partyValues;
    }

    struct VoidSignatureData {
        bytes32 contractId;
        address party;
    }

    // Closed Agreement Data
    mapping(bytes32 => string[]) public closedAgreementValues;

    // Mapping of templateId => template data
    mapping(bytes32 => Template) public templates;

    // Mapping of contractId => contract data
    mapping(bytes32 => AgreementData) public agreements;

    // A mapping connecting an address to all the agreements they are a party to
    mapping(address => bytes32[]) public agreementsForParty;

    event TemplateCreated(
        bytes32 indexed templateId,
        string indexed title,
        string legalContractUri,
        string[] globalFields,
        string[] signerFields
    );

    event ContractCreated(
        bytes32 indexed contractId,
        bytes32 indexed templateId,
        address[] parties
    );

    event AgreementSigned(
        bytes32 indexed contractId,
        address indexed party,
        uint256 timestamp
    );

    event VoidRequested(bytes32 indexed contractId, address indexed party);

    event ContractVoided(
        bytes32 indexed contractId,
        address[] voidSigners,
        uint256 timestamp
    );

    event ContractFinalized(
        bytes32 indexed contractId,
        address finalizer,
        uint256 timestamp
    );

    event ContractFullySigned(bytes32 indexed contractId, uint256 timestamp);

    error TemplateAlreadyExists();
    error TemplateDoesNotExist();
    error ContractAlreadyExists();
    error ContractDoesNotExist();
    error NotAParty();
    error SignatureVerificationFailed();
    error AlreadySigned();
    error MismatchedFieldsLength();
    error FirstPartyZeroAddress();
    error DuplicateParty();
    error TitleEmpty();
    error InvalidPartyCount();
    error ClosedAgreementPartyValueMismatch();
    error ContractAlreadyVoided();
    error NotFinalizer();
    error ContractAlreadyFinalized();
    error ContractNotFullySigned();
    error ContractExpired();
    error InvalidSecret();
    error MismatchedPartyValuesLength();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {}

    function initialize(address _auth) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);

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

        SIGNATUREDATA_TYPEHASH = keccak256(
            "SignatureData(bytes32 contractId,string legalContractUri,string[] globalFields,string[] partyFields,string[] globalValues,string[] partyValues)"
        );

        VOIDSIGNATUREDATA_TYPEHASH = keccak256(
            "VoidSignatureData(bytes32 contractId,address party)"
        );
    }

    modifier onlyFinalizer(bytes32 contractId) {
        if (
            agreements[contractId].finalizer != msg.sender &&
            agreements[contractId].finalizer != address(0)
        ) revert NotFinalizer();
        _;
    }

    function createTemplate(
        bytes32 templateId,
        string memory title,
        string memory legalContractUri,
        string[] memory globalFields,
        string[] memory partyFields
    ) external onlyOwner {
        if (bytes(templates[templateId].legalContractUri).length > 0) {
            revert TemplateAlreadyExists();
        }

        if (bytes(title).length == 0) {
            revert TitleEmpty();
        }

        templates[templateId] = Template({
            legalContractUri: legalContractUri,
            title: title,
            globalFields: globalFields,
            partyFields: partyFields
        });

        emit TemplateCreated(
            templateId,
            title,
            legalContractUri,
            globalFields,
            partyFields
        );
    }

    function createContract(
        bytes32 templateId,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        bytes32 secretHash,
        address finalizer,
        uint256 expiry
    ) external returns (bytes32 contractId) {
        contractId = keccak256(
            abi.encode(templateId, salt, globalValues, parties)
        );
        if (agreements[contractId].parties.length > 0) {
            revert ContractAlreadyExists();
        }

        Template storage template = templates[templateId];
        if (bytes(template.legalContractUri).length == 0) {
            revert TemplateDoesNotExist();
        }

        if (globalValues.length != template.globalFields.length) {
            revert MismatchedFieldsLength();
        }

        if (parties[0] == address(0)) {
            revert FirstPartyZeroAddress();
        }

        for (uint256 i = 0; i < parties.length; i++) {
            for (uint256 j = i + 1; j < parties.length; j++) {
                if (parties[i] == parties[j]) {
                    revert DuplicateParty();
                }
            }
        }

        AgreementData storage agreementData = agreements[contractId];
        agreementData.templateId = templateId;
        agreementData.globalValues = globalValues;
        agreementData.parties = parties;
        agreementData.finalizer = finalizer;
        agreementData.expiry = expiry;
        agreementData.secretHash = secretHash;

        //check all arrays inside partyValues are the same length
        for (uint256 i = 0; i < partyValues.length; i++) {
            if (partyValues[i].length != template.partyFields.length) {
                revert MismatchedFieldsLength();
            }
            //matching address cannot be 0
            if (parties[i] == address(0)) {
                revert FirstPartyZeroAddress();
            }
            //set agreement partyValues
            agreements[contractId].partyValues[parties[i]] = partyValues[i];
        }

        emit ContractCreated(contractId, templateId, parties);

        // Add to the party's list of agreements
        for (uint256 i = 0; i < parties.length; i++) {
            agreementsForParty[parties[i]].push(contractId);
        }
    }

    function signContract(
        bytes32 contractId,
        string[] memory partyValues,
        bytes calldata signature,
        bool fillUnallocated, // to fill a 0 address or not
        string memory secret
    ) external {
        signContractFor(
            msg.sender,
            contractId,
            partyValues,
            signature,
            fillUnallocated,
            secret
        );
    }

    function signContractFor(
        address signer,
        bytes32 contractId,
        string[] memory partyValues,
        bytes calldata signature,
        bool fillUnallocated, // to fill a 0 address or not
        string memory secret
    ) public {
        AgreementData storage agreementData = agreements[contractId];
        Template memory template = templates[agreementData.templateId];
        if (agreementData.parties.length == 0) revert ContractDoesNotExist();
        if (agreementData.signedAt[signer] != 0) revert AlreadySigned();
        if (isVoided(contractId)) revert ContractAlreadyVoided();
        if (agreementData.finalized) revert ContractAlreadyFinalized();
        if (agreementData.expiry > 0 && agreementData.expiry < block.timestamp)
            revert ContractExpired();

        if (!isParty(contractId, signer)) {
            if (
                agreementData.secretHash > 0 &&
                keccak256(abi.encode(secret)) != agreementData.secretHash
            ) revert InvalidSecret();
            // Not a named party, so check if there's an open slot
            uint256 firstOpenPartyIndex = getFirstOpenPartyIndex(contractId);
            if (firstOpenPartyIndex == 0 || !fillUnallocated)
                revert NotAParty();
            // There is a spare slot, assign the sender to this slot.
            agreementData.parties[firstOpenPartyIndex] = signer;
            agreementsForParty[agreementData.parties[firstOpenPartyIndex]].push(
                    contractId
                );
        }

        //verify if the contract is closed
        if (agreementData.partyValues[signer].length > 0) {
            //check that the submitted partyValues match
            if (
                keccak256(abi.encode(agreementData.partyValues[signer])) !=
                keccak256(abi.encode(partyValues))
            ) {
                revert ClosedAgreementPartyValueMismatch();
            }
        }

        // Verify the signature
        if (
            !_verifySignature(
                signer,
                SignatureData({
                    contractId: contractId,
                    legalContractUri: template.legalContractUri,
                    globalFields: template.globalFields,
                    partyFields: template.partyFields,
                    globalValues: agreementData.globalValues,
                    partyValues: partyValues
                }),
                signature
            )
        ) {
            revert SignatureVerificationFailed();
        }

        if (partyValues.length != template.partyFields.length)
            revert MismatchedFieldsLength();

        uint256 timestamp = block.timestamp;

        agreementData.partyValues[signer] = partyValues;
        agreementData.signedAt[signer] = timestamp;
        uint256 totalSignatures = ++agreementData.numSignatures;

        emit AgreementSigned(contractId, signer, timestamp);

        if (totalSignatures == agreementData.parties.length) {
            if (agreementData.finalizer == address(0)) {
                agreementData.finalized = true;
                emit ContractFinalized(contractId, msg.sender, timestamp);
            }

            emit ContractFullySigned(contractId, timestamp);
        }
    }

    function voidContractFor(
        bytes32 contractId,
        address party,
        bytes calldata signature
    ) public {
        //make sure the party is a party to the contract
        if (!isParty(contractId, party)) revert NotAParty();

        AgreementData storage agreementData = agreements[contractId];
        if (agreementData.finalized) revert ContractAlreadyFinalized();

        //verify the signature
        if (
            !_verifyVoidSignature(
                party,
                VoidSignatureData({contractId: contractId, party: party}),
                signature
            )
        ) revert SignatureVerificationFailed();

        for (uint256 i = 0; i < agreementData.voidRequestedBy.length; i++) {
            if (agreementData.voidRequestedBy[i] == party)
                revert ContractAlreadyVoided();
        }

        agreementData.voidRequestedBy.push(party);
        emit VoidRequested(contractId, party);

        if (agreementData.expiry < block.timestamp) {
            agreementData.voided = true;
        } else if (
            agreementData.voidRequestedBy.length ==
            agreementData.parties.length &&
            agreementData.voidRequestedBy.length > 0
        ) {
            agreementData.voided = true;
        } else if (
            agreementData.parties[0] == party &&
            agreementData.numSignatures == 1
        ) {
            agreementData.voided = true;
        }

        if (agreementData.voided)
            emit ContractVoided(
                contractId,
                agreementData.voidRequestedBy,
                block.timestamp
            );
    }

    function finalizeContract(
        bytes32 contractId
    ) public onlyFinalizer(contractId) {
        AgreementData storage agreementData = agreements[contractId];
        if (agreementData.finalized) revert ContractAlreadyFinalized();
        if (agreementData.parties.length == 0) revert ContractDoesNotExist();
        if (!allPartiesSigned(contractId)) revert ContractNotFullySigned();
        if (isVoided(contractId)) revert ContractAlreadyVoided();
        if (agreementData.expiry > 0 && agreementData.expiry < block.timestamp)
            revert ContractExpired();

        agreementData.finalized = true;
        emit ContractFinalized(contractId, msg.sender, block.timestamp);
    }

    function getParties(
        bytes32 contractId
    ) external view returns (address[] memory) {
        return agreements[contractId].parties;
    }

    function hasSigned(
        bytes32 contractId,
        address signer
    ) external view returns (bool) {
        if (signer == address(0)) revert NotAParty();
        return agreements[contractId].signedAt[signer] != 0;
    }

    function getSignatureTimestamp(
        bytes32 contractId,
        address signer
    ) external view returns (uint256) {
        return agreements[contractId].signedAt[signer];
    }

    function allPartiesSigned(bytes32 contractId) public view returns (bool) {
        return
            agreements[contractId].numSignatures ==
            agreements[contractId].parties.length;
    }

    function getContractDetails(
        bytes32 contractId
    )
        external
        view
        returns (
            bytes32 templateId,
            string memory legalContractUri,
            string[] memory globalFields,
            string[] memory partyFields,
            string[] memory globalValues,
            address[] memory parties,
            string[][] memory partyValues,
            uint256[] memory signedAt,
            uint256 numSignatures,
            bool isComplete
        )
    {
        AgreementData storage agreementData = agreements[contractId];
        Template memory template = templates[agreementData.templateId];

        if (agreementData.parties.length == 0) revert ContractDoesNotExist();

        // Collect all party values and timestamps
        string[][] memory allPartyValues = new string[][](
            agreementData.parties.length
        );
        uint256[] memory allSignedAt = new uint256[](
            agreementData.parties.length
        );

        for (uint256 i = 0; i < agreementData.parties.length; i++) {
            address party = agreementData.parties[i];
            allPartyValues[i] = agreementData.partyValues[party];
            allSignedAt[i] = agreementData.signedAt[party];
        }

        return (
            agreementData.templateId,
            template.legalContractUri,
            template.globalFields,
            template.partyFields,
            agreementData.globalValues,
            agreementData.parties,
            allPartyValues,
            allSignedAt,
            agreementData.numSignatures,
            agreementData.numSignatures == agreementData.parties.length
        );
    }

    function getTemplateDetails(
        bytes32 templateId
    )
        external
        view
        returns (
            string memory legalContractUri,
            string[] memory globalFields,
            string[] memory signerFields
        )
    {
        Template storage template = templates[templateId];
        if (bytes(template.legalContractUri).length == 0)
            revert TemplateDoesNotExist();

        return (
            template.legalContractUri,
            template.globalFields,
            template.partyFields
        );
    }

    function getSignerValues(
        bytes32 contractId,
        address signer
    ) external view returns (string[] memory signerValues) {
        AgreementData storage agreementData = agreements[contractId];
        return (agreementData.partyValues[signer]);
    }

    // This makes fetching all agreements for a party easier from a client, as the
    // default getter requires an index
    function getAgreementsForParty(
        address party
    ) external view returns (bytes32[] memory) {
        return agreementsForParty[party];
    }

    function isParty(
        bytes32 contractId,
        address user
    ) internal view returns (bool) {
        if (user == address(0)) {
            return false;
        }
        address[] memory parties = agreements[contractId].parties;
        for (uint256 i = 0; i < parties.length; i++) {
            if (parties[i] == user) {
                return true;
            }
        }
        return false;
    }

    function getFirstOpenPartyIndex(
        bytes32 contractId
    ) internal view returns (uint256) {
        AgreementData storage agreementData = agreements[contractId];
        for (uint256 i = 0; i < agreementData.parties.length; i++) {
            if (agreementData.parties[i] == address(0)) {
                return i;
            }
        }
        // NOTE: 0 can never be an open party
        return 0;
    }

    function getVoidRequestedBy(
        bytes32 contractId
    ) external view returns (address[] memory) {
        return agreements[contractId].voidRequestedBy;
    }

    function getContractJson(
        bytes32 contractId
    ) external view returns (string memory) {
        AgreementData storage agreementData = agreements[contractId];
        Template storage template = templates[agreementData.templateId];

        // Start with basic fields
        string memory json = string(
            abi.encodePacked(
                '{"templateId": "',
                _bytes32ToString(agreementData.templateId), // Corrected to use agreementData.templateId
                '", "title": "',
                template.title,
                '", "legalContractUri": "',
                template.legalContractUri,
                '", "ContractFields": {'
            )
        );

        // Add global fields and values as key-value pairs
        if (template.globalFields.length > 0) {
            for (uint256 i = 0; i < template.globalFields.length; i++) {
                json = string.concat(
                    json,
                    '"',
                    template.globalFields[i],
                    '": "',
                    agreementData.globalValues[i],
                    '"'
                );
                if (i + 1 < template.globalFields.length) {
                    json = string.concat(json, ",");
                }
            }
        }
        json = string.concat(json, '}, "parties": {');

        // Add parties and their values as key-value pairs
        if (agreementData.parties.length > 0) {
            for (uint256 i = 0; i < agreementData.parties.length; i++) {
                address party = agreementData.parties[i];
                json = string.concat(
                    json,
                    '"',
                    _addressToString(party),
                    '": {'
                );

                // Add party fields and values
                if (template.partyFields.length > 0) {
                    string[] memory values = agreementData.partyValues[party];
                    for (uint256 j = 0; j < template.partyFields.length; j++) {
                        json = string.concat(
                            json,
                            '"',
                            template.partyFields[j],
                            '": "'
                        );
                        if (values.length > j) {
                            json = string.concat(json, values[j]);
                        }
                        json = string.concat(json, '"');
                        if (j + 1 < template.partyFields.length) {
                            json = string.concat(json, ",");
                        }
                    }
                }

                // Add signature timestamp
                if (template.partyFields.length > 0) {
                    json = string.concat(json, ",");
                }
                json = string.concat(
                    json,
                    '"signedAt": ',
                    _uint256ToString(agreementData.signedAt[party])
                );
                json = string.concat(json, "}");

                if (i + 1 < agreementData.parties.length) {
                    json = string.concat(json, ",");
                }
            }
        }

        // Add metadata
        json = string.concat(
            json,
            '}, "numSignatures": ',
            _uint256ToString(agreementData.numSignatures)
        );
        json = string.concat(
            json,
            ', "isComplete": ',
            agreementData.numSignatures == agreementData.parties.length
                ? "true"
                : "false"
        );
        // Add voided status
        json = string.concat(
            json,
            ', "voided": ',
            agreementData.voided ? "true" : "false"
        );
        // loop and add voidRequestedBy
        json = string.concat(json, ', "voidRequestedBy": [');
        for (uint256 i = 0; i < agreementData.voidRequestedBy.length; i++) {
            json = string.concat(
                json,
                '"',
                _addressToString(agreementData.voidRequestedBy[i]),
                '"'
            );
            if (i + 1 < agreementData.voidRequestedBy.length) {
                json = string.concat(json, ",");
            }
        }
        json = string.concat(json, "]");
        // add finalized status
        json = string.concat(
            json,
            ', "finalized": ',
            agreementData.finalized ? "true" : "false"
        );
        json = string.concat(json, "}");
        return json;
    }

    function _verifySignature(
        address signer,
        SignatureData memory data,
        bytes memory signature
    ) internal view returns (bool) {
        // Hash the data (AgreementData) according to EIP-712
        bytes32 digest = _hashTypedDataV4(data);

        // Recover the signer address
        address recoveredSigner = digest.recover(signature);

        // Check if the recovered address matches the expected signer
        return recoveredSigner == signer;
    }

    // Helper function to hash the typed data (SignatureData) according to EIP-712
    function _hashTypedDataV4(
        SignatureData memory data
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    keccak256(
                        abi.encode(
                            SIGNATUREDATA_TYPEHASH,
                            data.contractId,
                            keccak256(bytes(data.legalContractUri)),
                            _hashStringArray(data.globalFields),
                            _hashStringArray(data.partyFields),
                            _hashStringArray(data.globalValues),
                            _hashStringArray(data.partyValues)
                        )
                    )
                )
            );
    }

    // Helper function to hash string arrays
    function _hashStringArray(
        string[] memory array
    ) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](array.length);
        for (uint256 i = 0; i < array.length; i++) {
            hashes[i] = keccak256(bytes(array[i]));
        }
        return keccak256(abi.encodePacked(hashes));
    }

    // Helper function to convert bytes32 to string
    function _bytes32ToString(
        bytes32 _bytes32
    ) internal pure returns (string memory) {
        bytes memory bytesArray = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            uint8 b = uint8(uint8(bytes1(bytes32(_bytes32) >> (8 * (31 - i)))));
            bytesArray[i * 2] = bytes1(uint8(b / 16 + (b / 16 < 10 ? 48 : 87)));
            bytesArray[i * 2 + 1] = bytes1(
                uint8((b % 16) + (b % 16 < 10 ? 48 : 87))
            );
        }
        return string(bytesArray);
    }

    // Helper function to convert address to string
    function _addressToString(
        address _addr
    ) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint160(_addr) >> (8 * (19 - i))));
            uint8 hi = uint8(b) >> 4;
            uint8 lo = uint8(b) & 0x0f;
            s[2 * i] = bytes1(hi + (hi < 10 ? 48 : 87));
            s[2 * i + 1] = bytes1(lo + (lo < 10 ? 48 : 87));
        }
        return string(abi.encodePacked("0x", s));
    }

    // Helper function to convert uint256 to string
    function _uint256ToString(
        uint256 _i
    ) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = uint8(48 + (_i % 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function isFinalized(bytes32 contractId) external view returns (bool) {
        return agreements[contractId].finalized;
    }

    function isVoided(bytes32 contractId) public view returns (bool) {
        return agreements[contractId].voided;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}

    function _verifyVoidSignature(
        address signer,
        VoidSignatureData memory data,
        bytes memory signature
    ) internal view returns (bool) {
        // Hash the data (VoidSignatureData) according to EIP-712
        bytes32 digest = _hashVoidTypedDataV4(data);

        // Recover the signer address
        address recoveredSigner = digest.recover(signature);

        // Check if the recovered address matches the expected signer
        return recoveredSigner == signer;
    }

    // Helper function to hash the typed data (VoidSignatureData) according to EIP-712
    function _hashVoidTypedDataV4(
        VoidSignatureData memory data
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    keccak256(
                        abi.encode(
                            VOIDSIGNATUREDATA_TYPEHASH,
                            data.contractId,
                            data.party
                        )
                    )
                )
            );
    }
}
