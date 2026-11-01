"""Unit + actual deployed-registry fork acceptance; no live transactions."""
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
settings = {k: os.environ[k] for k in ["ROBINHOOD_RPC_URL", "RPC_URL_ROBINHOOD"] if os.environ.get(k)}
for line in Path(".env").read_text().splitlines():
    if "=" in line and not line.lstrip().startswith("#"):
        k, v = line.split("=", 1)
        if k.strip() in {"ROBINHOOD_RPC_URL", "RPC_URL_ROBINHOOD"}:
            settings.setdefault(k.strip(), v.strip().strip('"').strip("'"))
rpc = settings.get("ROBINHOOD_RPC_URL") or settings["RPC_URL_ROBINHOOD"]
target = json.loads(Path("notes/ai/tasks/robinhood-post-v5-comparison-20261030.json").read_text())["chains"]["robinhood"]
manifest_path = Path("script/res/robinhood-base-templates.json")
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
env = os.environ.copy()
env.update(ROBINHOOD_POST_FORK_RPC_URL=rpc, POST_UPGRADE_CHAIN_ID="4663", POST_UPGRADE_BLOCK=str(target["blockNumber"]))
command = ["forge", "test", "--match-path", "test/BaseTemplateSync*Test.t.sol", "--offline", "--use", "0.8.28",
           "--evm-version", "cancun", "--threads", "1", "-R", "@openzeppelin/contracts/=dependencies/openzeppelin-contracts/contracts/",
           "-R", "@openzeppelin/contracts-upgradeable/=dependencies/openzeppelin-contracts-upgradeable/contracts/", "-vvv"]
result = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
output = result.stdout
for url in settings.values():
    output = output.replace(url, "<configured RPC>")
folder = Path("out/base-template-sync")
folder.mkdir(parents=True, exist_ok=True)
log_path = folder / "acceptance.log"
log_path.write_text(output, encoding="utf-8")
validated = False
if result.returncode == 0:
    match = re.search(r"^\s*SAFE_METADATA (data:application/json;base64,\S+)\s*$", output, re.MULTILINE)
    assert match, "missing SAFE certificate metadata"
    metadata = json.loads(base64.b64decode(match[1].split(",", 1)[1]))
    assert metadata["securityType"] == "SAFE" and metadata["investmentAmountUSD"] == "7500.00"
    assert metadata["cyberCORPName"] == "Fork Acceptance Corp"
    svg = base64.b64decode(metadata["image"].split(",", 1)[1])
    ET.fromstring(svg)
    assert b"Fork Acceptance Corp" in svg
    (folder / "safe-metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    (folder / "safe-image.svg").write_bytes(svg)
    validated = True
paths = [Path("script/sync-base-templates.s.sol"), Path("script/export-base-templates.py"), Path(__file__), manifest_path,
         Path("script/prepare-robinhood-templates.py"), Path("script/res/base-templates.json"),
         Path("script/res/base-template-events.json"), Path("test/BaseTemplateSyncTest.t.sol"),
         Path("test/BaseTemplateSyncForkTest.t.sol"), Path("test/RobinhoodPostUpgradeLifecycleTest.t.sol"), log_path]
evidence = {"observedAtUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "sourceRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
            "testedTree": "new/modified task files in local working tree; src unchanged", "sourceBaseBlock": manifest["sourceBlock"],
            "sourceBaseBlockHash": manifest["sourceBlockHash"], "templateCount": manifest["templateCount"],
            "targetForkBlock": target["blockNumber"], "targetForkBlockHash": target["blockHash"], "exitCode": result.returncode,
            "passed": re.findall(r"^\[PASS\] (\S+)", output, re.MULTILINE),
            "failed": re.findall(r"^\[FAIL[^\]]*\] (\S+)", output, re.MULTILINE),
            "skipped": re.findall(r"^\[SKIP\] (\S+)", output, re.MULTILINE),
            "safeMetadataValidated": validated, "liveTransactionsSubmitted": False, "command": command,
            "sha256": {p.as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}}
Path("notes/ai/tasks/robinhood-base-template-sync-verification-20261030.json").write_text(json.dumps(evidence, indent=2)+"\n")
display = re.sub(r"^\s*SAFE_METADATA .*$", "  [SAFE metadata validated and saved locally]", output, flags=re.MULTILINE)
print(display[-10000:])
raise SystemExit(result.returncode)
