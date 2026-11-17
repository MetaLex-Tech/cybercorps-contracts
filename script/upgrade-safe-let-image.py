"""Prepare separate SAFE LET image Safe batches on eth, base, arb and rhc.

Simulation is the default. --broadcast deploys contracts only, after all selected
chains pass simulation. Deployment batches remain .unverified.json until the
operator verifies receipts, linked code and Safe acceptance. No Safe calls are sent.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = "script/upgrade-safe-let-image.s.sol:UpgradeSafeLetImageScript"
CHAINS = {"eth": (1, "ethereum"), "base": (8453, "base"),
          "arb": (42161, "arbitrum"), "rhc": (4663, "robinhood")}
REMAPPINGS = ("-R", "@openzeppelin/contracts/=dependencies/openzeppelin-contracts/contracts/",
              "-R", "@openzeppelin/contracts-upgradeable/=dependencies/openzeppelin-contracts-upgradeable/contracts/")


def validate_batch(path, chain_id):
    batch = json.loads(path.read_text(encoding="utf-8"))
    if batch.get("version") != "1.0" or batch.get("chainId") != str(chain_id):
        raise ValueError("Safe batch version or chain mismatch")
    txs = batch.get("transactions")
    if not isinstance(txs, list) or len(txs) > 1:
        raise ValueError("Expected zero or one renderer update")
    for tx in txs:
        if tx.get("value") != "0" or not re.fullmatch(r"0x[0-9a-fA-F]{40}", tx.get("to", "")):
            raise ValueError("Invalid Safe destination or value")
        data = tx.get("data", "")
        if not re.fullmatch(r"0x(?:[0-9a-fA-F]{2})+", data) or data[:10].lower() not in ("0x8a5dc582", "0x4f1ef286"):
            raise ValueError("Unexpected Safe call; expected image setter or atomic renderer upgrade")
    return len(txs)


def prepare(args, execute=subprocess.run):
    if len(set(args.chains)) != len(args.chains):
        raise ValueError("Select each chain only once")
    rpcs = {name: alias for name, (_, alias) in CHAINS.items()}
    for override in args.rpc:
        name, separator, endpoint = override.partition("=")
        if name not in CHAINS or not separator or not endpoint:
            raise ValueError("--rpc must be eth|base|arb|rhc=RPC_URL_OR_FORGE_ALIAS")
        rpcs[name] = endpoint
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    directory = ROOT / "script/res/safe-let-image" / run_id
    directory.mkdir(parents=True)
    manifest = {"script": SCRIPT, "broadcastRequested": args.broadcast,
                "safeExecution": "not submitted", "steps": []}
    manifest_path = directory / "manifest.json"

    def save():
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    save()
    print(f"Artifacts: {directory}", flush=True)
    # All chain/ownership/deployment simulations must pass before any broadcast.
    phases = ("simulation", "deployment") if args.broadcast else ("simulation",)
    for phase in phases:
        for name in args.chains:
            chain_id, _ = CHAINS[name]
            suffix = "simulation.json" if phase == "simulation" else "unverified.json"
            batch_path = directory / f"{name}-{chain_id}-{suffix}"
            relative = batch_path.relative_to(ROOT).as_posix()
            command = ["forge", "script", SCRIPT, "--sig", "runForChain(uint256,string)", str(chain_id), relative,
                       "--use", "0.8.28", "--rpc-url", rpcs[name], "--sender", args.sender, *REMAPPINGS]
            if args.account:
                command.extend(("--account", args.account))
            if args.ledger:
                command.append("--ledger")
            if phase == "deployment":
                command.extend(("--broadcast", "--slow"))
            step = {"chain": name, "chainId": chain_id, "phase": phase, "batch": relative, "status": "running"}
            manifest["steps"].append(step)
            save()
            print(f"{name} ({chain_id}): {phase}", flush=True)
            try:
                result = execute(command, cwd=ROOT, text=True, encoding="utf-8", errors="replace",
                                 capture_output=True, timeout=900)
                (directory / f"{name}-{phase}.log").write_text(result.stdout + result.stderr, encoding="utf-8")
                if result.returncode:
                    raise RuntimeError(f"Forge failed; see {name}-{phase}.log")
                step["calls"] = validate_batch(batch_path, chain_id)
                step["status"] = "simulated" if phase == "simulation" else "broadcast-complete-unverified"
                save()
            except Exception as error:
                step["status"] = "failed"
                save()
                raise RuntimeError(f"{name} {phase} stopped: {error}. Evidence: {directory}") from error
    return directory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chains", nargs="+", choices=CHAINS, default=list(CHAINS))
    parser.add_argument("--rpc", action="append", default=[], metavar="CHAIN=RPC",
                        help="Override a Forge RPC alias (defaults: ethereum, base, arbitrum, robinhood)")
    parser.add_argument("--sender", required=True, help="Deployment wallet address")
    wallet = parser.add_mutually_exclusive_group()
    wallet.add_argument("--account", help="Forge keystore account")
    wallet.add_argument("--ledger", action="store_true", help="Use Forge's Ledger wallet")
    parser.add_argument("--broadcast", action="store_true", help="Deploy after every selected chain passes simulation")
    args = parser.parse_args()
    try:
        prepare(args)
    except (ValueError, RuntimeError) as error:
        parser.exit(1, f"{error}\n")
    print("Complete. Simulation batches must not be executed. Verify deployment receipts/code before Safe import.")


if __name__ == "__main__":
    main()
