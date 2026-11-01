"""Exercise only generated test signers on a fresh local Robinhood fork."""
import base64,datetime,hashlib,importlib.util,json,os,re,subprocess,sys
from pathlib import Path
import xml.etree.ElementTree as ET

sys.stdout.reconfigure(encoding="utf-8",errors="replace")
spec=importlib.util.spec_from_file_location("checks",Path(__file__).with_name("check-robinhood-post-upgrade.py"))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
keys={"ROBINHOOD_RPC_URL","RPC_URL_ROBINHOOD"}
settings={k:os.environ[k] for k in keys if os.environ.get(k)}
for line in Path(".env").read_text().splitlines():
    if "=" in line and not line.lstrip().startswith("#"):
        k,v=line.split("=",1)
        if k.strip() in keys:settings.setdefault(k.strip(),v.strip().strip('"').strip("'"))
rpc=settings.get("ROBINHOOD_RPC_URL") or settings["RPC_URL_ROBINHOOD"]
chain,block=m.rpc(rpc,[("eth_chainId",[]),("eth_blockNumber",[])])
assert int(chain,16)==4663
header=m.rpc(rpc,[("eth_getBlockByNumber",[block,False])])[0]
env=os.environ.copy();env.update(CENT_SAFE_FORK_RPC_URL=rpc,CENT_SAFE_FORK_BLOCK=str(int(block,16)))
command=["forge","test","--match-path","test/RobinhoodCentSafeScriptTest.t.sol","--offline","--use","0.8.28",
         "--evm-version","cancun","--threads","1","-R","@openzeppelin/contracts/=dependencies/openzeppelin-contracts/contracts/",
         "-R","@openzeppelin/contracts-upgradeable/=dependencies/openzeppelin-contracts-upgradeable/contracts/","-vvv"]
folder=Path("out/robinhood-cent-safe");folder.mkdir(parents=True,exist_ok=True)
log=folder/"fork.log"
print("Testing real ETH/USDG swap and 0.01 USDG SAFE on fork block",int(block,16),flush=True)
with log.open("w",encoding="utf-8") as output:
    result=subprocess.run(command,env=env,stdout=output,stderr=subprocess.STDOUT)
text=log.read_text(encoding="utf-8",errors="replace")
for value in settings.values():text=text.replace(value,"<configured RPC>")
log.write_text(text,encoding="utf-8")
metadata_validated=False
if result.returncode==0:
    match=re.search(r"^\s*CENT_SAFE_METADATA (data:application/json;base64,\S+)\s*$",text,re.MULTILINE)
    assert match,"missing issued SAFE metadata"
    metadata=json.loads(base64.b64decode(match[1].split(",",1)[1]))
    assert metadata["securityType"]=="SAFE" and metadata["investmentAmountUSD"]=="0.01"
    svg=base64.b64decode(metadata["image"].split(",",1)[1]);ET.fromstring(svg)
    assert b"Cent SAFE Fork Rehearsal" in svg
    (folder/"safe-metadata.json").write_text(json.dumps(metadata,indent=2),encoding="utf-8")
    (folder/"safe-image.svg").write_bytes(svg);metadata_validated=True
paths=[Path("script/robinhood-cent-safe.s.sol"),Path("test/RobinhoodCentSafeScriptTest.t.sol"),Path("script/test-robinhood-cent-safe.py"),log]
evidence={"observedAtUtc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"chainId":4663,
          "forkBlock":int(block,16),"forkBlockHash":header["hash"],"sourceRevision":subprocess.check_output(["git","rev-parse","HEAD"],text=True).strip(),
          "testedTree":"local rehearsal script/test additions; src unchanged","exitCode":result.returncode,
          "passed":re.findall(r"^\[PASS\] (\S+)",text,re.MULTILINE),"failed":re.findall(r"^\[FAIL[^\]]*\] (\S+)",text,re.MULTILINE),
          "skipped":re.findall(r"^\[SKIP\] (\S+)",text,re.MULTILINE),"liveTransactionsSubmitted":False,"realKeysUsed":False,
          "usdgMockFunding":False,"metadataValidated":metadata_validated,
          "swapEthSpentWei":re.findall(r"SWAP_ETH_SPENT_WEI (\d+)",text),"command":command,
          "sha256":{p.as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}}
Path("notes/ai/tasks/robinhood-cent-safe-verification-20261030.json").write_text(json.dumps(evidence,indent=2)+"\n")
display=re.sub(r"^\s*CENT_SAFE_METADATA .*$","  [one-cent SAFE JSON/SVG validated]",text,flags=re.MULTILINE)
print(display[-14000:]);raise SystemExit(result.returncode)
