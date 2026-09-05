// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {CyberCorp} from "../src/CyberCorp.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {MetaDAOFactory} from "../src/MetaDAOFactory.sol";
import {ParentCoFactory} from "../src/ParentCoFactory.sol";
import {PumpCorpFactory} from "../src/PumpCorpFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";

interface IUUPSBoardFactory {
    function AUTH() external view returns (BorgAuth);
    function cyberCorpSingleFactory() external view returns (address);
    function setCyberCorpSingleFactory(address newSingleFactory) external;
    function upgradeToAndCall(
        address newImplementation,
        bytes calldata data
    ) external payable;
}

/// @notice Installs the v5 Board-authority path for future deployments only.
/// @dev Deploys a separate v5 single factory and atomically pairs each supplied
///      top-level proxy upgrade with that pointer. The legacy single factory is
///      read for auth/reference checks but never mutated. This deliberately
///      does not migrate or activate any existing CyberCorp.
contract UpgradeBoardAuthorityForwardPathScript is Script {
    bytes32 internal constant CYBERCORP_SALT =
        keccak256("MetaLexCyberCorp.BoardAuthority.CyberCorp.v5");
    bytes32 internal constant SINGLE_FACTORY_IMPLEMENTATION_SALT =
        keccak256(
            "MetaLexCyberCorp.BoardAuthority.CyberCorpSingleFactory.implementation.v1"
        );
    bytes32 internal constant SINGLE_FACTORY_PROXY_SALT =
        keccak256(
            "MetaLexCyberCorp.BoardAuthority.CyberCorpSingleFactory.proxy.v1"
        );
    bytes32 internal constant CYBERCORP_FACTORY_SALT =
        keccak256("MetaLexCyberCorp.BoardAuthority.CyberCorpFactory.v1");
    bytes32 internal constant PUMP_FACTORY_SALT =
        keccak256("MetaLexCyberCorp.BoardAuthority.PumpCorpFactory.v1");
    bytes32 internal constant PARENT_FACTORY_SALT =
        keccak256("MetaLexCyberCorp.BoardAuthority.ParentCoFactory.v1");
    bytes32 internal constant METADAO_FACTORY_SALT =
        keccak256("MetaLexCyberCorp.BoardAuthority.MetaDAOFactory.v1");

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployer = vm.addr(privateKey);
        address legacySingleFactoryAddress = vm.envAddress(
            "CYBERCORP_SINGLE_FACTORY"
        );

        address cyberCorpFactoryAddress = vm.envOr(
            "CYBERCORP_FACTORY",
            address(0)
        );
        address pumpFactoryAddress = vm.envOr(
            "PUMP_CORP_FACTORY",
            address(0)
        );
        address parentFactoryAddress = vm.envOr(
            "PARENT_CO_FACTORY",
            address(0)
        );
        address metaDAOFactoryAddress = vm.envOr(
            "METADAO_FACTORY",
            address(0)
        );

        _assertOwner(legacySingleFactoryAddress, deployer);
        _assertOptionalOwner(cyberCorpFactoryAddress, deployer);
        _assertOptionalOwner(pumpFactoryAddress, deployer);
        _assertOptionalOwner(parentFactoryAddress, deployer);
        _assertOptionalOwner(metaDAOFactoryAddress, deployer);

        CyberCorpSingleFactory legacySingleFactory =
            CyberCorpSingleFactory(legacySingleFactoryAddress);
        address legacyReference =
            legacySingleFactory.getRefImplementation();
        BorgAuth singleFactoryAuth = legacySingleFactory.AUTH();

        vm.startBroadcast(privateKey);

        CyberCorp newCyberCorp = new CyberCorp{salt: CYBERCORP_SALT}();
        CyberCorpSingleFactory newSingleFactory = CyberCorpSingleFactory(
            address(
                new ERC1967Proxy{salt: SINGLE_FACTORY_PROXY_SALT}(
                    address(
                        new CyberCorpSingleFactory{
                            salt: SINGLE_FACTORY_IMPLEMENTATION_SALT
                        }()
                    ),
                    abi.encodeCall(
                        CyberCorpSingleFactory.initialize,
                        (address(singleFactoryAuth), address(newCyberCorp))
                    )
                )
            )
        );

        if (cyberCorpFactoryAddress != address(0)) {
            CyberCorpFactory implementation = new CyberCorpFactory{
                salt: CYBERCORP_FACTORY_SALT
            }();
            IUUPSBoardFactory(cyberCorpFactoryAddress).upgradeToAndCall(
                address(implementation),
                abi.encodeCall(
                    IUUPSBoardFactory.setCyberCorpSingleFactory,
                    (address(newSingleFactory))
                )
            );
        }
        if (pumpFactoryAddress != address(0)) {
            PumpCorpFactory implementation = new PumpCorpFactory{
                salt: PUMP_FACTORY_SALT
            }();
            IUUPSBoardFactory(pumpFactoryAddress).upgradeToAndCall(
                address(implementation),
                abi.encodeCall(
                    IUUPSBoardFactory.setCyberCorpSingleFactory,
                    (address(newSingleFactory))
                )
            );
        }
        if (parentFactoryAddress != address(0)) {
            ParentCoFactory implementation = new ParentCoFactory{
                salt: PARENT_FACTORY_SALT
            }();
            IUUPSBoardFactory(parentFactoryAddress).upgradeToAndCall(
                address(implementation),
                abi.encodeCall(
                    IUUPSBoardFactory.setCyberCorpSingleFactory,
                    (address(newSingleFactory))
                )
            );
        }
        if (metaDAOFactoryAddress != address(0)) {
            MetaDAOFactory implementation = new MetaDAOFactory{
                salt: METADAO_FACTORY_SALT
            }();
            IUUPSBoardFactory(metaDAOFactoryAddress).upgradeToAndCall(
                address(implementation),
                abi.encodeCall(
                    IUUPSBoardFactory.setCyberCorpSingleFactory,
                    (address(newSingleFactory))
                )
            );
        }

        vm.stopBroadcast();

        require(
            newSingleFactory.getRefImplementation() == address(newCyberCorp),
            "CyberCorp reference implementation mismatch"
        );
        require(
            legacySingleFactory.getRefImplementation() == legacyReference,
            "legacy single-factory reference changed"
        );
        require(
            keccak256(bytes(newCyberCorp.DEPLOY_VERSION())) ==
                keccak256(bytes("5")),
            "unexpected CyberCorp version"
        );
        _assertOptionalSingleFactory(
            cyberCorpFactoryAddress,
            address(newSingleFactory)
        );
        _assertOptionalSingleFactory(
            pumpFactoryAddress,
            address(newSingleFactory)
        );
        _assertOptionalSingleFactory(
            parentFactoryAddress,
            address(newSingleFactory)
        );
        _assertOptionalSingleFactory(
            metaDAOFactoryAddress,
            address(newSingleFactory)
        );

        console2.log("CyberCorp v5 reference:", address(newCyberCorp));
        console2.log(
            "Legacy CyberCorpSingleFactory (unchanged):",
            legacySingleFactoryAddress
        );
        console2.log(
            "CyberCorpSingleFactory v5:",
            address(newSingleFactory)
        );
        console2.log(
            "Existing corps were not upgraded or governance-activated."
        );
    }

    function _assertOptionalOwner(
        address target,
        address deployer
    ) internal view {
        if (target != address(0)) _assertOwner(target, deployer);
    }

    function _assertOptionalSingleFactory(
        address target,
        address expectedSingleFactory
    ) internal view {
        if (target == address(0)) return;
        if (
            IUUPSBoardFactory(target).cyberCorpSingleFactory() !=
                expectedSingleFactory
        ) {
            revert("top-level factory single-factory mismatch");
        }
    }

    function _assertOwner(address target, address deployer) internal view {
        BorgAuth auth = IUUPSBoardFactory(target).AUTH();
        if (auth.userRoles(deployer) < auth.OWNER_ROLE()) {
            revert("deployer is not target AUTH owner");
        }
    }
}
