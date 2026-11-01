"""Fresh live-state readback and strict local fork lifecycle acceptance.

Never runs a registration/deployment script or accesses PRIVATE_KEY_MAIN. Uses
the existing lifecycle's generated public test signers and local USDG funding.
"""
import base64
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
spec=importlib.util.spec_from_file_location("rpc_checks",Path(__file__).with_name("check-robinhood-post-upgrade.py"))
checks=importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)
allowed={"ROBINHOOD_RPC_URL","RPC_URL_ROBINHOOD"}
settings={k:os.environ[k] for k in allowed if os.environ.get(k)}
for line in Path(".env").read_text().splitlines():
    if "=" in line and not line.lstrip().startswith("#"):
        k,v=line.split("=",1)
        if k.strip() in allowed:
            settings.setdefault(k.strip(),v.strip().strip('"').strip("'"))
rpc=settings.get("ROBINHOOD_RPC_URL") or settings["RPC_URL_ROBINHOOD"]
chain,block=checks.rpc(rpc,[("eth_chainId",[]),("eth_blockNumber",[])])
assert int(chain,16)==4663,"expected Robinhood mainnet"
header=checks.rpc(rpc,[("eth_getBlockByNumber",[block,False])])[0]
manifest_path=Path("script/res/robinhood-base-templates.json")
manifest=json.loads(manifest_path.read_text(encoding="utf-8"))
registry=manifest["targetRegistry"]
selector=checks.selector("getTemplateDetails(bytes32)")
values=checks.rpc(rpc,[("eth_call",[{"to":registry,"data":selector+e["id"][2:]},block]) for e in manifest["templates"]])
readback={"observedAtUtc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"chainId":4663,
          "blockNumber":int(block,16),"blockHash":header["hash"],"registry":registry,
          "manifestSha256":hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
          "matching":[],"missingOrFailed":[],"conflicting":[],"liveTransactionsSubmitted":False}
for entry,raw in zip(manifest["templates"],values):
    if not isinstance(raw,str):
        readback["missingOrFailed"].append({"id":entry["id"],"error":raw})
        continue
    decoded=[json.loads(v) for v in checks.cast("abi-decode","f()(string,string,string[],string[])",raw).splitlines()]
    expected=[entry["legalContractUri"],entry["title"],entry["globalFields"],entry["partyFields"]]
    if decoded!=expected:
        readback["conflicting"].append({"id":entry["id"],"observed":decoded,"expected":expected})
    else:
        readback["matching"].append(entry["id"])
legacy=manifest["destinationAudit"]["conflicts"]
readback["preservedLegacyDefinitions"]=[]
for entry in legacy:
    raw=checks.rpc(rpc,[("eth_call",[{"to":registry,"data":selector+entry["id"][2:]},block])])[0]
    digest=checks.cast("keccak",stdin=raw) if isinstance(raw,str) else None
    readback["preservedLegacyDefinitions"].append({"id":entry["id"],"definitionHash":digest,
                                                  "unchanged":digest==entry["preservedDefinitionHash"]})
readback_path=Path("notes/ai/tasks/robinhood-live-template-readback-20261030.json")
readback_path.write_text(json.dumps(readback,indent=2)+"\n")
print("Robinhood block",int(block,16),"template matches",len(readback["matching"]),"/",len(values),flush=True)
print("Missing/failed",len(readback["missingOrFailed"]),"conflicting",len(readback["conflicting"]),flush=True)
if readback["missingOrFailed"] or readback["conflicting"] or not all(e["unchanged"] for e in readback["preservedLegacyDefinitions"]):
    raise SystemExit("Live template readback failed; see public readback evidence. No local template was installed.")

env=os.environ.copy()
env.update(ROBINHOOD_POST_FORK_RPC_URL=rpc,POST_UPGRADE_CHAIN_ID="4663",POST_UPGRADE_BLOCK=str(int(block,16)))
command=["forge","test","--match-path","test/RobinhoodLiveTemplateLifecycleTest.t.sol",
         "--no-match-test","test_LiveFormationAndMissingTemplateRefusal","--offline","--use","0.8.28",
         "--evm-version","cancun","--threads","1","-R","@openzeppelin/contracts/=dependencies/openzeppelin-contracts/contracts/",
         "-R","@openzeppelin/contracts-upgradeable/=dependencies/openzeppelin-contracts-upgradeable/contracts/","-vvv"]
folder=Path("out/robinhood-live-templates")
folder.mkdir(parents=True,exist_ok=True)
log_path=folder/"lifecycle.log"
with log_path.open("w",encoding="utf-8") as log:
    result=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT)
output=log_path.read_text(encoding="utf-8",errors="replace")
for url in settings.values():
    output=output.replace(url,"<configured RPC>")
log_path.write_text(output,encoding="utf-8")
validated=False
if result.returncode==0:
    match=re.search(r"^\s*SAFE_METADATA (data:application/json;base64,\S+)\s*$",output,re.MULTILINE)
    assert match,"missing issued SAFE metadata"
    metadata=json.loads(base64.b64decode(match[1].split(",",1)[1]))
    for key,value in {"cyberCORPName":"Fork Acceptance Corp","securityType":"SAFE","securitySeries":"SeriesSeed",
                      "investmentAmountUSD":"7500.00","issuerUSDValuationAtTimeOfInvestment":"10000000.00"}.items():
        assert metadata[key]==value,key+" mismatch"
    assert metadata["SAFESeriesDetails"]["seriesName"]=="Seed SAFE"
    assert metadata["SAFEDetails"]["customProvisions"]=="Fork acceptance certificate"
    assert metadata["image"].startswith("data:image/svg+xml;base64,")
    svg=base64.b64decode(metadata["image"].split(",",1)[1])
    ET.fromstring(svg)
    assert b"Fork Acceptance Corp" in svg
    (folder/"safe-metadata.json").write_text(json.dumps(metadata,indent=2),encoding="utf-8")
    (folder/"safe-image.svg").write_bytes(svg)
    validated=True
same_block=checks.rpc(rpc,[("eth_getBlockByNumber",[block,False])])[0]["hash"]==header["hash"]
paths=[Path("script/test-robinhood-live-templates.py"),Path("test/RobinhoodLiveTemplateLifecycleTest.t.sol"),
       Path("test/RobinhoodPostUpgradeLifecycleTest.t.sol"),manifest_path,readback_path,log_path]
if validated:
    paths.extend([folder/"safe-metadata.json",folder/"safe-image.svg"])
evidence={"observedAtUtc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"chainId":4663,
          "blockNumber":int(block,16),"blockHash":header["hash"],"sourceBlockStillCanonical":same_block,
          "sourceRevision":subprocess.check_output(["git","rev-parse","HEAD"],text=True).strip(),
          "testedTree":"local lifecycle test/runner additions; production src unchanged",
          "passed":re.findall(r"^\[PASS\] (\S+)",output,re.MULTILINE),
          "failed":re.findall(r"^\[FAIL[^\]]*\] (\S+)",output,re.MULTILINE),
          "skipped":re.findall(r"^\[SKIP\] (\S+)",output,re.MULTILINE),
          "exitCode":result.returncode,"metadataJsonAndSvgValidated":validated,
          "liveTemplateCountMatched":len(readback["matching"]),"localTemplateRegistration":False,
          "productionContractUpgrades":False,"deploymentScriptInvoked":False,"liveTransactionsSubmitted":False,
          "forkCompany":re.findall(r"Created company (0x[0-9a-fA-F]{40})",output),
          "forkSafeLet":re.findall(r"SAFE LET (0x[0-9a-fA-F]{40})",output),"command":command,
          "sha256":{p.as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}}
Path("notes/ai/tasks/robinhood-live-template-lifecycle-20261030.json").write_text(json.dumps(evidence,indent=2)+"\n")
display=re.sub(r"^\s*SAFE_METADATA .*$","  [issued SAFE JSON and SVG validated]",output,flags=re.MULTILINE)
print(display[-10000:])
if not same_block:
    raise SystemExit("Pinned block reorganized; evidence must be rerun")
raise SystemExit(result.returncode)
