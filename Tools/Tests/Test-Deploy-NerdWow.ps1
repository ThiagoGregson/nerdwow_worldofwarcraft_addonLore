[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$deploy = Join-Path (Split-Path -Parent $PSScriptRoot) 'Deploy-NerdWow.ps1'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('NerdWow-deploy-tests-' + [guid]::NewGuid().ToString('N'))
$links = [Collections.Generic.List[string]]::new()
$passed = 0

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Write-Fixture([string]$Path, [string]$Content) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function Expect-Failure([scriptblock]$Action, [string]$Pattern) {
    $message = $null
    try { & $Action | Out-Null } catch { $message = $_.Exception.Message }
    Assert ($null -ne $message -and $message -match $Pattern) "Falha esperada não observada ($Pattern): $message"
    $script:passed++
}

function Snapshot([string]$Root) {
    return (@(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }) -join "`n")
}

function New-TestJunction([string]$Path, [string]$Target) {
    New-Item -ItemType Junction -Path $Path -Target $Target | Out-Null
    $script:links.Add($Path)
}

try {
    $source = Join-Path $fixtureRoot 'source\NerdWow'
    $addOns = Join-Path $fixtureRoot 'game\Interface\AddOns'
    $destination = Join-Path $addOns 'NerdWow'
    New-Item -ItemType Directory -Path $source, $addOns -Force | Out-Null
    $realSource = Join-Path $projectRoot 'NerdWow'
    $toc = [IO.File]::ReadAllText((Join-Path $realSource 'NerdWow.toc'))
    $runtimeCount = 1 + @($toc -split '\r?\n' | Where-Object { $_ -match '^[^#].*\.lua$' }).Count
    Write-Fixture (Join-Path $source 'NerdWow.toc') $toc
    foreach ($line in $toc -split '\r?\n') {
        if ($line -match '^[^#].*\.lua$') {
            Write-Fixture (Join-Path $source $line) ([IO.File]::ReadAllText((Join-Path $realSource $line)))
        }
    }
    Write-Fixture (Join-Path $source 'Tests\Ignored.lua') 'not runtime'
    Write-Fixture (Join-Path $source '.git\config') 'not runtime'
    Write-Fixture (Join-Path $source 'Unlisted.lua') 'not runtime'
    Write-Fixture (Join-Path $addOns 'DialogueUI\sentinel.txt') 'preserve DialogueUI'
    Write-Fixture (Join-Path $addOns 'OtherAddon\sentinel.txt') 'preserve other addon'
    $wtf = Join-Path $fixtureRoot 'game\WTF\Account\SavedVariables\NerdWow.lua'
    Write-Fixture $wtf 'preserve saved data'
    $sourceSnapshot = Snapshot $source
    $neighborSnapshot = Snapshot (Join-Path $addOns 'DialogueUI')
    $otherSnapshot = Snapshot (Join-Path $addOns 'OtherAddon')
    $wtfHash = (Get-FileHash -LiteralPath $wtf).Hash

    & $deploy -SourcePath $source -AddOnsPath $addOns -WhatIf
    & $deploy -AddOnsPath $addOns -WhatIf
    Assert (-not (Test-Path -LiteralPath $destination)) 'WhatIf criou o destino'
    $passed++
    $first = & $deploy -SourcePath $source -AddOnsPath $addOns
    Assert ($first.Created.Count -eq $runtimeCount) 'Primeira cópia diverge do manifesto'
    Assert (@(Get-ChildItem -LiteralPath $destination -File -Recurse -Force).Count -eq $runtimeCount) 'Arquivos extras implantados'
    Assert (-not (Test-Path -LiteralPath (Join-Path $destination 'Tests'))) 'Tests foi implantado'
    Assert (-not (Test-Path -LiteralPath (Join-Path $destination '.git'))) 'Git foi implantado'
    foreach ($relative in $first.Created) {
        Assert ((Get-FileHash -LiteralPath (Join-Path $source $relative)).Hash -eq
            (Get-FileHash -LiteralPath (Join-Path $destination $relative)).Hash) "Cópia divergente: $relative"
    }
    $passed++
    $repeat = & $deploy -SourcePath $source -AddOnsPath $addOns
    Assert ($repeat.Created.Count -eq 0 -and $repeat.Updated.Count -eq 0 -and
        $repeat.Removed.Count -eq 0 -and $repeat.Unchanged.Count -eq $runtimeCount) 'Repetição não é idempotente'
    $passed++

    Write-Fixture (Join-Path $destination 'Bootstrap.lua') 'old runtime'
    Write-Fixture (Join-Path $destination 'Legacy\obsolete.lua') 'obsolete'
    Write-Fixture (Join-Path $destination 'Tests\must-remove.lua') 'obsolete test'
    Write-Fixture (Join-Path $destination '.git\must-remove.txt') 'obsolete metadata'
    $beforeWhatIf = Snapshot $destination
    & $deploy -SourcePath $source -AddOnsPath $addOns -WhatIf
    Assert ((Snapshot $destination) -eq $beforeWhatIf) 'WhatIf alterou um destino existente'
    $passed++
    $update = & $deploy -SourcePath $source -AddOnsPath $addOns
    Assert ($update.Updated.Count -eq 1 -and $update.Updated[0] -eq 'Bootstrap.lua') 'Atualização incorreta'
    Assert ($update.Removed.Count -eq 6) 'Arquivos e pastas excedentes não removidos'
    Assert (@(Get-ChildItem -LiteralPath $destination -File -Recurse -Force).Count -eq $runtimeCount) 'Espelho incompleto'
    Assert ((Snapshot $source) -eq $sourceSnapshot) 'Origem modificada'
    $passed++

    # Corrigir conflitos de tipo sem apagar nenhum caminho externo ao destino.
    $integration = Join-Path $destination 'Integration'
    $integrationFiles = @(Get-ChildItem -LiteralPath $integration -File)
    foreach ($file in $integrationFiles) { Remove-Item -LiteralPath $file.FullName }
    Remove-Item -LiteralPath $integration
    Write-Fixture $integration 'file where directory belongs'
    $conflict = & $deploy -SourcePath $source -AddOnsPath $addOns
    Assert ($conflict.Created.Count -eq $integrationFiles.Count -and $conflict.Removed.Count -eq 1) 'Conflito arquivo para pasta não corrigido'
    $bootstrap = Join-Path $destination 'Bootstrap.lua'
    Remove-Item -LiteralPath $bootstrap
    Write-Fixture (Join-Path $bootstrap 'obsolete.txt') 'directory where file belongs'
    $conflict = & $deploy -SourcePath $source -AddOnsPath $addOns
    Assert ($conflict.Created.Count -eq 1 -and $conflict.Removed.Count -eq 2) 'Conflito pasta para arquivo não corrigido'
    $passed++

    # Um arquivo saiu do manifesto e da origem: deve sair do espelho.
    $localePath = Join-Path $source 'Locales\ptBR.lua'
    $locale = [IO.File]::ReadAllText($localePath)
    Write-Fixture (Join-Path $source 'NerdWow.toc') ($toc -replace '(?m)^Locales\\ptBR\.lua\r?\n', '')
    Remove-Item -LiteralPath $localePath
    $pruned = & $deploy -SourcePath $source -AddOnsPath $addOns
    Assert (-not (Test-Path -LiteralPath (Join-Path $destination 'Locales'))) 'Módulo antigo não foi removido'
    Assert ($pruned.Removed.Count -eq 2 -and $pruned.Updated.Count -eq 1) 'Relatório de remoção incorreto'
    Write-Fixture $localePath $locale
    Write-Fixture (Join-Path $source 'NerdWow.toc') $toc
    & $deploy -SourcePath $source -AddOnsPath $addOns | Out-Null
    $passed++

    $stableDestination = Snapshot $destination
    Expect-Failure { & $deploy -SourcePath (Join-Path $fixtureRoot 'missing\NerdWow') -AddOnsPath $addOns } 'Origem não encontrada'
    Expect-Failure { & $deploy -SourcePath $source -AddOnsPath (Join-Path $fixtureRoot 'missing\Interface\AddOns') } 'Interface\\AddOns não encontrada'
    Expect-Failure { & $deploy -SourcePath $destination -AddOnsPath $addOns } 'coincidir'
    Expect-Failure { & $deploy -SourcePath $source -AddOnsPath $fixtureRoot } 'Informe a pasta'

    Write-Fixture (Join-Path $source 'NerdWow.toc') ($toc + "`n..\outside.lua`n")
    Expect-Failure { & $deploy -SourcePath $source -AddOnsPath $addOns } 'Entrada de execução inválida'
    Write-Fixture (Join-Path $source 'NerdWow.toc') ($toc + "`nTests\Ignored.lua`n")
    Expect-Failure { & $deploy -SourcePath $source -AddOnsPath $addOns } 'Entrada de execução inválida'
    Write-Fixture (Join-Path $source 'NerdWow.toc') ($toc + "`nMissing.lua`n")
    Expect-Failure { & $deploy -SourcePath $source -AddOnsPath $addOns } 'Arquivo de execução não encontrado'
    Write-Fixture (Join-Path $source 'NerdWow.toc') $toc

    $tocPath = Join-Path $source 'NerdWow.toc'
    Remove-Item -LiteralPath $tocPath
    Expect-Failure { & $deploy -SourcePath $source -AddOnsPath $addOns } 'TOC não encontrado'
    Write-Fixture $tocPath $toc

    $linkedAddOns = Join-Path $fixtureRoot 'linked\Interface\AddOns'
    New-Item -ItemType Directory -Path $linkedAddOns -Force | Out-Null
    New-TestJunction (Join-Path $linkedAddOns 'NerdWow') $source
    Expect-Failure { & $deploy -SourcePath $source -AddOnsPath $linkedAddOns } 'junção ou link simbólico'
    $sourceAlias = Join-Path $fixtureRoot 'source-alias\NerdWow'
    New-Item -ItemType Directory -Path (Split-Path -Parent $sourceAlias) -Force | Out-Null
    New-TestJunction $sourceAlias $source
    Expect-Failure { & $deploy -SourcePath $sourceAlias -AddOnsPath $addOns } 'junção ou link simbólico'
    New-TestJunction (Join-Path $destination 'linked-neighbor') (Join-Path $addOns 'DialogueUI')
    Expect-Failure { & $deploy -SourcePath $source -AddOnsPath $addOns } 'junção ou link simbólico'
    [IO.Directory]::Delete((Join-Path $destination 'linked-neighbor'))
    $links.Remove((Join-Path $destination 'linked-neighbor')) | Out-Null
    $alias = Join-Path $fixtureRoot 'alias'
    New-TestJunction $alias (Join-Path $fixtureRoot 'game')
    Expect-Failure { & $deploy -SourcePath $source -AddOnsPath (Join-Path $alias 'Interface\AddOns') } 'junção ou link simbólico'

    Assert ((Snapshot $destination) -eq $stableDestination) 'Uma recusa modificou o destino'
    Assert ((Snapshot $source) -eq $sourceSnapshot) 'Origem alterada pela implantação'
    Assert ((Snapshot (Join-Path $addOns 'DialogueUI')) -eq $neighborSnapshot) 'DialogueUI alterado'
    Assert ((Snapshot (Join-Path $addOns 'OtherAddon')) -eq $otherSnapshot) 'Outro addon alterado'
    Assert ((Get-FileHash -LiteralPath $wtf).Hash -eq $wtfHash) 'SavedVariables alterada'
    $passed++
    Write-Output "$passed cenários de implantação aprovados; origem, vizinhos e SavedVariables preservados nas fixtures."
} finally {
    # Remover links sem seguir seus alvos antes de limpar a fixture isolada.
    foreach ($link in $links) {
        if (Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue) { [IO.Directory]::Delete($link) }
    }
    $absoluteFixture = [IO.Path]::GetFullPath($fixtureRoot)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $absoluteFixture.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $absoluteFixture) -notmatch '^NerdWow-deploy-tests-[a-f0-9]{32}$') {
        throw 'Limpeza fora da fixture recusada'
    }
    if (Test-Path -LiteralPath $absoluteFixture) { Remove-Item -LiteralPath $absoluteFixture -Recurse -Force }
}
