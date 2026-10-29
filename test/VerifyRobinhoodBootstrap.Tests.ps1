$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../script/verify-robinhood-bootstrap.ps1')

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Assert-Refuses([scriptblock]$Action, [string]$Message) {
    $refused = $false
    try { & $Action } catch { $refused = $true }
    Assert-True $refused $Message
}

$standard = @{ language = 'Solidity'; sources = @{ 'old/Auth.sol' = @{ content = 'contract Auth {}' } }; settings = @{ optimizer = @{ enabled = $true; runs = 15 }; viaIR = $true } } | ConvertTo-Json -Depth 10 -Compress
$source = [pscustomobject]@{ SourceCode = '{' + $standard + '}'; ContractName = 'Auth'; ContractFileName = 'old/Auth.sol'; CompilerVersion = 'v0.8.28+commit.7893614a' }
$recipe = [pscustomobject]@{ address = '0x0000000000000000000000000000000000000001'; constructorArguments = ('0' * 64) }
$package = Make-VerificationPackage $source $recipe
Assert-True ($package.sourceCode -eq $standard) 'Standard JSON source/settings changed.'
Assert-True ($package.contractname -eq 'old/Auth.sol:Auth') 'Wrong historical contract path.'
Assert-True ($package.constructorArguments -eq $recipe.constructorArguments) 'Recipe constructor arguments were not preserved.'
Assert-True (-not $package.ContainsKey('apikey')) 'Key entered the source cache.'
$outcome = [pscustomobject]@{ status = ''; message = '' }
Assert-True (Set-ExistingVerification $outcome $source) 'Existing source was not recognized.'
Assert-True ($outcome.status -eq 'verified') 'Exact source was misclassified.'
$source | Add-Member -NotePropertyName SimilarMatch -NotePropertyValue '0x0000000000000000000000000000000000000002'
Assert-True (Set-ExistingVerification $outcome $source) 'Similar source was not recognized.'
Assert-True ($outcome.status -eq 'similar-match') 'Similar source was mislabeled as exact verification.'
$source.SourceCode = ''
Assert-Refuses { Make-VerificationPackage $source $recipe } 'Missing historical source was accepted.'
$source.SourceCode = '{"language":"Solidity","sources":{"A.sol":{"urls":["https://invalid.example/A.sol"]}},"settings":{}}'
Assert-Refuses { Make-VerificationPackage $source $recipe } 'URL-only sources were accepted.'
Assert-Refuses { Invoke-Explorer 46630 'getsourcecode' @{} } 'An out-of-scope chain was accepted.'
$script:ApiKey = 'fixture-key'
Assert-Refuses { Invoke-Explorer 4663 'getsourcecode' @{ chainid = 1 } } 'Explorer chain routing could be overridden.'
function Invoke-RestMethod([string]$Uri, [string]$Method, [hashtable]$Body, [int]$MaximumRedirection, [int]$TimeoutSec) {
    Assert-True ($Uri -match '^https://api\.etherscan\.io/v2/api\?chainid=4663&module=contract&action=verifysourcecode&apikey=fixture-key$') 'V2 POST routing was not in the query string.'
    Assert-True ($Method -eq 'Post' -and $Body.sourceCode -eq 'public fixture') 'Source verification did not use a form POST.'
    Assert-True (-not $Body.ContainsKey('apikey')) 'Credentials entered the request body/cache.'
    return [pscustomobject]@{ status = '1'; result = 'fixture-guid' }
}
Assert-True ((Invoke-Explorer 4663 'verifysourcecode' @{ sourceCode = 'public fixture' }).result -eq 'fixture-guid') 'V2 request construction failed.'

$script:RpcFixture = @{
    eth_getTransactionReceipt = [pscustomobject]@{ status = '0x1'; transactionHash = '0xabc' }
    eth_getTransactionByHash = [pscustomobject]@{ to = '0x4e59b44847b379578588920cA78FbF26c0B4956C'; input = '0x1234'; value = '0x0' }
    eth_getCode = '0x6000'
}
function Invoke-ChainRead([string]$Method, [object[]]$Parameters) { return $script:RpcFixture[$Method] }
$entry = [pscustomobject]@{ data = '0x1234' }
$recipe | Add-Member -NotePropertyName name -NotePropertyValue 'Fixture'
$broadcast = [pscustomobject]@{ transactions = @([pscustomobject]@{ hash = '0xabc'; transaction = [pscustomobject]@{ to = '0x4e59b44847b379578588920cA78FbF26c0B4956C'; input = '0x1234' } }) }
Assert-True ((Confirm-Replay $entry $recipe $broadcast) -eq '0xabc') 'Valid receipt/payload/code was refused.'
$script:RpcFixture.eth_getTransactionReceipt.status = '0x0'
Assert-Refuses { Confirm-Replay $entry $recipe $broadcast } 'Reverted deployment was accepted.'
$script:RpcFixture.eth_getTransactionReceipt.status = '0x1'
$script:RpcFixture.eth_getTransactionByHash.input = '0xabcd'
Assert-Refuses { Confirm-Replay $entry $recipe $broadcast } 'Wrong on-chain payload was accepted.'
$script:RpcFixture.eth_getTransactionByHash.input = '0x1234'
$script:RpcFixture.eth_getCode = '0x'
Assert-Refuses { Confirm-Replay $entry $recipe $broadcast } 'Absent target code was accepted.'
Write-Host 'Verification helper fixtures passed: historical package, constructor args, no cached keys, missing/URL-only source refusal, successful/reverted receipt, payload mismatch and missing code.'
