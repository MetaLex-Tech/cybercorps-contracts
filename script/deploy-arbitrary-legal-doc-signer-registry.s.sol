
import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";

contract DeployArbitraryLegalDocSignerRegistryScript is Script {
    function run() public {
        runWithArgs(
            // Production
            keccak256("ArbitraryLegalDocSignerRegistry.v1.0.0"), // salt

            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
        );
    }

    function runWithArgs(bytes32 salt, uint256 deployerPrivateKey) public returns (
        BorgAuth,
        CyberAgreementRegistry
    ) {
        address deployer = vm.addr(deployerPrivateKey);

        // Use MetaLeX AUTH
        BorgAuth auth = BorgAuth(0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01);

        console2.log("deployer: %s", deployer);
        console2.log("AUTH: %s", address(auth));

        vm.startBroadcast(deployerPrivateKey);

        CyberAgreementRegistry registry = CyberAgreementRegistry(address(
            new ERC1967Proxy{salt: salt}(
                address(new CyberAgreementRegistry{salt: salt}()),
                abi.encodeWithSelector(
                    CyberAgreementRegistry.initialize.selector,
                    address(auth)
                )
            )
        ));

        vm.stopBroadcast();

        console2.log("==== Deployed contracts ====");
        console2.log("registry: %s", address(registry));

        return (auth, registry);
    }
}
