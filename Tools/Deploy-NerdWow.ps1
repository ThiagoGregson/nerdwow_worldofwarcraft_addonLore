[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$SourcePath,
    [string]$AddOnsPath = 'E:\Jogos\World of Warcraft\_retail_\Interface\AddOns'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-AbsolutePath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Assert-NoLink([string]$Path) {
    # Verifica cada ancestral existente, inclusive links pendentes.
    $current = $Path
    while ($current) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Implantação recusada: junção ou link simbólico em '$current'."
        }
        $current = Split-Path -Parent $current
    }
}

function Assert-WithinDestination([string]$Path) {
    $absolute = Get-AbsolutePath $Path
    if (-not $absolute.StartsWith($destination + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Operação fora da pasta NerdWow recusada: '$absolute'."
    }
    Assert-NoLink $absolute
}

function Get-SafeTree([string]$Root) {
    foreach ($item in Get-ChildItem -LiteralPath $Root -Force) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Implantação recusada: junção ou link simbólico em '$($item.FullName)'."
        }
        $item
        if ($item.PSIsContainer) { Get-SafeTree $item.FullName }
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        $SourcePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'NerdWow'
    }
    $source = Get-AbsolutePath $SourcePath
    $addOns = Get-AbsolutePath $AddOnsPath
    $destination = Get-AbsolutePath (Join-Path $addOns 'NerdWow')
    if ((Split-Path -Leaf $source) -ine 'NerdWow') {
        throw 'A pasta de origem deve se chamar NerdWow.'
    }
    if ((Split-Path -Leaf $addOns) -ine 'AddOns' -or
        (Split-Path -Leaf (Split-Path -Parent $addOns)) -ine 'Interface') {
        throw 'Informe a pasta Interface\AddOns como destino base.'
    }
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Origem não encontrada: '$source'."
    }
    if (-not (Test-Path -LiteralPath $addOns -PathType Container)) {
        throw "Pasta Interface\AddOns não encontrada: '$addOns'."
    }
    Assert-NoLink $source
    Assert-NoLink $destination
    if ($source -ieq $destination -or
        $source.StartsWith($destination + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $destination.StartsWith($source + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Origem e destino não podem coincidir nem estar contidos um no outro.'
    }
    $destinationItem = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
    if ($destinationItem -and -not $destinationItem.PSIsContainer) {
        throw "O destino NerdWow não é uma pasta: '$destination'."
    }

    # O TOC é o manifesto canônico. Nesta entrega seus recursos são somente Lua.
    $tocPath = Join-Path $source 'NerdWow.toc'
    if (-not (Test-Path -LiteralPath $tocPath -PathType Leaf)) {
        throw "TOC não encontrado: '$tocPath'."
    }
    Assert-NoLink $tocPath
    $manifest = @{ 'NerdWow.toc' = $tocPath }
    foreach ($line in [IO.File]::ReadAllLines($tocPath, [Text.Encoding]::UTF8)) {
        $relative = $line.Trim().Replace('/', '\')
        if (-not $relative -or $relative.StartsWith('#')) { continue }
        if ([IO.Path]::IsPathRooted($relative) -or $relative.Contains(':') -or
            $relative -match '(^|\\)\.{1,2}(\\|$)' -or
            $relative -match '(^|\\)(Tests|\.git)(\\|$)' -or
            [IO.Path]::GetExtension($relative) -ine '.lua') {
            throw "Entrada de execução inválida no TOC: '$relative'."
        }
        $filePath = Get-AbsolutePath (Join-Path $source $relative)
        if (-not $filePath.StartsWith($source + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Entrada do TOC fora da origem: '$relative'."
        }
        Assert-NoLink $filePath
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            throw "Arquivo de execução não encontrado: '$filePath'."
        }
        if ($manifest.ContainsKey($relative)) { throw "Entrada duplicada no TOC: '$relative'." }
        $manifest[$relative] = $filePath
    }
    if ($manifest.Count -lt 2) { throw 'O TOC não lista arquivos de execução.' }

    $existing = @()
    if ($destinationItem) { $existing = @(Get-SafeTree $destination) }
    $directories = @{}
    foreach ($relative in $manifest.Keys) {
        $parent = Split-Path -Parent $relative
        while ($parent) {
            $directories[$parent] = $true
            $parent = Split-Path -Parent $parent
        }
    }
    $created = @(); $updated = @(); $unchanged = @(); $removed = @(); $createdDirectories = @()
    foreach ($relative in @($manifest.Keys | Sort-Object)) {
        $target = Join-Path $destination $relative
        Assert-WithinDestination $target
        $item = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        if (-not $item -or $item.PSIsContainer) { $created += $relative }
        elseif ((Get-FileHash -LiteralPath $manifest[$relative] -Algorithm SHA256).Hash -ne
                (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash) { $updated += $relative }
        else { $unchanged += $relative }
    }
    # Arquivos que precisam virar diretórios também são excedentes.
    $obsolete = @($existing | Where-Object {
        $relative = $_.FullName.Substring($destination.Length + 1)
        if ($_.PSIsContainer) { -not $directories.ContainsKey($relative) }
        else { -not $manifest.ContainsKey($relative) }
    } | Sort-Object { $_.FullName.Length } -Descending)

    if (-not $PSCmdlet.ShouldProcess($destination, 'Espelhar somente os arquivos de execução de NerdWow')) { return }

    # Nenhuma gravação ocorre antes da validação de todos os caminhos e entradas.
    foreach ($item in $obsolete) {
        Assert-WithinDestination $item.FullName
        if ($item.PSIsContainer -and @(Get-ChildItem -LiteralPath $item.FullName -Force).Count) {
            throw "Pasta excedente não está vazia; implantação interrompida: '$($item.FullName)'."
        }
        Remove-Item -LiteralPath $item.FullName -Force
        $relative = $item.FullName.Substring($destination.Length + 1)
        $removed += $relative
        Write-Host "Removido: $relative"
    }
    foreach ($relative in @('') + @($directories.Keys | Sort-Object Length)) {
        $path = $destination
        if ($relative) { $path = Join-Path $destination $relative; Assert-WithinDestination $path }
        else { Assert-NoLink $destination }
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path | Out-Null
            $createdDirectories += $path
            Write-Host "Pasta criada: $path"
        }
    }
    foreach ($relative in $created + $updated) {
        $target = Join-Path $destination $relative
        Assert-WithinDestination $target
        Assert-NoLink $manifest[$relative]
        Copy-Item -LiteralPath $manifest[$relative] -Destination $target -Force
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $manifest[$relative] -Algorithm SHA256).Hash) {
            throw "Conteúdo copiado diverge da origem: '$relative'."
        }
        if ($relative -in $created) { Write-Host "Criado: $relative" }
        else { Write-Host "Atualizado: $relative" }
    }
    Write-Host ('Implantação concluída. Arquivos criados: {0}; atualizados: {1}; inalterados: {2}; itens removidos: {3}; pastas criadas: {4}.' -f
        $created.Count, $updated.Count, $unchanged.Count, $removed.Count, $createdDirectories.Count)
    Write-Host 'Alterações Lua valem após /reload. TOC novo ou alterado exige reiniciar o jogo.'
    if (Get-Process -Name Wow,WowT,WowB -ErrorAction SilentlyContinue) {
        Write-Warning 'World of Warcraft está aberto. Reinicie o jogo para reconhecer o TOC e a entrada do menu de addons.'
    }
    [pscustomobject]@{ Destination = $destination; Created = $created; Updated = $updated
        Removed = $removed; Unchanged = $unchanged; CreatedDirectories = $createdDirectories }
} catch {
    throw "Falha na implantação de NerdWow: $($_.Exception.Message)"
}
