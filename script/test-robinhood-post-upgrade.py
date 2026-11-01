"""Run the opt-in deployed-code lifecycle acceptance at comparison snapshot blocks.

Only local fork calls and public toy signatures. Does not read a private key or
invoke broadcast/upgrade scripts. RPC URLs are redacted from persisted output.
"""
import json
import base64
import os
from pathlib import Path
import subprocess
import sys
import re
import xml.etree.ElementTree as ET
import hashlib
import datetime

sys.stdout.reconfigure(encoding='utf-8',errors='replace')

chain = sys.argv[1] if len(sys.argv)>1 else 'robinhood'
assert chain in ['robinhood','base']
snapshot=json.loads(Path('notes/ai/tasks/robinhood-post-v5-comparison-20261030.json').read_text())
allowed={'ROBINHOOD_RPC_URL','RPC_URL_ROBINHOOD','RPC_URL_BASE'}
settings={k:os.environ[k] for k in allowed if os.environ.get(k)}
for line in Path('.env').read_text().splitlines():
    if '=' in line and not line.lstrip().startswith('#'):
        k,v=line.split('=',1)
        if k.strip() in allowed: settings.setdefault(k.strip(),v.strip().strip('"').strip("'"))
base=settings.get('RPC_URL_BASE','https://base-rpc.publicnode.com')
url=(settings.get('ROBINHOOD_RPC_URL') or settings['RPC_URL_ROBINHOOD']) if chain=='robinhood' else base
env=os.environ.copy()
env.update(ROBINHOOD_POST_FORK_RPC_URL=url,POST_UPGRADE_CHAIN_ID=str(snapshot['chains'][chain]['chainId']),
           POST_UPGRADE_BLOCK=str(snapshot['chains'][chain]['blockNumber']),POST_UPGRADE_BASE_RPC_URL=base,
           POST_UPGRADE_BASE_BLOCK=str(snapshot['chains']['base']['blockNumber']))
command=['forge','test','--match-path','test/RobinhoodPostUpgradeLifecycleTest.t.sol',
         '--offline','--use','0.8.28','--evm-version','cancun','--threads','1',
         '-R','@openzeppelin/contracts/=dependencies/openzeppelin-contracts/contracts/',
         '-R','@openzeppelin/contracts-upgradeable/=dependencies/openzeppelin-contracts-upgradeable/contracts/',
         '-vvv']
result=subprocess.run(command,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace')
output=result.stdout
for value in {*settings.values(),url,base}: output=output.replace(value,'<configured RPC>')
folder=Path('out/robinhood-post-v5');folder.mkdir(parents=True,exist_ok=True)
(folder/(chain+'-lifecycle.log')).write_text(output,encoding='utf-8')
if result.returncode==0:
    match=re.search(r'^\s*SAFE_METADATA (data:application/json;base64,\S+)\s*$',output,re.MULTILINE)
    assert match, 'missing certificate metadata evidence'
    metadata=json.loads(base64.b64decode(match[1].split(',',1)[1]))
    assert metadata['cyberCORPName']=='Fork Acceptance Corp'
    assert metadata['securityType']=='SAFE'
    assert metadata['securitySeries']=='SeriesSeed'
    assert metadata['investmentAmountUSD']=='7500.00'
    assert metadata['SAFESeriesDetails']['seriesName']=='Seed SAFE'
    assert metadata['SAFEDetails']['customProvisions']=='Fork acceptance certificate'
    (folder/(chain+'-safe-metadata.json')).write_text(json.dumps(metadata,indent=2),encoding='utf-8')
    image=metadata['image']
    assert image.startswith('data:image/svg+xml;base64,'), 'expected embedded SVG image'
    svg=base64.b64decode(image.split(',',1)[1])
    ET.fromstring(svg)
    assert b'Fork Acceptance Corp' in svg, 'image must identify the issuing company'
    (folder/(chain+'-safe-image.svg')).write_bytes(svg)
    print('Certificate metadata: valid JSON; image: valid embedded SVG with issuing company.')
display=re.sub(r'^\s*SAFE_METADATA .*$', '  [certificate metadata captured and validated by wrapper]', output, flags=re.MULTILINE)
evidence_path=Path('notes/ai/tasks/robinhood-post-v5-lifecycle-20261030.json')
evidence=json.loads(evidence_path.read_text()) if evidence_path.exists() else {'chains':{}}
files=[Path('test/RobinhoodPostUpgradeLifecycleTest.t.sol'),Path('script/test-robinhood-post-upgrade.py'),
       Path('script/check-robinhood-post-upgrade.py'),folder/(chain+'-lifecycle.log')]
if result.returncode==0:
    files += [folder/(chain+'-safe-metadata.json'),folder/(chain+'-safe-image.svg')]
evidence['chains'][chain]={
    'observedAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'sourceRevision':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
    'testSources':'new local working-tree additions; production src unchanged',
    'blockNumber':snapshot['chains'][chain]['blockNumber'],
    'blockHash':snapshot['chains'][chain].get('blockHash'),
    'chainId':snapshot['chains'][chain]['chainId'],
    'exitCode':result.returncode,
    'passed':re.findall(r'^\[PASS\] (\S+)',output,re.MULTILINE),
    'failed':re.findall(r'^\[FAIL[^\]]*\] (\S+)',output,re.MULTILINE),
    'skipped':re.findall(r'^\[SKIP\] (\S+)',output,re.MULTILINE),
    'productionContractUpgrades':False,'submittedLiveTransactions':False,
    'localTemplateFixture':chain=='robinhood',
    'metadataJsonAndSvgValidated':result.returncode==0,
    'sha256':{p.as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
    'command':command,
}
evidence_path.write_text(json.dumps(evidence,indent=2)+'\n')
print(display[-16000:])
raise SystemExit(result.returncode)
