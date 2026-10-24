"""Local-only Anvil deployment and sign/simulate/submit rehearsal with public toy keys.

No external RPC or account is accepted. Artifacts remain under script/res/bound-registry-rehearsal/.
The authority is a one-owner contract stand-in, not a real Safe.
"""
import json
import os
from pathlib import Path
import socket
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
IMPLEMENTATION_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
DEPLOYER_KEY = "0x" + f"{0xB0B:064x}"
OWNER_KEY = "0x" + f"{0xA11CE:064x}"


def command(*args, ok=True):
    result = subprocess.run(args, cwd=ROOT, text=True, encoding="utf-8", errors="replace", capture_output=True, timeout=300)
    if (result.returncode == 0) != ok:
        raise RuntimeError(result.stdout[-6000:] + result.stderr[-3000:])
    return result.stdout.strip()


def calldata(signature, *args):
    return command("cast", "calldata", signature, *args)


def main():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    url = f"http://127.0.0.1:{port}"
    def rpc(method, *params):
        return json.loads(command("cast", "rpc", "--rpc-url", url, "--raw", method, json.dumps(params)))
    relative = Path("script/res/bound-registry-rehearsal") / uuid.uuid4().hex[:12]
    directory = ROOT / relative
    directory.mkdir(parents=True)
    prefix = (relative / "release").as_posix()
    fixture_path = (relative / "fixture.json").as_posix()
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    with (directory / "anvil.log").open("w", encoding="utf-8") as log:
        node = subprocess.Popen(["anvil", "--host", "127.0.0.1", "--port", str(port), "--chain-id", "31337"],
                                cwd=ROOT, stdout=log, stderr=log, creationflags=flags)
        try:
            for _ in range(40):
                try:
                    if int(rpc("eth_chainId"), 16) == 31337:
                        break
                except RuntimeError:
                    pass
                time.sleep(0.25)
            else:
                raise RuntimeError("Anvil did not start")
            deployer = command("cast", "wallet", "address", "--private-key", DEPLOYER_KEY)
            owner = command("cast", "wallet", "address", "--private-key", OWNER_KEY)
            for address in (deployer, owner):
                rpc("anvil_setBalance", address, hex(100 * 10**18))
            common = ("--use", "0.8.28", "--rpc-url", url, "--sender", deployer, "--private-key", DEPLOYER_KEY)
            fixture_log = command("forge", "script", "test/fixtures/BoundRegistryUpgradeRehearsal.s.sol:BoundRegistryUpgradeRehearsal",
                                  "--sig", "run(string,address)", fixture_path, owner, *common, "--broadcast", "--slow")
            (directory / "fixture.log").write_text(fixture_log, encoding="utf-8")
            fixture = json.loads((ROOT / fixture_path).read_text())
            proxy, authority = fixture["proxy"], fixture["authority"]
            # Grant the deployment wallet owner access through the local authority contract.
            role_data = calldata("updateRole(address,uint256)", deployer, "99")
            command("cast", "send", authority, "execute(address,bytes)", fixture["auth"], role_data,
                    "--rpc-url", url, "--private-key", OWNER_KEY, "--json")
            before = rpc("eth_getStorageAt", proxy, IMPLEMENTATION_SLOT, "latest")
            script = "script/deploy-bound-agreement-registry.s.sol:DeployBoundAgreementRegistryScript"
            signature = "runWithArgs(uint256,address,address,string)"
            # Wrong chain must fail without changing the deployment nonce.
            nonce = rpc("eth_getTransactionCount", deployer, "latest")
            command("forge", "script", script, "--sig", signature, "1", proxy, authority, prefix, *common, ok=False)
            assert rpc("eth_getTransactionCount", deployer, "latest") == nonce
            # A dry run writes preview JSON but does not deploy or upgrade anything.
            command("forge", "script", script, "--sig", signature, "31337", proxy, authority, prefix, *common)
            assert rpc("eth_getTransactionCount", deployer, "latest") == nonce
            assert rpc("eth_getStorageAt", proxy, IMPLEMENTATION_SLOT, "latest") == before
            deploy_log = command("forge", "script", script, "--sig", signature, "31337", proxy, authority, prefix,
                                 *common, "--broadcast", "--slow")
            (directory / "deployment.log").write_text(deploy_log, encoding="utf-8")
            assert rpc("eth_getStorageAt", proxy, IMPLEMENTATION_SLOT, "latest") == before
            batch = json.loads((ROOT / (prefix + ".json")).read_text())
            assert batch["chainId"] == "31337" and len(batch["transactions"]) == 1
            tx = batch["transactions"][0]
            assert tx["to"].lower() == proxy.lower() and tx["value"] == "0"
            candidate = "0x" + tx["data"][10:74][-40:]
            assert tx["data"].lower() == calldata("upgradeToAndCall(address,bytes)", candidate, "0x").lower()
            assert rpc("eth_getCode", candidate, "latest") != "0x"
            owner_call = calldata("execute(address,bytes)", tx["to"], tx["data"])
            # The stand-in refuses anyone other than its owner, even the registry-owner deployer.
            try:
                rpc("eth_call", {"from": deployer, "to": authority, "data": owner_call}, "latest")
            except RuntimeError:
                pass
            else:
                raise AssertionError("Unauthorized authority execution accepted")
            # Sign first, simulate the exact signed call's fields, then submit raw bytes to localhost.
            nonce = int(rpc("eth_getTransactionCount", owner, "latest"), 16)
            gas_price = int(rpc("eth_gasPrice"), 16)
            raw = command("cast", "mktx", authority, "execute(address,bytes)", tx["to"], tx["data"], "--private-key", OWNER_KEY,
                          "--chain", "31337", "--nonce", str(nonce), "--gas-limit", "1000000",
                          "--gas-price", str(gas_price), "--legacy")
            assert rpc("eth_call", {"from": owner, "to": authority, "data": owner_call, "value": "0x0",
                                    "gas": hex(1_000_000), "gasPrice": hex(gas_price)}, "latest") == "0x"
            tx_hash = rpc("eth_sendRawTransaction", raw)
            receipt = rpc("eth_getTransactionReceipt", tx_hash)
            assert receipt and int(receipt["status"], 16) == 1
            assert rpc("eth_getStorageAt", proxy, IMPLEMENTATION_SLOT, "latest")[-40:].lower() == candidate[2:].lower()
            assert rpc("eth_call", {"to": proxy, "data": calldata("getContractJson(bytes32)", "0x" + "00" * 32)}, "latest") != "0x"
            (directory / "upgrade-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
            print(f"PASS: local deploy, direct Safe JSON, unauthorized refusal, sign/simulate/submit and linked JSON readback.\nEvidence: {directory}")
        finally:
            node.terminate()
            try:
                node.wait(timeout=10)
            except subprocess.TimeoutExpired:
                node.kill()
                node.wait()


if __name__ == "__main__":
    main()
