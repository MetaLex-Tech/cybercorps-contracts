// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./baseCondition.sol";
import "../../interfaces/ILexChex.sol";
import "../LexScroWLite.sol";
import "../auth.sol";

/// @title  LexChexCondition - A condition that checks if the user has a valid LexChex accreditation
/// @author MetaLeX Labs, Inc.

contract LexChexCondition is BaseCondition, BorgAuthACL {

    address public lexchex;
    string public constant NAME = "LexChexCondition";
    uint256 public constant VERSION = 1;

    /// @notice Empty constructor for implementation contract
    constructor() {
    }

    /// @notice Initializer replacing the constructor
    /// @param _lexchex Address of the LexChex contract
    /// @param _auth Address of the BorgAuth contract
    function initialize(address _lexchex, address _auth) public initializer {
        lexchex = _lexchex;
        __BorgAuthACL_init(_auth);
    }

    function checkCondition(address _contract, bytes4 _functionSignature, bytes memory data) public view override returns (bool) {
        LexScroWLite lexScrow = LexScroWLite(_contract);
        bytes32 agreementId = abi.decode(data, (bytes32));
        
        // Get the counterparty address directly from escrow details
        address counterparty = lexScrow.getEscrowDetails(agreementId).counterParty;
        return ILexChex(lexchex).hasValidLexCheX(counterparty);
    }

    function updateLexChex(address _lexchex) public onlyAdmin {
        lexchex = _lexchex;
    }

    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        return interfaceId == type(ICondition).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}