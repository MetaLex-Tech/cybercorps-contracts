
import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";

contract UpgradeArbitraryLegalSigningScript is Script {
    function run() public {
        runWithArgs(
            // Production
            keccak256("MetaLex.ArbitraryLegalSigning.UpgradeV3.1.0"), // salt

            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
        );
    }

    function runWithArgs(bytes32 salt, uint256 deployerPrivateKey) public returns (
        BorgAuth,
        CyberAgreementRegistry
    ) {
        address deployer = vm.addr(deployerPrivateKey);

        // Existing MetaLeX contracts
        BorgAuth auth = BorgAuth(0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01);
        CyberAgreementRegistry registry = CyberAgreementRegistry(0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134);

        console2.log("deployer: %s", deployer);
        console2.log("AUTH: %s", address(auth));

        vm.startBroadcast(deployerPrivateKey);

        // 1) upgrade CyberAgreementRegistry
        address newRegistryImpl = address(
            new CyberAgreementRegistry{salt: salt}()
        );
        console2.log(
            "New CyberAgreementRegistry implementation:",
            newRegistryImpl
        );
        CyberAgreementRegistry(registry).upgradeToAndCall(newRegistryImpl, "");
        console2.log(
            "CyberAgreementRegistry upgraded (proxy via upgradeToAndCall):",
            address(registry)
        );

        vm.stopBroadcast();

        return (auth, registry);
    }
}
