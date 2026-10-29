param(
    [switch]$Submit,
    [switch]$StatusOnly,
    [switch]$RequireExactMatch,
    [switch]$RetrySimilarMatch,
    [string[]]$Address = @(),
    [ValidateRange(1, 20)][int]$PollRounds = 8,
    [ValidateRange(1, 30)][int]$PollSeconds = 5
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$script:ApiUrl = 'https://api.etherscan.io/v2/api'
$script:LastApiCall = [DateTime]::MinValue

function Read-Field($Object, [string]$Name, $Default = $null) {
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $Default
}

function Invoke-Explorer([int]$Chain, [string]$Action, [hashtable]$Fields) {
    if ($Chain -notin @(1, 4663) -or $Action -notin @('getsourcecode', 'verifysourcecode', 'checkverifystatus')) {
        throw 'Unsupported explorer operation.'
    }
    $delay = 700 - ([DateTime]::UtcNow - $script:LastApiCall).TotalMilliseconds
    if ($delay -gt 0) { Start-Sleep -Milliseconds ([int]$delay) }
    # Etherscan V2 reads routing/authentication from the URL even for form POSTs.
    $uri = '{0}?chainid={1}&module=contract&action={2}&apikey={3}' -f $script:ApiUrl, $Chain, $Action, [Uri]::EscapeDataString($script:ApiKey)
    $parameters = @{}
    foreach ($name in $Fields.Keys) {
        if ($name -in @('chainid', 'module', 'action', 'apikey')) { throw 'Cannot override explorer routing or credentials.' }
        $parameters[$name] = $Fields[$name]
    }
    $method = if ($Action -eq 'verifysourcecode') { 'Post' } else { 'Get' }
    try {
        Invoke-RestMethod -Uri $uri -Method $method -Body $parameters -MaximumRedirection 0 -TimeoutSec 30
    } catch {
        # Do not print request URLs, bodies, keys or potentially sensitive exception dumps.
        throw "Etherscan $Action request failed; rerun to resume after checking connectivity."
    } finally { $script:LastApiCall = [DateTime]::UtcNow }
}

function Invoke-ChainRead([string]$Method, [object[]]$Parameters) {
    if ($Method -notin @('eth_chainId', 'eth_getTransactionReceipt', 'eth_getTransactionByHash', 'eth_getCode')) {
        throw 'Unsupported RPC operation.'
    }
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Parameters } | ConvertTo-Json -Depth 10 -Compress
    try {
        $response = Invoke-RestMethod -Uri $script:RpcUrl -Method Post -ContentType 'application/json' -Body $body -MaximumRedirection 0 -TimeoutSec 30
    } catch { throw "RPC $Method request failed (endpoint withheld)." }
    if (Read-Field $response 'error') { throw "RPC $Method returned an error." }
    return $response.result
}

function Read-Source([int]$Chain, [string]$ContractAddress) {
    $response = Invoke-Explorer $Chain 'getsourcecode' @{ address = $ContractAddress }
    if ($response.status -ne '1' -or $response.result -is [string]) { throw "Source lookup failed on chain $Chain." }
    return @($response.result)[0]
}

function Make-VerificationPackage($Source, $Recipe) {
    $text = [string]$Source.SourceCode
    if (-not $text) { throw 'Historical Ethereum source is not verified; no local source will be substituted.' }
    if ($text.StartsWith('{{') -and $text.EndsWith('}}')) { $text = $text.Substring(1, $text.Length - 2) }
    try { $inputJson = $text | ConvertFrom-Json } catch { throw 'Historical source is not a standard JSON package.' }
    if ((Read-Field $inputJson 'language') -ne 'Solidity' -or -not (Read-Field $inputJson 'sources') -or -not (Read-Field $inputJson 'settings')) {
        throw 'Historical source package is incomplete.'
    }
    foreach ($file in $inputJson.sources.PSObject.Properties) {
        if ($null -eq (Read-Field $file.Value 'content')) { throw 'Historical source contains URL-only inputs; refusing.' }
    }
    $fileName = [string](Read-Field $Source 'ContractFileName' '')
    $contractName = [string]$Source.ContractName
    if (-not $fileName) {
        $matches = @($inputJson.sources.PSObject.Properties | Where-Object {
            $_.Value.content -match ('\b(contract|library)\s+' + [regex]::Escape($contractName) + '\b')
        })
        if ($matches.Count -ne 1) { throw 'Cannot resolve a unique historical contract source path.' }
        $fileName = $matches[0].Name
    }
    if (-not $inputJson.sources.PSObject.Properties[$fileName]) { throw 'Historical contract source path is absent.' }
    return @{
        contractaddress = $Recipe.address
        sourceCode = $text
        codeformat = 'solidity-standard-json-input'
        contractname = "$($fileName):$contractName"
        compilerversion = $Source.CompilerVersion
        constructorArguments = $Recipe.constructorArguments
        # Some older Etherscan-compatible deployments use this historical spelling.
        constructorArguements = $Recipe.constructorArguments
    }
}

function Set-ExistingVerification($Result, $Source) {
    if (-not $Source.SourceCode) { return $false }
    $similar = [string](Read-Field $Source 'SimilarMatch' '')
    if ($similar) {
        $Result.status = 'similar-match'
        $Result.message = "Explorer provides similar-match source via $similar; constructor arguments are not explorer-exact-verified."
    } else {
        $Result.status = 'verified'; $Result.message = 'Explorer reports exact verified source.'
    }
    return $true
}

function Confirm-Replay($Entry, $Recipe, $Broadcast) {
    $transactions = @($Broadcast.transactions | Where-Object {
        $inputData = Read-Field $_.transaction 'input' (Read-Field $_.transaction 'data' '')
        (Read-Field $_.transaction 'to' '') -ieq '0x4e59b44847b379578588920cA78FbF26c0B4956C' -and $inputData -ieq $Entry.data
    })
    if ($transactions.Count -ne 1) { throw "Missing or ambiguous broadcast payload for $($Recipe.name)." }
    $hash = [string]$transactions[0].hash
    $receipt = Invoke-ChainRead 'eth_getTransactionReceipt' @($hash)
    if ($null -eq $receipt -or $receipt.status -ne '0x1' -or $receipt.transactionHash -ine $hash) {
        throw "Deployment receipt is missing or unsuccessful for $($Recipe.name)."
    }
    $transaction = Invoke-ChainRead 'eth_getTransactionByHash' @($hash)
    if ($null -eq $transaction -or $transaction.to -ine '0x4e59b44847b379578588920cA78FbF26c0B4956C' -or $transaction.input -ine $Entry.data -or $transaction.value -ne '0x0') {
        throw "On-chain deployment payload mismatch for $($Recipe.name)."
    }
    $code = Invoke-ChainRead 'eth_getCode' @($Recipe.address, 'latest')
    if (-not $code -or $code -eq '0x') { throw "No deployed code for $($Recipe.name)." }
    return $hash
}

function Save-VerificationState {
    $report = [ordered]@{
        chainId = 4663; sourceChainId = 1; updatedAtUtc = [DateTime]::UtcNow.ToString('o')
        manifestSha256 = $script:ManifestHash; recipesSha256 = $script:RecipeHash
        contracts = @($script:Results.Values | Sort-Object address)
    }
    $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:StatePath -Encoding UTF8
}

# Dot-sourcing exposes pure/request helpers for offline fixture tests without running network work.
if ($MyInvocation.InvocationName -eq '.') { return }

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    if ($Submit -and $StatusOnly) { throw 'Choose Submit or StatusOnly, not both.' }
    $settings = @{}
    foreach ($name in @('ROBINHOOD_RPC_URL', 'ROBINHOOD_ETHERSCAN_API_KEY', 'ETHERSCAN_API_KEY')) {
        $settings[$name] = [Environment]::GetEnvironmentVariable($name)
    }
    if (Test-Path -LiteralPath '.env') {
        foreach ($line in Get-Content -LiteralPath '.env') {
            if ($line -match '^\s*(ROBINHOOD_RPC_URL|ROBINHOOD_ETHERSCAN_API_KEY|ETHERSCAN_API_KEY)\s*=\s*(.*?)\s*$') {
                if (-not $settings[$Matches[1]]) { $settings[$Matches[1]] = $Matches[2].Trim([char[]]@('"', "'")) }
            }
        }
    }
    $script:RpcUrl = $settings['ROBINHOOD_RPC_URL']
    $script:ApiKey = $settings['ROBINHOOD_ETHERSCAN_API_KEY']
    if (-not $script:ApiKey) { $script:ApiKey = $settings['ETHERSCAN_API_KEY'] }
    if (-not $script:RpcUrl -or -not $script:ApiKey) { throw 'Configure ROBINHOOD_RPC_URL and ROBINHOOD_ETHERSCAN_API_KEY in the local environment.' }

    $script:ManifestHash = '0e08923887062963553ad3d8a36e911c0e68cb05c46de075bbf304856d24f82a'
    $script:RecipeHash = '9e738142f301c351c32953c74530afc196797bce8efdaee727111e2965b0c373'
    if ((Get-FileHash 'script/res/robinhood-bootstrap.json' -Algorithm SHA256).Hash -ine $script:ManifestHash) { throw 'Pinned bootstrap manifest changed.' }
    if ((Get-FileHash 'script/res/robinhood-bootstrap-verification.json' -Algorithm SHA256).Hash -ine $script:RecipeHash) { throw 'Pinned verification recipes changed.' }
    $manifest = Get-Content 'script/res/robinhood-bootstrap.json' -Raw | ConvertFrom-Json
    $recipes = Get-Content 'script/res/robinhood-bootstrap-verification.json' -Raw | ConvertFrom-Json
    $entries = @($manifest.deployments | Where-Object { $_.sourceTx -ne ('0x' + ('0' * 64)) })
    if ($entries.Count -ne 32 -or @($recipes.contracts).Count -ne 32 -or $recipes.targetChainId -ne 4663 -or $recipes.sourceChainId -ne 1 -or $recipes.manifestSha256 -ine $script:ManifestHash) { throw 'Unexpected verification scope.' }
    foreach ($recipe in $recipes.contracts) {
        $entry = @($entries | Where-Object { $_.addr -ieq $recipe.address })
        if ($entry.Count -ne 1 -or $entry[0].sourceTx -ine $recipe.sourceTx -or -not $entry[0].data.EndsWith($recipe.constructorArguments, [StringComparison]::OrdinalIgnoreCase)) { throw 'Verification recipe does not match manifest.' }
    }
    foreach ($requested in $Address) {
        if (-not @($recipes.contracts | Where-Object { $_.address -ieq $requested }).Count) { throw "Address is outside the historical bootstrap scope: $requested" }
    }
    $selected = @($recipes.contracts | Where-Object { $Address.Count -eq 0 -or $_.address -in $Address })
    $broadcast = Get-Content 'broadcast/bootstrap-robinhood.s.sol/4663/run-latest.json' -Raw | ConvertFrom-Json
    if ($broadcast.chain -ne 4663 -or @(Read-Field $broadcast 'pending' @()).Count -gt 0) { throw 'Wrong-chain or pending deployment artifact; wait for deployment completion.' }
    if ((Invoke-ChainRead 'eth_chainId' @()) -ne '0x1237') { throw 'RPC is not Robinhood mainnet 4663.' }
    $directory = Join-Path (Get-Location) 'out/robinhood-verification'
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $script:StatePath = Join-Path $directory 'state.json'
    $script:Results = @{}
    if (Test-Path -LiteralPath $script:StatePath) {
        $saved = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
        if ($saved.chainId -ne 4663 -or $saved.manifestSha256 -ine $script:ManifestHash -or $saved.recipesSha256 -ine $script:RecipeHash) { throw 'Verification state belongs to another scope.' }
        foreach ($item in $saved.contracts) { $script:Results[$item.address.ToLowerInvariant()] = $item }
    }
    # Complete every selected deployment check before any explorer submission.
    foreach ($recipe in $selected) {
        $entry = $entries | Where-Object { $_.addr -ieq $recipe.address }
        $hash = Confirm-Replay $entry $recipe $broadcast
        $id = $recipe.address.ToLowerInvariant()
        if (-not $script:Results.ContainsKey($id)) {
            $script:Results[$id] = [pscustomobject]@{ address = $recipe.address; name = $recipe.name; transactionHash = $hash; status = 'deployed'; guid = ''; message = '' }
        }
        Write-Host "[receipt confirmed] $($recipe.name): $($recipe.address)"
    }
    Save-VerificationState
    foreach ($recipe in $selected) {
        $result = $script:Results[$recipe.address.ToLowerInvariant()]
        try {
            $target = Read-Source 4663 $recipe.address
            if ($target.SourceCode -and (-not (Read-Field $target 'SimilarMatch' '') -or -not $RetrySimilarMatch -or $StatusOnly)) {
                $null = Set-ExistingVerification $result $target
            } elseif ($StatusOnly) {
                $result.status = 'unverified'; $result.message = 'Explorer has no verified source.'
            } elseif ($result.guid -and $Submit -and $result.status -ne 'failed') {
                $result.status = 'pending'
            } else {
                $source = Read-Source 1 $recipe.address
                $package = Make-VerificationPackage $source $recipe
                # Cache only already-public source/settings. No API key is present in this object.
                $package | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $directory "$($recipe.address).package.json") -Encoding UTF8
                if (-not $Submit) {
                    $result.status = 'prepared'; $result.message = 'Public historical source package ready; nothing submitted.'
                } else {
                    $response = Invoke-Explorer 4663 'verifysourcecode' $package
                    if ($response.status -eq '1') {
                        $result.guid = [string]$response.result; $result.status = 'pending'; $result.message = 'Verification request queued.'
                    } elseif ([string]$response.result -match '(?i)already verified') {
                        $record = Read-Source 4663 $recipe.address
                        if (-not (Set-ExistingVerification $result $record)) { throw 'Already-verified response has no readable verified source.' }
                    } else { throw ([string]$response.result) }
                }
            }
        } catch {
            $result.status = 'failed'; $result.message = $_.Exception.Message.Replace($script:ApiKey, '<redacted>')
        }
        Save-VerificationState
        Write-Host "[$($result.status)] $($recipe.name): $($result.message)"
    }
    if ($Submit) {
        for ($round = 0; $round -lt $PollRounds; $round++) {
            $pending = @($selected | ForEach-Object { $script:Results[$_.address.ToLowerInvariant()] } | Where-Object { $_.status -eq 'pending' })
            if ($pending.Count -eq 0) { break }
            Start-Sleep -Seconds $PollSeconds
            foreach ($result in $pending) {
                try {
                    $response = Invoke-Explorer 4663 'checkverifystatus' @{ guid = $result.guid }
                    $message = [string]$response.result
                    if ($response.status -eq '1' -and $message -match '(?i)^Pass - Verified') {
                        $result.status = 'verified'; $result.message = $message
                        Write-Host "[verified] $($result.name): $($result.address)"
                    } elseif ($message -match '(?i)already verified') {
                        $record = Read-Source 4663 $result.address
                        if (-not (Set-ExistingVerification $result $record)) { throw 'Already-verified response has no readable verified source.' }
                        Write-Host "[$($result.status)] $($result.name): $($result.message)"
                    } elseif ($message -notmatch '(?i)pending|queue|in progress') {
                        $result.status = 'failed'; $result.message = $message.Replace($script:ApiKey, '<redacted>')
                        Write-Host "[failed] $($result.name): $($result.message)"
                    }
                } catch { $result.message = 'Status read failed; queued GUID retained for the next run.' }
                Save-VerificationState
            }
        }
    }
    $counts = @($selected | ForEach-Object { $script:Results[$_.address.ToLowerInvariant()] } | Group-Object status | ForEach-Object { "$($_.Name)=$($_.Count)" })
    Write-Host ("Result: " + ($counts -join ', ') + ". State: $script:StatePath")
    $incomplete = @($selected | Where-Object {
        $status = $script:Results[$_.address.ToLowerInvariant()].status
        if ($Submit -or $StatusOnly) {
            $status -ne 'verified' -and ($RequireExactMatch -or $status -ne 'similar-match')
        } else { $status -notin @('verified', 'similar-match', 'prepared') }
    })
    if ($incomplete.Count -gt 0) { throw 'Some contracts remain unverified; inspect state.json and rerun to resume.' }
} finally { Pop-Location }
