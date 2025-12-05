
import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";

contract DeployDevArbitraryLegalDocSignerRegistryScript is Script {
    function run() public {
        runWithArgs(
            keccak256("DeployDevArbitraryLegalDocSignerRegistryScript"), // salt
            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
        );
    }

    function runWithArgs(bytes32 salt, uint256 deployerPrivateKey) public returns (
        BorgAuth,
        CyberAgreementRegistry
    ) {
        address deployer = vm.addr(deployerPrivateKey);
        console2.log("deployer: %s", deployer);

        vm.startBroadcast(deployerPrivateKey);

        BorgAuth auth = new BorgAuth(deployer);

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

        console2.log("auth: %s", address(auth));
        console2.log("registry: %s", address(registry));

        return (auth, registry);
    }
}
