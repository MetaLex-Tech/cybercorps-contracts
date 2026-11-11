"""Read-only, block-pinned shared deployment comparison on four mainnets.

Only RPC settings are read from the local environment. No signing or explorer
publication. Run from the repository root with Python and cast installed.
"""
import concurrent.futures
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

spec = importlib.util.spec_from_file_location("checks", Path(__file__).with_name("check-robinhood-post-upgrade.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

constants = Path("script/libs/DeploymentConstants.sol").read_text()
core = {k: m.ADDRESSES[k] for k in (
    "coreAuth", "corporateFactory", "singleFactory", "issuanceFactory", "dealFactory", "roundFactory",
    "registry", "uriBuilder", "lexAuth", "lex", "lexMinter", "badgeAuth", "badge")}


def fields(text):
    return dict(re.findall(r"(\w+):\s*(0x[0-9a-fA-F]{40})", text))


extensions = fields(re.search(r"else if \(chainId == BASE\) \{\s*return ExtensionDeployment\(\{(.*?)\}\)", constants, re.S)[1])
conditions = fields(re.search(r"deployment = SecondaryConditionDeployment\(\{(.*?)\}\)", constants, re.S)[1])
assert len(core) == 13 and len(extensions) == 17 and len(conditions) == 19
inventory = []
for group, entries in (("Critical auth/proxy", core), ("Certificate extension", extensions), ("Secondary condition", conditions)):
    inventory.extend({"group": group, "name": name, "address": address} for name, address in entries.items())
extra = {
    "Legacy/checklist identity": {
        "lexchexCondition": "0x4a08547d57C8d01e59bA8F884aB90CEe0d6d5b42",
        "zkpassportVerifier": "0x1D000001000EFD9a6371f4d90bB8920D5431c0D8",
        "deprecatedNonUSNationalityCondition": "0xe71fE689bFAA4939A760EDF7e07f44372a43932A",
    },
    "Historical checklist": {
        "originalIssuanceFactory": "0xA32547aAdAA4975082D729c79e79dBaE4385EBCf",
        "originalSingleFactory": "0xc8e084D3f8B3b326FCc894C7afD28F4904196406",
        "originalDealFactory": "0x975df8A99C895d04ae158F8C91Ba562Fce3ECDA3",
        "originalLETImplementation": "0x016C3a68C3a82179B4e63871c7730aaA272c9638",
        "oldKillSwitchFromTestnetChecklist": "0x4c3b9Ec3B6e416A64Fde4a17Ea856e1cf2fE0344",
    },
    "Additional checklist products": {
        "MetaDAOFactory": "0x734aE2b36f663D0F4233Ce4a02c13b5EB8ec959D",
        "MetaDAOAuth": "0x727Cb7985F2a2ecD0626A771eDb1a63c92221F00",
        "PumpCorpFactoryBaseProduction": "0xe73Ea052c2891cE1668742142a6634Df09c88512",
        "PumpZkpassportAuthBaseProduction": "0xB92E1f3A65223476ce798eCC60186dc22c4d719f",
        "PumpNonUSNationalityBaseProduction": "0x95f0F67FdCa00b585a28Cf7A1E275A5541a9f6b3",
        "PumpOrConditionBaseProduction": "0x859c0DEc1B416ce02D2873E99Ad8FDEAc53Ac025",
    },
}
for group, entries in extra.items():
    inventory.extend({"group": group, "name": name, "address": address} for name, address in entries.items())

queries = []


def query(label, target, signature, kind="address", expected=None):
    queries.append({"label": label, "target": target, "signature": signature, "kind": kind, "expected": expected})


for getter, name in (("issuanceManagerFactory", "issuanceFactory"), ("cyberCorpSingleFactory", "singleFactory"),
                     ("dealManagerFactory", "dealFactory"), ("roundManagerFactory", "roundFactory"),
                     ("registryAddress", "registry"), ("uriBuilder", "uriBuilder"), ("lexchexAuth", "lexAuth")):
    query("corporateFactory." + getter, core["corporateFactory"], getter + "()", expected=core[name])
for name in ("corporateFactory", "singleFactory", "issuanceFactory", "dealFactory", "roundFactory", "registry", "uriBuilder"):
    query(name + ".AUTH", core[name], "AUTH()", expected=core["coreAuth"])
for name, expected in (("lex", "lexAuth"), ("lexMinter", "lexAuth"), ("badge", "badgeAuth")):
    query(name + ".AUTH", core[name], "AUTH()", expected=core[expected])
for name in ("singleFactory", "issuanceFactory", "dealFactory", "roundFactory"):
    query(name + ".referenceImplementation", core[name], "getRefImplementation()")
query("LET.referenceImplementation", core["issuanceFactory"], "getCyberCertPrinterRefImplementation()")
query("CyberScrip.referenceImplementation", core["issuanceFactory"], "getCyberScripRefImplementation()")
query("corporateFactory.stable", core["corporateFactory"], "stable()")
query("uriBuilder.imageBuilder", core["uriBuilder"], "imageBuilder()")
for name in ("dealFactory", "roundFactory"):
    query(name + ".primaryFeeBps", core[name], "getDefaultFeeRatio()", "uint")
query("dealFactory.secondaryFeeBps", core["dealFactory"], "getSecondaryFeeRatio()", "uint")
for q in queries:
    q["data"] = m.selector(q["signature"])

allowed = {"RPC_URL_ROBINHOOD", "ROBINHOOD_RPC_URL", "RPC_URL_BASE", "RPC_URL_ETHEREUM", "RPC_URL_ARBITRUM"}
settings = {k: os.environ[k] for k in allowed if os.environ.get(k)}
if Path(".env").exists():
    for line in Path(".env").read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            if k.strip() in allowed:
                settings.setdefault(k.strip(), v.strip().strip('"').strip("'"))
chains = {
    "Robinhood": (4663, settings.get("ROBINHOOD_RPC_URL") or settings["RPC_URL_ROBINHOOD"]),
    "Base": (8453, settings.get("RPC_URL_BASE", "https://mainnet.base.org")),
    "Ethereum": (1, settings.get("RPC_URL_ETHEREUM", "https://ethereum-rpc.publicnode.com")),
    "Arbitrum": (42161, settings.get("RPC_URL_ARBITRUM", "https://arb1.arbitrum.io/rpc")),
}


def fingerprint(code):
    if not isinstance(code, str) or not code.startswith("0x"):
        return {"readError": code}
    raw = bytes.fromhex(code[2:])
    return {"hasCode": bool(raw), "runtimeBytes": len(raw), "runtimeSha256": hashlib.sha256(raw).hexdigest()}


def inspect_chain(name):
    cid, url = chains[name]
    def read(requests):
        if name != "Arbitrum":
            return m.rpc(url, requests)
        # Public Arbitrum endpoints throttle large batches. Keep reads modest.
        result = []
        for start in range(0, len(requests), 5):
            result.extend(m.rpc(url, requests[start:start + 5]))
            time.sleep(0.25)
        return result
    actual, block = read([("eth_chainId", []), ("eth_blockNumber", [])])
    assert int(actual, 16) == cid, "RPC chain mismatch: " + name
    header = read([("eth_getBlockByNumber", [block, False])])[0]
    results = read([("eth_getCode", [item["address"], block]) for item in inventory])
    contracts = {item["name"]: fingerprint(result) for item, result in zip(inventory, results)}
    reads = read([("eth_call", [{"to": q["target"], "data": q["data"]}, block]) for q in queries])
    wiring = {}
    for q, value in zip(queries, reads):
        if q["kind"] == "address":
            decoded = m.as_address(value)
        else:
            decoded = int(value, 16) if isinstance(value, str) and value != "0x" else value
        entry = {"value": decoded}
        if q["expected"]:
            entry["expected"] = q["expected"]
            entry["matchesSharedTarget"] = isinstance(decoded, str) and decoded.lower() == q["expected"].lower()
        wiring[q["label"]] = entry
    proxy_inventory = [x for x in inventory if x["group"] in ("Critical auth/proxy", "Certificate extension")]
    slots = read([("eth_getStorageAt", [x["address"], m.SLOT, block]) for x in proxy_inventory])
    implementations = {}
    for item, word in zip(proxy_inventory, slots):
        value = m.as_address(word)
        if isinstance(value, str) and int(value, 16) != 0:
            implementations[item["name"]] = value
    implementation_targets = dict(implementations)
    implementation_targets.update({k: v["value"] for k, v in wiring.items() if k.endswith("referenceImplementation")})
    valid = {k: v for k, v in implementation_targets.items() if isinstance(v, str) and len(v) == 42 and int(v, 16) != 0}
    addresses = list(dict.fromkeys(valid.values()))
    codes = read([("eth_getCode", [a, block]) for a in addresses])
    version_selector = m.selector("DEPLOY_VERSION()")
    versions = read([("eth_call", [{"to": a, "data": version_selector}, block]) for a in addresses])
    by_address = {}
    for address, code, version in zip(addresses, codes, versions):
        details = fingerprint(code)
        if isinstance(version, str) and len(version) >= 194:
            length = int(version[66:130], 16)
            details["deployVersion"] = bytes.fromhex(version[130:130 + length * 2]).decode("utf-8", errors="replace")
        by_address[address] = details
    return {"chainId": cid, "block": int(block, 16), "blockHash": header["hash"],
            "blockTimestamp": int(header["timestamp"], 16), "contracts": contracts, "wiring": wiring,
            "proxyImplementations": implementations, "implementationTargets": valid,
            "implementationCode": by_address}


report = {"observedAtUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
          "sourceRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
          "scope": "Shared core, extensions, secondary conditions and selected historical/product checklist addresses; no client-specific or staging deployments.",
          "inventory": inventory, "chains": {}, "failures": {}, "transactionsSubmitted": False, "walletKeysUsed": False}
path = Path("notes/ai/tasks/robinhood-address-parity-20261101.json")
if "--resume" in sys.argv and path.exists():
    report = json.loads(path.read_text())
    assert report["inventory"] == inventory, "Inventory changed; start a fresh comparison."
pending = [name for name in chains if name not in report["chains"]]
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    futures = {pool.submit(inspect_chain, name): name for name in pending}
    for future in concurrent.futures.as_completed(futures):
        name = futures[future]
        try:
            report["chains"][name] = future.result()
            report["failures"].pop(name, None)
            print(name, "pinned at", report["chains"][name]["block"], flush=True)
        except Exception as error:
            report["failures"][name] = type(error).__name__ + ": " + str(error)
            print(name, "read failed; endpoint withheld", flush=True)

report["comparison"] = []
for item in inventory:
    states = {name: data["contracts"][item["name"]] for name, data in report["chains"].items()}
    present = [name for name, data in states.items() if data.get("hasCode")]
    report["comparison"].append({**item, "presentOn": present, "allFourHaveCode": len(present) == 4,
                                 "allFourRuntimeEqual": len(present) == 4 and len({x.get("runtimeSha256") for x in states.values()}) == 1})
report["lastCheckedAtUtc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
path.write_text(json.dumps(report, indent=2) + "\n")
for group in dict.fromkeys(x["group"] for x in inventory):
    rows = [x for x in report["comparison"] if x["group"] == group]
    print(group, sum(x["allFourHaveCode"] for x in rows), "/", len(rows), "at same address on all four chains")
    for row in rows:
        if not row["allFourHaveCode"]:
            print(" ", row["name"], "present:", ", ".join(row["presentOn"]) or "none")
for name, data in report["chains"].items():
    mismatches = {k: v for k, v in data["wiring"].items() if v.get("matchesSharedTarget") is False}
    print(name, "wiring mismatches:", json.dumps(mismatches))
if report["failures"]:
    raise SystemExit(1)
