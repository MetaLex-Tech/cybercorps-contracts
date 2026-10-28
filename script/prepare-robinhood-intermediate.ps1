param(
    [ValidateSet(4663, 46630)]
    [int]$ExpectedChainId = 4663,
    [long]$ForkBlockNumber = 0
)

$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    # Foundry loads the remaining public settings from .env. No signing key is used.
    $rpcEndpoint = $env:ROBINHOOD_RPC_URL
    if (-not $rpcEndpoint -and (Test-Path -LiteralPath '.env')) {
        foreach ($line in Get-Content -LiteralPath '.env') {
            if ($line -match '^\s*ROBINHOOD_RPC_URL\s*=\s*(.*?)\s*$') {
                $rpcEndpoint = $Matches[1].Trim([char[]]@('"', "'"))
            }
        }
    }
    if (-not $rpcEndpoint) { throw 'ROBINHOOD_RPC_URL is required.' }
    $actualChainId = & cast chain-id --rpc-url $rpcEndpoint
    if ($LASTEXITCODE -ne 0) { throw 'Could not read the configured RPC chain ID.' }
    if ([int]$actualChainId -ne $ExpectedChainId) { throw "Wrong network: expected $ExpectedChainId, received $actualChainId." }

    $forgeArgs = @(
        'script', 'script/prepare-robinhood-intermediate.s.sol:PrepareRobinhoodIntermediateScript',
        '--sig', 'prepare()', '--rpc-url', $rpcEndpoint,
        '--sender', '0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B',
        '--use', '0.8.28', '--evm-version', 'cancun', '--via-ir', '--offline',
        '-R', '@openzeppelin/contracts/=dependencies/openzeppelin-contracts/contracts/',
        '-R', '@openzeppelin/contracts-upgradeable/=dependencies/openzeppelin-contracts-upgradeable/contracts/'
    )
    if ($ForkBlockNumber -gt 0) { $forgeArgs += @('--fork-block-number', "$ForkBlockNumber") }
    & forge @forgeArgs
    if ($LASTEXITCODE -ne 0) { throw 'Intermediate rehearsal failed; do not proceed to deployment.' }
    Write-Host 'Rehearsal passed. The .simulation.json output is for review only.'
} finally {
    Pop-Location
}
