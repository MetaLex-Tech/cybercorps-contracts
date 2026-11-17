"""Local Anvil deployment and sign -> simulate -> submit with PUBLIC TOY keys only.

Accepts no external RPC or wallet. The authority is a contract stand-in, not a real
Safe. Evidence stays under script/res/safe-let-image-rehearsal/.
"""
import json
import os
from pathlib import Path
import socket
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
DEPLOYER_KEY = "0x" + f"{0xB0B:064x}"
OWNER_KEY = "0x" + f"{0xA11CE:064x}"
REMAPPINGS = ("-R", "@openzeppelin/contracts/=dependencies/openzeppelin-contracts/contracts/",
              "-R", "@openzeppelin/contracts-upgradeable/=dependencies/openzeppelin-contracts-upgradeable/contracts/")


def command(*args, ok=True):
    result = subprocess.run(args, cwd=ROOT, text=True, encoding="utf-8", errors="replace", capture_output=True, timeout=600,
                            env={**os.environ, "PRIVATE_KEY_MAIN": DEPLOYER_KEY})
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

    relative = Path("script/res/safe-let-image-rehearsal") / uuid.uuid4().hex[:12]
    directory = ROOT / relative
    directory.mkdir(parents=True)
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
            common = ("--use", "0.8.28", "--rpc-url", url, "--sender", deployer, "--private-key", DEPLOYER_KEY, *REMAPPINGS)
            fixture_log = command("forge", "script", "test/fixtures/SafeLetImageRehearsal.s.sol:SafeLetImageRehearsal",
                                  "--sig", "run(string,address)", fixture_path, owner, *common, "--broadcast", "--slow")
            (directory / "fixture.log").write_text(fixture_log, encoding="utf-8")
            fixture = json.loads((ROOT / fixture_path).read_text())
            proxy, authority = fixture["proxy"], fixture["authority"]
            before = rpc("eth_getStorageAt", proxy, SLOT, "latest")
            script = "script/upgrade-safe-let-image.s.sol:UpgradeSafeLetImageScript"
            signature = "runWithArgs(uint256,address,address,string)"
            nonce = rpc("eth_getTransactionCount", deployer, "latest")
            batch_path = (relative / "batch.unverified.json").as_posix()
            # Explicit refusals with --broadcast still must not deploy any contracts.
            for chain_id, safe in (("1", authority), ("31337", "0x" + "33" * 20)):
                command("forge", "script", script, "--sig", signature, chain_id, proxy, safe, batch_path,
                        *common, "--broadcast", "--slow", ok=False)
                assert rpc("eth_getTransactionCount", deployer, "latest") == nonce
            command("forge", "script", script, "--sig", signature, "31337", proxy, authority, batch_path, *common)
            assert rpc("eth_getTransactionCount", deployer, "latest") == nonce
            deploy_log = command("forge", "script", script, "--sig", signature, "31337", proxy, authority, batch_path,
                                 *common, "--broadcast", "--slow")
            (directory / "deployment.log").write_text(deploy_log, encoding="utf-8")
            assert rpc("eth_getStorageAt", proxy, SLOT, "latest") == before
            image_data = calldata("imageBuilder()")
            assert rpc("eth_call", {"to": proxy, "data": image_data}, "latest")[-40:].lower() == fixture["oldImage"][2:].lower()
            batch = json.loads((ROOT / batch_path).read_text())
            assert batch["chainId"] == "31337" and len(batch["transactions"]) == 1
            tx = batch["transactions"][0]
            assert tx["to"].lower() == proxy.lower() and tx["value"] == "0"
            decoded = command("cast", "calldata-decode", "upgradeToAndCall(address,bytes)", tx["data"]).splitlines()
            implementation, setter = decoded[0], decoded[1]
            image = command("cast", "calldata-decode", "setImageBuilder(address)", setter)
            assert tx["data"].lower() == calldata("upgradeToAndCall(address,bytes)", implementation, setter).lower()
            assert rpc("eth_getCode", implementation, "latest") != "0x"
            assert rpc("eth_getCode", image, "latest") != "0x"
            owner_call = calldata("execute(address,bytes)", tx["to"], tx["data"])
            try:
                rpc("eth_call", {"from": deployer, "to": authority, "data": owner_call}, "latest")
            except RuntimeError:
                pass
            else:
                raise AssertionError("Unauthorized authority execution accepted")
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
            assert rpc("eth_getStorageAt", proxy, SLOT, "latest")[-40:].lower() == implementation[2:].lower()
            assert rpc("eth_call", {"to": proxy, "data": image_data}, "latest")[-40:].lower() == image[2:].lower()
            auth_data = calldata("AUTH()")
            assert rpc("eth_call", {"to": proxy, "data": auth_data}, "latest")[-40:].lower() == fixture["auth"][2:].lower()
            svg = command("cast", "call", fixture["readback"], "render(address)(string)", image, "--rpc-url", url)
            assert ">40,000</text>" in svg and ">Consideration</text>" in svg
            (directory / "upgrade-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
            print(f"PASS: local deployments only, exact Safe JSON, refusals, sign/simulate/submit, AUTH and SAFE SVG readback.\nEvidence: {directory}")
        finally:
            node.terminate()
            try:
                node.wait(timeout=10)
            except subprocess.TimeoutExpired:
                node.kill()
                node.wait()


if __name__ == "__main__":
    main()
