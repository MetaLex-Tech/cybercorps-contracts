import {Script, console2} from "forge-std/Script.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {ERC1967ProxyLib} from "../test/libs/ERC1967ProxyLib.sol";

contract AcceptUpgradeRoundManagerScript is Script {
    using ERC1967ProxyLib for address;

    CyberCorpFactory cyberCorpFactory = CyberCorpFactory(0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2);

    function run(address corpAddr) public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY_MAIN"));

        RoundManagerFactory rmFactory = RoundManagerFactory(cyberCorpFactory.roundManagerFactory());
        RoundManager rm = RoundManager(CyberCorp(corpAddr).roundManager());

        address refRmImpl = rmFactory.getRefImplementation();
        vm.assertNotEq(address(rm).getErc1967Implementation(), refRmImpl, "Already at reference implementation, no need to upgrade");

        rm.upgradeToAndCall(refRmImpl, "");
        console2.log("CyberCorp: %s accepted RoundManager upgrade to: %s", corpAddr, refRmImpl);

        vm.stopBroadcast();
    }
}
