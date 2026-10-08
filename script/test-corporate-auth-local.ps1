param(
    [string]$RpcUrl = 'http://127.0.0.1:18545',
    [Parameter(Mandatory=$true)][string]$AuthAddress,
    [Parameter(Mandatory=$true)][string]$CorpAddress
)

$ErrorActionPreference = 'Stop'
$endpoint = [Uri]$RpcUrl
if (-not $endpoint.IsLoopback) { throw 'Disposable loopback Anvil only.' }
if ((& cast chain-id --rpc-url $RpcUrl) -ne '31337') { throw 'Expected local chain 31337.' }

# Public Anvil development keys, exclusively for this disposable local chain.
$rootKey = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'
$officerKey = '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d'
$rootAddress = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'
$officerAddress = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8'
if ((& cast call $AuthAddress 'rootAuthority()(address)' --rpc-url $RpcUrl) -ne $rootAddress) {
    throw 'Expected the local fixture root.'
}

function Invoke-LocalCase {
    param([string]$Name, [string]$Signature, [string[]]$Arguments, [string]$Caller, [string]$Key, [bool]$ExpectedSuccess,
        [string]$Target = $CorpAddress)
    # Sign first with an explicit gas limit so refusal cases can also be submitted.
    $signed = & cast mktx $Target $Signature @Arguments --private-key $Key --chain-id 31337 `
        --gas-limit 300000 --rpc-url $RpcUrl
    if ($LASTEXITCODE -ne 0) { throw "Signing failed: $Name" }
    $simulation = & cast call $Target $Signature @Arguments --from $Caller --rpc-url $RpcUrl 2>&1
    $simulatedSuccess = $LASTEXITCODE -eq 0
    if ($simulatedSuccess -ne $ExpectedSuccess) { throw "Unexpected simulation result: $Name" }
    $receiptText = & cast publish $signed --rpc-url $RpcUrl --json
    $receipt = $receiptText | ConvertFrom-Json
    $submittedSuccess = $receipt.status -eq '0x1'
    if ($submittedSuccess -ne $ExpectedSuccess) { throw "Unexpected submitted result: $Name" }
    [pscustomobject]@{
        case = $Name; signed = $true; simulationSucceeded = $simulatedSuccess;
        submittedSucceeded = $submittedSuccess; transactionHash = $receipt.transactionHash
    }
}

$registry = & cast call $AuthAddress 'releaseRegistry()(address)' --rpc-url $RpcUrl
$approvedImplementation = & cast call $registry 'borgAuthImplementation()(address)' --rpc-url $RpcUrl
$oldImplementation = & cast implementation $AuthAddress --rpc-url $RpcUrl
if ($oldImplementation -eq $approvedImplementation) { throw 'Expected a distinct approved upgrade.' }

$results = @(
    Invoke-LocalCase 'root config succeeds' 'setCompanyPayable(address)' @($officerAddress) $rootAddress $rootKey $true
    Invoke-LocalCase 'officer config refused' 'setCompanyPayable(address)' @($rootAddress) $officerAddress $officerKey $false
    Invoke-LocalCase 'officer signing succeeds' 'addEscrowedOfficerSignature(bytes)' @('0x1234') $officerAddress $officerKey $true
    Invoke-LocalCase 'root signing refused without officer membership' 'addEscrowedOfficerSignature(bytes)' @('0x1234') $rootAddress $rootKey $false
    Invoke-LocalCase 'unapproved auth upgrade refused' 'upgradeToAndCall(address,bytes)' @($oldImplementation,'0x') $rootAddress $rootKey $false $AuthAddress
    Invoke-LocalCase 'officer auth upgrade refused' 'upgradeToAndCall(address,bytes)' @($approvedImplementation,'0x') $officerAddress $officerKey $false $AuthAddress
    Invoke-LocalCase 'approved root auth upgrade succeeds' 'upgradeToAndCall(address,bytes)' @($approvedImplementation,'0x') $rootAddress $rootKey $true $AuthAddress
)
if ((& cast call $CorpAddress 'companyPayable()(address)' --rpc-url $RpcUrl) -ne $officerAddress) {
    throw 'Refused transaction changed the company payable.'
}
if ((& cast call $CorpAddress 'getEscrowedOfficerSignatureCount()(uint256)' --rpc-url $RpcUrl) -ne '1') {
    throw 'Expected exactly one authorized officer signature.'
}
if ((& cast call $AuthAddress 'rootAuthority()(address)' --rpc-url $RpcUrl) -ne $rootAddress `
    -or (& cast call $AuthAddress 'hasRole(address,uint256)(bool)' $officerAddress '2' --rpc-url $RpcUrl) -ne 'true' `
    -or (& cast implementation $AuthAddress --rpc-url $RpcUrl) -ne $approvedImplementation) {
    throw 'Upgrade failed to preserve authority or install the approved implementation.'
}
$results | ConvertTo-Json -Depth 4
