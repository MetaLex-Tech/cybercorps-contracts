"""Read-only, block-pinned Robinhood/Base comparison. Requires Python and cast.

Reads only RPC endpoint settings from .env; never uses a signing key. Produces
public evidence under notes/ai/tasks. Run from the repository root.
"""
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.request

SLOT = '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'
FACTORY = '0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2'
REGISTRY = '0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134'
SAFE = '0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C'
ADDRESSES = {
    'coreAuth': '0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01',
    'corporateFactory': FACTORY,
    'singleFactory': '0xBE0D3D13AA07501beAC9b72dE9e9292E66C7A5C4',
    'issuanceFactory': '0xD353972D7955F421d94d0eA8c42c88c417F7155A',
    'dealFactory': '0x3982b078f2ac306219c9540Ebc908360a960C251',
    'roundFactory': '0xc9d5d0DeDD124f9351E5880469f25AB41869aeb9',
    'registry': REGISTRY,
    'uriBuilder': '0x5500c095ea7dE6F8a5E15949e24B80604cc670A3',
    'lexAuth': '0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2',
    'lex': '0xc8db0c3f47656aee725b0AD1835F9A3FbD0a0b62',
    'lexMinter': '0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960',
    'badgeAuth': '0x197333Fc7A828e623fbfcF88eCdc976136F0cf1d',
    'badge': '0x114664773Ba721a6AA43890d5FDE7939aF37618F',
    'safeExtension': '0xB2E732d29b89ec36a8Dd23CFD32901056b6579C8',
    'safeExtensionV3': '0x740003076c9F16c4a364AE07f3770FB77899299b',
    'aceSafeExtensionV3': '0x9a8ef946F18C4296e50f8DF0C97b5Cf5d1b5eCD2',
    'killSwitch': '0x456EDAfB7283dB8FDa2A5b3ecE576d9292512435',
    'saftExtensionV2': '0x37c2A0e801e569e01f0972186aF4DB01409e92c1',
    'safteExtensionV2': '0x4Acdc8618BF2C3d760a357ec11A8290c79f5b41A',
    'tokenWarrantExtensionV2': '0xF5A9984DfcA4D6Dd55D6151F0cd2F4Af9522BC8F',
    'shareExtension': '0x80e8205b74e3E9882C3C57aA0b36cD465E7A4b81',
    'shareExtensionV3': '0xa21C434379CC44bfeD6e3c1342e49951804ec30f',
}

def cast(*args, stdin=None):
    p = subprocess.run(['cast', *args], input=stdin, text=True, capture_output=True)
    if p.returncode: raise RuntimeError('cast operation failed: ' + args[0])
    return p.stdout.strip()

def selector(signature):
    return cast('sig', signature)

def normalized(code, address):
    raw = bytes.fromhex(code[2:])
    if len(raw) > 2:
        size = int.from_bytes(raw[-2:], 'big')
        # Solidity CBOR metadata is a map. Do not remove arbitrary trailing bytes.
        if 0 < size < len(raw)-2 and 0xa0 <= raw[-size-2] <= 0xbf:
            raw = raw[:-size-2]
    return '0x' + raw.hex().replace(address[2:].lower(), '00'*20)

def compare_push20_operands(left, right):
    """Describe literal address differences; this is not semantic equivalence."""
    x,y=bytes.fromhex(left[2:]),bytes.fromhex(right[2:])
    if len(x)!=len(y): return {'sameInstructionBodyExceptPush20':False}
    i=0; differences=[]
    while i<len(x):
        if x[i]!=y[i]: return {'sameInstructionBodyExceptPush20':False}
        width=x[i]-0x5f if 0x60<=x[i]<=0x7f else 0
        a,b=x[i+1:i+1+width],y[i+1:i+1+width]
        if a!=b:
            if width!=20: return {'sameInstructionBodyExceptPush20':False}
            differences.append({'offset':i,'robinhood':'0x'+a.hex(),'base':'0x'+b.hex()})
        i+=1+width
    return {'sameInstructionBodyExceptPush20':True,'differingAddressOperands':differences}

def rpc(url, requests):
    results = []
    for start in range(0, len(requests), 30):
        chunk = requests[start:start+30]
        body = [{'jsonrpc':'2.0','id':i,'method':m,'params':p} for i,(m,p) in enumerate(chunk)]
        req = urllib.request.Request(url, json.dumps(body).encode(), {'Content-Type':'application/json','User-Agent':'Mozilla/5.0'})
        try:
            with urllib.request.urlopen(req, timeout=60) as response: data = json.load(response)
        except urllib.error.HTTPError as e:
            raise RuntimeError('HTTP '+str(e.code)+' during configured RPC read') from None
        except Exception as e:
            raise RuntimeError(type(e).__name__ + ' during configured RPC read') from None
        if not isinstance(data, list): raise RuntimeError('RPC rejected batch')
        ordered = {x['id']: x for x in data}
        for i in range(len(chunk)):
            item = ordered[i]
            results.append(item.get('result') if 'error' not in item else {'rpcError':item['error']['code']})
    return results

def address_word(a): return a[2:].lower().rjust(64,'0')
def as_address(value): return '0x' + value[-40:] if isinstance(value,str) and len(value)==66 else value

def main():
    allowed = {'RPC_URL_BASE','ROBINHOOD_RPC_URL','RPC_URL_ROBINHOOD'}
    settings = {k:os.environ[k] for k in allowed if os.environ.get(k)}
    if Path('.env').exists():
        for line in Path('.env').read_text().splitlines():
            if '=' in line and not line.lstrip().startswith('#'):
                k,v=line.split('=',1)
                if k.strip() in allowed: settings.setdefault(k.strip(),v.strip().strip('"').strip("'"))
    urls = {'robinhood':settings.get('ROBINHOOD_RPC_URL') or settings['RPC_URL_ROBINHOOD'], 'base':settings.get('RPC_URL_BASE','https://mainnet.base.org')}
    batch_path=Path('script/res/gnosis-batch-upgrade-v5-4663.json')
    batch=json.loads(batch_path.read_text())
    addresses=dict(ADDRESSES)
    for tx in batch['transactions']:
        if tx['to'].lower() not in {a.lower() for a in addresses.values()}:
            addresses['batchTarget'+str(len(addresses))]=tx['to']
    report={'observedAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'sourceRevision':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
            'batchSha256':hashlib.sha256(batch_path.read_bytes()).hexdigest(),
            'submittedTransactions':False,'chains':{},'comparison':[]}
    runtime_bodies={}
    query_spec=[]
    zk_kind=cast('keccak',stdin='MetaLeX.SignerCondition.ZKPassport.v1')
    for signature in ['issuanceManagerFactory()','cyberCorpSingleFactory()','dealManagerFactory()',
                      'roundManagerFactory()','stable()','lexchexAuth()','registryAddress()','uriBuilder()']:
        query_spec.append(('corporateFactory.'+signature,FACTORY,signature,'','address'))
    for name in ['singleFactory','issuanceFactory','dealFactory','roundFactory']:
        query_spec.append((name+'.ref',addresses[name],'getRefImplementation()','','address'))
    for name,signature,kind in [
        ('issuanceFactory','getCyberCertPrinterRefImplementation()','address'),
        ('issuanceFactory','getCyberScripRefImplementation()','address'),
        ('dealFactory','getDefaultFeeRatio()','uint'),('dealFactory','getSecondaryFeeRatio()','uint'),
        ('roundFactory','getDefaultFeeRatio()','uint'),('roundFactory','getPlatformPayable()','address'),
        ('uriBuilder','imageBuilder()','address'),('killSwitch','metalexAdmin()','address'),
        ('killSwitch','legionAdmin()','address'),('killSwitch','killed()','uint'),
        ('badge','AUTH()','address')]:
        query_spec.append((name+'.'+signature,addresses[name],signature,'',kind))
    for name in ['coreAuth','lexAuth','badgeAuth']:
        query_spec.append((name+'.safeRole',addresses[name],'userRoles(address)',address_word(SAFE),'uint'))
    query_spec.append(('badge.minterKeys',addresses['badge'],'issuerKeys(address)',address_word(addresses['lexMinter']),'uint'))
    query_spec.append(('registry.zkpassportConfig',REGISTRY,'getSignerConditionConfig(bytes32)',zk_kind[2:],'bytes'))
    for name,chain_id in [('robinhood',4663),('base',8453)]:
        url=urls[name]
        cid,block=rpc(url,[('eth_chainId',[]),('eth_blockNumber',[])])
        assert int(cid,16)==chain_id
        if os.environ.get(name.upper()+'_COMPARE_BLOCK'):
            block=hex(int(os.environ[name.upper()+'_COMPARE_BLOCK']))
        block_header=rpc(url,[('eth_getBlockByNumber',[block,False])])[0]
        print(name, 'block',int(block,16),flush=True)
        codes=rpc(url,[('eth_getCode',[a,block]) for a in addresses.values()])
        slots=rpc(url,[('eth_getStorageAt',[a,SLOT,block]) for a in addresses.values()])
        entries={k:{'address':a,'codeBytes':(len(c)-2)//2,'codeHash':cast('keccak',stdin=c),
                    'implementation':as_address(s)} for (k,a),c,s in zip(addresses.items(),codes,slots)}
        values=rpc(url,[('eth_call',[{'to':a,'data':selector(s)+args},block]) for _,a,s,args,_ in query_spec])
        state={label:(as_address(v) if kind=='address' else int(v,16) if kind=='uint' and isinstance(v,str) else v)
               for (label,_,_,_,kind),v in zip(query_spec,values)}
        # Decode the bytes return to retain the exact inner ABI config.
        if isinstance(state['registry.zkpassportConfig'],str):
            state['registry.zkpassportConfig']=cast('abi-decode','f()(bytes)',state['registry.zkpassportConfig'])
        token=state['corporateFactory.stable()']
        token_values=rpc(url,[('eth_call',[{'to':token,'data':selector(s)},block]) for s in ['name()','symbol()','decimals()']])
        state['paymentToken']={k:(json.loads(cast('abi-decode','f()(string)',v)) if k!='decimals' else int(v,16)) for k,v in zip(['name','symbol','decimals'],token_values)}
        state['roundFactory.paymentTokenWhitelistedForLexchexMint']=int(rpc(url,[('eth_call',[{'to':addresses['roundFactory'],
            'data':selector('isWhitelistedToken(address)')+address_word(token)},block])])[0],16)
        impls={k:e['implementation'] for k,e in entries.items() if e['implementation'] != '0x'+'00'*20}
        for label,_,_,_,kind in query_spec:
            if kind=='address' and ('ref' in label or 'RefImplementation' in label or 'imageBuilder' in label):
                if isinstance(state[label],str): impls[label]=state[label]
        impl_codes=rpc(url,[('eth_getCode',[a,block]) for a in impls.values()])
        implementations={k:{'address':a,'codeBytes':(len(c)-2)//2,'codeHash':cast('keccak',stdin=c),
                                'normalizedCodeHash':cast('keccak',stdin=normalized(c,a))}
                         for (k,a),c in zip(impls.items(),impl_codes)}
        runtime_bodies[name]={k:normalized(c,a) for (k,a),c in zip(impls.items(),impl_codes)}
        # Candidate production SAFE templates from repository deployment scripts.
        tids=[('safe_reg_s_32',hex(32)[2:].rjust(64,'0')),('ace_safe_reg_d_v1',b'ace_safe_reg_d_v1'.hex().ljust(64,'0')),
              ('ace_safev1',b'ace_safev1'.hex().ljust(64,'0'))]
        raw=rpc(url,[('eth_call',[{'to':REGISTRY,'data':selector('getTemplateDetails(bytes32)')+tid},block]) for _,tid in tids])
        templates={}
        for (label,tid),v in zip(tids,raw):
            templates[label]={'id':'0x'+tid,'details':cast('abi-decode','f()(string,string,string[],string[])',v) if isinstance(v,str) else v}
        report['chains'][name]={'chainId':chain_id,'blockNumber':int(block,16),'blockHash':block_header['hash'],
                               'blockTimestamp':int(block_header['timestamp'],16),'contracts':entries,
                               'state':state,'implementations':implementations,'templates':templates}
    rh,base=report['chains']['robinhood'],report['chains']['base']
    for k,entry in rh['contracts'].items():
        other=base['contracts'][k]
        row={'name':k,'address':entry['address'],'bothHaveCode':entry['codeBytes']>0 and other['codeBytes']>0,'runtimeMatches':entry['codeHash']==other['codeHash']}
        if k in rh['implementations'] and k in base['implementations']:
            x,y=rh['implementations'][k],base['implementations'][k]
            row.update(implementationAddressMatches=x['address']==y['address'],implementationRuntimeMatches=x['codeHash']==y['codeHash'],implementationNormalizedMatches=x['normalizedCodeHash']==y['normalizedCodeHash'])
        report['comparison'].append(row)
    checks=[]
    setters={selector('setRefImplementation(address)'):'.ref',
             selector('setCyberCertPrinterRefImplementation(address)'):'.getCyberCertPrinterRefImplementation()',
             selector('setCyberScripRefImplementation(address)'):'.getCyberScripRefImplementation()',
             selector('setDefaultSecondaryFeeRatio(uint256)'):'.getSecondaryFeeRatio()'}
    for i,tx in enumerate(batch['transactions']):
        label=next(k for k,a in addresses.items() if a.lower()==tx['to'].lower())
        data=tx['data']; sel=data[:10]; expected='0x'+data[34:74]
        if sel==selector('upgradeToAndCall(address,bytes)'):
            observed=rh['contracts'][label]['implementation']
            # URI upgrade contains initialize/setImageBuilder calldata atomically.
            if label=='uriBuilder':
                # Decode the inner bytes using cast instead of relying on word offsets.
                decoded=cast('abi-decode','f()(address,bytes)','0x'+data[10:]).splitlines()
                inner=decoded[1].strip()
                image_expected='0x'+inner[-40:]
                checks.append({'index':i,'target':'uriBuilder.imageBuilder', 'expected':image_expected,
                               'observed':rh['state']['uriBuilder.imageBuilder()'],
                               'matches':image_expected.lower()==rh['state']['uriBuilder.imageBuilder()'].lower()})
        elif sel in setters:
            observed=rh['state'][label+setters[sel]]
            if sel==selector('setDefaultSecondaryFeeRatio(uint256)'): expected=int(data[10:74],16)
        elif sel==selector('setSignerConditionConfig(bytes32,bytes)'):
            decoded=cast('abi-decode','f()(bytes32,bytes)','0x'+data[10:]).splitlines()
            assert decoded[0].lower()==zk_kind.lower()
            expected=decoded[1].strip();observed=rh['state']['registry.zkpassportConfig']
        else:
            checks.append({'index':i,'target':label,'selector':sel,'checked':False});continue
        checks.append({'index':i,'target':label,'expected':expected,'observed':observed,'matches':str(expected).lower()==str(observed).lower()})
    report['safeBatchChecks']=checks
    for key in sorted(rh['implementations'].keys() & base['implementations'].keys()):
        x,y=rh['implementations'][key],base['implementations'][key]
        report.setdefault('implementationComparison',[]).append({'name':key,'robinhoodAddress':x['address'],
            'baseAddress':y['address'],'robinhoodBytes':x['codeBytes'],'baseBytes':y['codeBytes'],
            'normalizedCodeMatches':x['normalizedCodeHash']==y['normalizedCodeHash'],
            **compare_push20_operands(runtime_bodies['robinhood'][key],runtime_bodies['base'][key])})
    report['normalization']='Strip trailing Solidity CBOR map and replace runtime own address bytes with zeros. Does not normalize linked libraries or prove behavioral equivalence.'
    output=Path('notes/ai/tasks/robinhood-post-v5-comparison-20261030.json')
    output.write_text(json.dumps(report,indent=2)+'\n')
    print('Batch direct checks:',sum(c.get('matches',False) for c in checks),'/',len(checks))
    print('Unmatched:',[c for c in checks if c.get('matches') is False])
    print('Missing code:',[c['name'] for c in report['comparison'] if not c['bothHaveCode']])
    print('Implementation differences:',[c for c in report['comparison'] if c.get('implementationNormalizedMatches') is False])
    print('State:',json.dumps({k:v['state'] for k,v in report['chains'].items()},indent=2))
    print('Templates:',json.dumps({k:v['templates'] for k,v in report['chains'].items()},indent=2))
    print('Saved',output)

if __name__=='__main__': main()
