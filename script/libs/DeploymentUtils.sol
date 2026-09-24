// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {BorgAuth} from "../../src/libs/auth.sol";
import {GnosisTransaction} from "./safe.sol";
import {Vm, console2} from "forge-std/Test.sol";

// Access hidden cheatcodes
interface EnhancedVm is Vm {
    function serializeJsonType(string calldata typeDescription, bytes memory value)
        external
        pure
        returns (string memory json);
}

interface ICreateX {
    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address newContract);
}

/// @notice Stateless helpers for deploy scripts: CREATE3 through CreateX, checks of existing addresses, auth checks and
///         the Safe Transaction Builder format. `DeploymentScript` builds the deploy steps on them.
library DeploymentUtils {
    EnhancedVm constant vm = EnhancedVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @dev CreateX v1.0.0 has the same address and code on all our chains. See test/createx/.
    address constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    bytes32 constant CREATEX_CODE_HASH = 0xbd8a7ea8cfca7b4e5f5041d7d4b17bc317c5ce42cfbc42066a00cf26b43eb53f;
    /// @dev The init code of the helper that CreateX deploys with CREATE2 for each salt.
    bytes32 constant CREATEX_HELPER_INIT_CODE_HASH = keccak256(hex"67363d3d37363d34f03d5260086018f3");

    error CreateXCodeHashMismatch(bytes32 codeHash);
    error Create3AddressMismatch(address expected, address deployed);
    error ExistingCreate3AddressMismatch(address existing, address expected);
    error ExistingCreate3AddressHasNoCode(address existing);

    struct SafeTxImport {
        string version;
        string chainId;
        uint256 createdAt;
        SafeTxMeta meta;
        SafeTx[] transactions;
    }

    struct SafeTxMeta {
        string name;
        string description;
        string txBuilderVersion;
        string createdFromSafeAddress;
        string createdFromOwnerAddress;
        string checksum;
    }

    struct SafeTx {
        address to;
        string value;
        bytes data;
    }

    function formatSafeTxJson(GnosisTransaction[] memory safeTxs, uint256 chainId) internal returns (string memory) {
        SafeTx[] memory convertedSafeTxs = new SafeTx[](safeTxs.length);
        for (uint256 i = 0; i < safeTxs.length; i++) {
            convertedSafeTxs[i] =
                SafeTx({to: safeTxs[i].to, value: vm.toString(safeTxs[i].value), data: safeTxs[i].data});
        }

        return vm.serializeJsonType(
            // it is important to include the input argument names as the utility will use them
            "SafeTxImport(string version,string chainId,uint256 createdAt,SafeTxMeta meta,SafeTx[] transactions)SafeTxMeta(string name,string description,string txBuilderVersion,string createdFromSafeAddress,string createdFromOwnerAddress,string checksum)SafeTx(address to,string value,bytes data)",
            abi.encode(
                SafeTxImport({
                    version: "1.0",
                    chainId: vm.toString(chainId),
                    createdAt: block.timestamp * 1000,
                    meta: SafeTxMeta({
                        name: "Transactions Batch",
                        description: "",
                        txBuilderVersion: "",
                        createdFromSafeAddress: "",
                        createdFromOwnerAddress: "",
                        checksum: ""
                    }),
                    transactions: convertedSafeTxs
                })
            )
        );
    }

    /// @notice Deploys a contract with CREATE3 through CreateX.
    /// @dev The address depends only on the deployer and `saltStr`, so it is the same on all chains.
    ///      The code and the constructor arguments do not change it.
    ///      Call it inside the deployer's broadcast. From another sender, CreateX deploys to a different
    ///      address without a revert, so this function compares the result with the expected address.
    ///      Each salt works one time per chain.
    function deployCreate3(address deployer, string memory saltStr, bytes memory initCode)
        internal
        returns (address deployed)
    {
        if (CREATEX.codehash != CREATEX_CODE_HASH) revert CreateXCodeHashMismatch(CREATEX.codehash);
        bytes32 salt = create3Salt(deployer, saltStr);
        address expected = computeCreate3Address(deployer, salt);
        deployed = ICreateX(CREATEX).deployCreate3(salt, initCode);
        if (deployed != expected) revert Create3AddressMismatch(expected, deployed);
    }

    /// @notice Checks an existing address from DeploymentConstants before a deployment.
    /// @dev A CREATE3 address is checked. A CREATE2 address or a zero address is not checked.
    ///      Code at the CREATE3 address of the deployer and `saltStr` means that we deployed the contract
    ///      with CREATE3, so the existing address must be that address. No code there means that the contract
    ///      is not deployed with CREATE3, so the existing address must not be that address.
    ///      A failed check means that the script configuration is wrong.
    function verifyExisting(address existing, address deployer, string memory saltStr) internal view {
        address expected = computeCreate3Address(deployer, create3Salt(deployer, saltStr));
        if (expected.code.length != 0) {
            if (existing != expected) revert ExistingCreate3AddressMismatch(existing, expected);
        } else if (existing == expected) {
            // If this happens, you have recorded the wrong address in DeploymentConstants
            revert ExistingCreate3AddressHasNoCode(existing);
        }
    }

    /// @dev The first 20 bytes are the deployer, so only the deployer can use the salt.
    ///      Byte 21 is 0x00, so CreateX leaves the chain id out.
    ///      The last 11 bytes come from `saltStr`.
    function create3Salt(address deployer, string memory saltStr) internal pure returns (bytes32) {
        return bytes32(abi.encodePacked(deployer, bytes1(0x00), bytes11(keccak256(bytes(saltStr)))));
    }

    /// @dev CreateX hashes the deployer with the salt. It deploys a helper with CREATE2 at that salt,
    ///      and the helper deploys the contract with CREATE at nonce 1.
    function computeCreate3Address(address deployer, bytes32 salt) internal pure returns (address) {
        bytes32 guardedSalt = keccak256(abi.encodePacked(bytes32(uint256(uint160(deployer))), salt));
        address helper = vm.computeCreate2Address(guardedSalt, CREATEX_HELPER_INIT_CODE_HASH, CREATEX);
        return vm.computeCreateAddress(helper, 1);
    }

    /// @notice Tells if the account holds the owner role on the auth.
    function hasOwnerRole(address auth, address account) internal view returns (bool) {
        return BorgAuth(auth).userRoles(account) >= BorgAuth(auth).OWNER_ROLE();
    }

    function parseSafeTxJson(string memory json) internal returns (SafeTxImport memory) {
        return abi.decode(vm.parseJson(json), (SafeTxImport));
    }
}
