// SPDX-License-Identifier: unlicensed
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./libs/auth.sol";

contract CyberDealRegistry is Initializable, UUPSUpgradeable, BorgAuthACL {
    struct Template {
        string legalContractUri; // Off-chain legal contract URI
        string title;
        string[] globalFields; // Field names that are the same for all contracts
        string[] partyFields; // party Fields that will be different per party
    }

    struct ContractData {
        bytes32 templateId; // ID of the template this contract uses
        string[] globalValues; // Values for the global fields
        address[] parties; // List of parties who should sign. Use zeroAddress for unknown counterparty
        mapping(address => string[]) partyValues; // Each signer's field data
        mapping(address => uint256) signedAt; // Timestamp when each party signed (0 if unsigned)
        uint256 numSignatures; // Number of parties who have signed
        bytes32 transactionHash; // Hash of the transaction that created this contract
    }

    // Mapping of templateId => template data
    mapping(bytes32 => Template) public templates;

    // Mapping of contractId => contract data
    mapping(bytes32 => ContractData) public contracts;

    // A mapping connecting an address to all the contracts they are a party to
    mapping(address => bytes32[]) public contractsForParty;

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

    event ContractSigned(
        bytes32 indexed contractId,
        address indexed party,
        uint256 timestamp
    );

    event ContractFullySigned(bytes32 indexed contractId, uint256 timestamp);

    error TemplateAlreadyExists();
    error TemplateDoesNotExist();
    error ContractAlreadyExists();
    error ContractDoesNotExist();
    error NotAParty();
    error AlreadySigned();
    error MismatchedFieldsLength();
    error FirstPartyZeroAddress();
    error DuplicateParty();
    error TitleEmpty();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
    }

    function initialize(address _auth) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    function createTemplate(
        bytes32 templateId,
        string memory title,
        string memory legalContractUri,
        string[] memory globalFields,
        string[] memory partyFields
    ) external {
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
        bytes32 contractId,
        bytes32 templateId,
        string[] memory globalValues,
        address[] memory parties
    ) external onlyAdmin {
        if (contracts[contractId].parties.length > 0) {
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

        ContractData storage contractData = contracts[contractId];
        contractData.templateId = templateId;
        contractData.globalValues = globalValues;
        contractData.parties = parties;
        contractData.transactionHash = blockhash(block.number - 1); // Store the transaction hash

        emit ContractCreated(contractId, templateId, parties);

        // Add to the party's list of contracts
        for (uint256 i = 0; i < parties.length; i++) {
            contractsForParty[parties[i]].push(contractId);
        }
    }

    function signContract(
        bytes32 contractId,
        string[] memory partyValues,
        bool fillUnallocated // to fill a 0 address or not
    ) external {
        ContractData storage contractData = contracts[contractId];
        if (contractData.parties.length == 0) revert ContractDoesNotExist();
        if (contractData.signedAt[msg.sender] != 0) revert AlreadySigned();

        if (!isParty(contractId, msg.sender)) {
            // Not a named party, so check if there's an open slot
            uint256 firstOpenPartyIndex = getFirstOpenPartyIndex(contractId);
            if (firstOpenPartyIndex == 0 || !fillUnallocated)
                revert NotAParty();
            // There is a spare slot, assign the sender to this slot.
            contractData.parties[firstOpenPartyIndex] = msg.sender;
        }

        Template storage template = templates[contractData.templateId];
        if (partyValues.length != template.partyFields.length)
            revert MismatchedFieldsLength();

        uint256 timestamp = block.timestamp;

        contractData.partyValues[msg.sender] = partyValues;
        contractData.signedAt[msg.sender] = timestamp;
        uint256 totalSignatures = ++contractData.numSignatures;

        emit ContractSigned(contractId, msg.sender, timestamp);

        if (totalSignatures == contractData.parties.length) {
            emit ContractFullySigned(contractId, timestamp);
        }
    }

     function getParties(
        bytes32 contractId
    ) external view returns (address[] memory) {
        return contracts[contractId].parties;
    }

    function hasSigned(
        bytes32 contractId,
        address signer
    ) external view returns (bool) {
        if (signer == address(0)) revert NotAParty();
        return contracts[contractId].signedAt[signer] != 0;
    }

    function getSignatureTimestamp(
        bytes32 contractId,
        address signer
    ) external view returns (uint256) {
        return contracts[contractId].signedAt[signer];
    }

    function allPartiesSigned(bytes32 contractId) external view returns (bool) {
        return
            contracts[contractId].numSignatures ==
            contracts[contractId].parties.length;
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
            bool isComplete,
            bytes32 transactionHash
        )
    {
        ContractData storage contractData = contracts[contractId];
        Template memory template = templates[contractData.templateId];

        if (contractData.parties.length == 0) revert ContractDoesNotExist();

        // Collect all party values and timestamps
        string[][] memory allPartyValues = new string[][](contractData.parties.length);
        uint256[] memory allSignedAt = new uint256[](contractData.parties.length);

        for (uint256 i = 0; i < contractData.parties.length; i++) {
            address party = contractData.parties[i];
            allPartyValues[i] = contractData.partyValues[party];
            allSignedAt[i] = contractData.signedAt[party];
        }

        return (
            contractData.templateId,
            template.legalContractUri,
            template.globalFields,
            template.partyFields,
            contractData.globalValues,
            contractData.parties,
            allPartyValues,
            allSignedAt,
            contractData.numSignatures,
            contractData.numSignatures == contractData.parties.length,
            contractData.transactionHash
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
        ContractData storage contractData = contracts[contractId];
        return (contractData.partyValues[signer]);
    }

    // This makes fetching all contracts for a party easier from a client, as the
    // default getter requires an index
    function getContractsForParty(
        address party
    ) external view returns (bytes32[] memory) {
        return contractsForParty[party];
    }

    function isParty(
        bytes32 contractId,
        address user
    ) internal view returns (bool) {
        if (user == address(0)) {
            return false;
        }
        address[] memory parties = contracts[contractId].parties;
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
        ContractData storage contractData = contracts[contractId];
        for (uint256 i = 0; i < contractData.parties.length; i++) {
            if (contractData.parties[i] == address(0)) {
                return i;
            }
        }
        // NOTE: 0 can never be an open party
        return 0;
    }

    function getContractURI(bytes32 contractId) external view returns (string memory) {
        ContractData storage contractData = contracts[contractId];
        Template storage template = templates[contractData.templateId];
        
        // Start with basic fields
        string memory json = string(abi.encodePacked(
            '{"templateId": "', 
            _bytes32ToString(contractId), 
            '", "title": "', 
            template.title, 
            '", "legalContractUri": "', 
            template.legalContractUri, 
            '", "ContractFields": {'
        ));

        // Add global fields and values as key-value pairs
        for (uint256 i = 0; i < template.globalFields.length; i++) {
            json = string.concat(json, '"', template.globalFields[i], '": "', contractData.globalValues[i], '"');
            if (i < template.globalFields.length - 1) {
                json = string.concat(json, ',');
            }
        }
        json = string.concat(json, '}, "parties": {');

        // Add parties and their values as key-value pairs
        for (uint256 i = 0; i < contractData.parties.length; i++) {
            address party = contractData.parties[i];
            json = string.concat(json, '"', _addressToString(party), '": {');
            
            //check if parties have added their values and if not, add a blank value
            if(contractData.partyValues[party].length > i)
            {
                // Add party fields and values
                string[] memory values = contractData.partyValues[party];
                for (uint256 j = 0; j < template.partyFields.length; j++) {
                    json = string.concat(json, '"', template.partyFields[j], '": "', values[j], '"');
                    if (j < template.partyFields.length - 1) {
                        json = string.concat(json, ',');
                    }
                }
            }
            
            // Add signature timestamp
            json = string.concat(json, ', "signedAt": ', _uint256ToString(contractData.signedAt[party]));
            json = string.concat(json, '}');
            
            if (i < contractData.parties.length - 1) {
                json = string.concat(json, ',');
            }
        }
        
        // Add metadata
        json = string.concat(json, '}, "numSignatures": ', _uint256ToString(contractData.numSignatures));
        json = string.concat(json, ', "isComplete": ', contractData.numSignatures == contractData.parties.length ? 'true' : 'false');
        json = string.concat(json, ', "isSigned": ', contractData.signedAt[msg.sender] != 0 ? 'true' : 'false');
        json = string.concat(json, '}');
        return json;
    }

    // Helper function to convert bytes32 to string
    function _bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
        bytes memory bytesArray = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            bytes1 char = bytes1(bytes32(uint256(_bytes32) * 2 ** (8 * i)));
            bytesArray[i*2] = char;
            bytesArray[i*2+1] = char;
        }
        return string(bytesArray);
    }

    // Helper function to convert address to string
    function _addressToString(address _addr) internal pure returns (string memory) {
        bytes memory s = new bytes(42);
        s[0] = "0";
        s[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint256(uint160(_addr)) / (2**(8*(19 - i)))));
            uint8 hi = uint8(b) / 16;
            uint8 lo = uint8(b) - 16 * hi;
            s[2+2*i] = hi >= 10 ? bytes1(hi + 87) : bytes1(hi + 48);
            s[2+2*i+1] = lo >= 10 ? bytes1(lo + 87) : bytes1(lo + 48);
        }
        return string(s);
    }

    // Helper function to convert uint256 to string
    function _uint256ToString(uint256 _i) internal pure returns (string memory) {
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
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    // Add a function to get the transaction hash
    function getContractTransactionHash(bytes32 contractId) external view returns (bytes32) {
        return contracts[contractId].transactionHash;
    }
}
