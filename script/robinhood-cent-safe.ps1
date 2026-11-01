param(
    [ValidateSet('Quote','DryRun','Broadcast')]
    [string]$Mode = 'DryRun'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $repositoryRoot
try {
    $forgeArguments = @(
        'script', 'script/robinhood-cent-safe.s.sol:RobinhoodCentSafeScript',
        '--rpc-url', 'robinhood', '--use', '0.8.28', '--evm-version', 'cancun', '--via-ir', '--offline',
        '-R', '@openzeppelin/contracts/=dependencies/openzeppelin-contracts/contracts/',
        '-R', '@openzeppelin/contracts-upgradeable/=dependencies/openzeppelin-contracts-upgradeable/contracts/'
    )
    if ($Mode -eq 'Quote') {
        $forgeArguments += @('--sig','quote()')
    } elseif ($Mode -eq 'Broadcast') {
        $forgeArguments += @('--broadcast','--slow')
    }
    # Foundry/the Solidity script loads environment variables. This wrapper
    # never reads, prints, writes or passes a private-key value on the CLI.
    & forge @forgeArguments
    if ($LASTEXITCODE -ne 0) { throw "Foundry $Mode failed (exit $LASTEXITCODE)." }
} finally {
    Pop-Location
}
