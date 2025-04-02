pragma solidity 0.8.28;

contract DeterministicDeployFactory {
    event ContractDeployed(address addr);

    function deploy(bytes32 salt, bytes memory bytecode) public returns (address) {
        address addr;
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(extcodesize(addr)) { revert(0, 0) }
        }
        emit ContractDeployed(addr);
        return addr;
    }
}
