"""Read-only destination audit and reviewable template deployment plan.

Preserves immutable existing IDs that differ from Base, recording both complete
definitions. The Forge script still rejects any new conflict in the selected IDs.
Never uses a signing key; run after export-base-templates.py.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location("template_export", Path(__file__).with_name("export-base-templates.py"))
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


def prepare(block=None):
    source_path = Path("script/res/base-templates.json")
    source = json.loads(source_path.read_text(encoding="utf-8"))
    if source["sourceChainId"] != 8453 or source["targetChainId"] != 4663 or source["sourceRegistry"].lower() != exporter.REGISTRY.lower():
        raise RuntimeError("wrong source manifest")
    if source["templateCount"] != len(source["templates"]) or len({e["id"] for e in source["templates"]}) != source["templateCount"]:
        raise RuntimeError("source inventory count/IDs invalid")
    keys = {"ROBINHOOD_RPC_URL", "RPC_URL_ROBINHOOD"}
    settings = {k: os.environ[k] for k in keys if os.environ.get(k)}
    for line in Path(".env").read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            if k.strip() in keys:
                settings.setdefault(k.strip(), v.strip().strip('"').strip("'"))
    client = exporter.Client(settings.get("ROBINHOOD_RPC_URL") or settings["RPC_URL_ROBINHOOD"])
    if int(client.read("eth_chainId", []), 16) != 4663:
        raise RuntimeError("target RPC must be Robinhood mainnet 4663")
    block = block if block is not None else int(client.read("eth_blockNumber", []), 16) - 12
    header = client.read("eth_getBlockByNumber", [hex(block), False])
    if not header or client.read("eth_getCode", [exporter.REGISTRY, hex(block)]) == "0x":
        raise RuntimeError("destination registry absent")
    selector = exporter.cast("sig", "getTemplateDetails(bytes32)")
    missing_error = exporter.cast("sig", "TemplateDoesNotExist()")
    report = {"targetChainId": 4663, "targetRegistry": exporter.REGISTRY, "targetBlock": block,
              "targetBlockHash": header["hash"], "matching": [], "missing": [], "conflicts": []}
    selected = []
    for entry in source["templates"]:
        try:
            raw = client.read("eth_call", [{"to": exporter.REGISTRY, "data": selector + entry["id"][2:]}, hex(block)])
        except exporter.RpcError as error:
            if error.code != 3 or error.data != missing_error:
                raise RuntimeError("unexpected destination read failure for " + entry["id"]) from None
            report["missing"].append(entry["id"])
            selected.append(entry)
            continue
        details = exporter.decode_details(raw)
        if all(details[key] == entry[key] for key in details):
            report["matching"].append(entry["id"])
            selected.append(entry)
        else:
            report["conflicts"].append({"id": entry["id"], "baseDefinition": entry,
                                        "preservedRobinhoodDefinition": details,
                                        "preservedDefinitionHash": exporter.cast("keccak", stdin=raw)})
    if not selected:
        raise RuntimeError("no matching/missing definitions to deploy")
    if client.read("eth_getBlockByNumber", [hex(block), False])["hash"] != header["hash"]:
        raise RuntimeError("target block changed during preflight; retry")
    plan = dict(source)
    plan.update(templateCount=len(selected), templates=selected, sourceTemplateCount=source["templateCount"],
                sourceManifest=source_path.as_posix(), sourceManifestSha256=hashlib.sha256(source_path.read_bytes()).hexdigest(),
                destinationAudit=report)
    output = Path("script/res/robinhood-base-templates.json")
    temporary = output.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(plan, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temporary.replace(output)
    print("Base templates:", source["templateCount"], "selected:", len(selected), "missing:", len(report["missing"]),
          "already matching:", len(report["matching"]), "preserved conflicting IDs:", len(report["conflicts"]))
    for conflict in report["conflicts"]:
        print("[preserve existing; excluded]", conflict["id"], conflict["baseDefinition"]["title"])
    print("Saved", output, "SHA256:", hashlib.sha256(output.read_bytes()).hexdigest())


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--block", type=int, help="pin an explicit Robinhood audit block")
    args = parser.parse_args()
    try:
        prepare(args.block)
    except (RuntimeError, KeyError, ValueError) as error:
        print("Preparation failed:", str(error), file=sys.stderr)
        sys.exit(1)
