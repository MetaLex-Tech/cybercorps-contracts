// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BorgAuthV2} from "../src/BorgAuthV2.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {CompanyOfficer} from "../src/interfaces/ILedgerEntryToken.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @dev Local acceptance fixture only; not a production release registry or governance executor.
contract LocalCorporateAuthRegistry {
    address public borgAuthImplementation;
    address public refImplementation;
    address public immutable owner;

    constructor(address auth, address corp) {
        owner = msg.sender;
        borgAuthImplementation = auth;
        refImplementation = corp;
    }

    function approveAuthImplementation(address implementation) external {
        require(msg.sender == owner, "Local fixture owner only");
        borgAuthImplementation = implementation;
    }

    function getRefImplementation() external view returns (address) {
        return refImplementation;
    }
}

contract LocalCorporateAuthBoard {}

/// @notice Deploys a small stack to a disposable Anvil chain for signed success/refusal acceptance.
contract TestCorporateAuthLocal is Script {
    function run() external {
        require(block.chainid == 31337, "Local Anvil chain only");
        uint256 rootKey = vm.envUint("CORPORATE_AUTH_LOCAL_ROOT_KEY");
        address root = vm.addr(rootKey);
        address officer = vm.envAddress("CORPORATE_AUTH_LOCAL_OFFICER");
        vm.startBroadcast(rootKey);
        BorgAuthV2 implementation = new BorgAuthV2();
        CyberCorp corpImplementation = new CyberCorp();
        LocalCorporateAuthRegistry registry =
            new LocalCorporateAuthRegistry(address(implementation), address(corpImplementation));
        BorgAuthV2 auth = BorgAuthV2(
            address(
                new ERC1967Proxy(
                    address(implementation), abi.encodeCall(BorgAuthV2.initializeCorporate, (root, address(registry)))
                )
            )
        );
        CyberCorp corp = CyberCorp(
            address(
                new ERC1967Proxy(
                    address(corpImplementation),
                    abi.encodeCall(
                        CyberCorp.initialize,
                        (
                            address(auth),
                            "Local",
                            "Corp",
                            "DE",
                            "contact",
                            "dispute",
                            address(registry),
                            root,
                            CompanyOfficer(officer, "Officer", "contact", "CEO"),
                            address(registry),
                            address(0)
                        )
                    )
                )
            )
        );
        address board = address(new LocalCorporateAuthBoard());
        address issuance = address(new LocalCorporateAuthBoard());
        address deal = address(new LocalCorporateAuthBoard());
        address round = address(new LocalCorporateAuthBoard());
        auth.completeSetup(root, board, address(corp), officer, issuance, deal, round);
        registry.approveAuthImplementation(address(new BorgAuthV2()));
        vm.stopBroadcast();
        console2.log("CORPORATE_AUTH", address(auth));
        console2.log("CORPORATE_CORP", address(corp));
    }
}
