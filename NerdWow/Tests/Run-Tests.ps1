param(
    [string]$LuaDll = 'C:\Program Files\obs-studio\bin\64bit\lua51.dll',
    [string]$PreviewPath
)

$ErrorActionPreference = 'Stop'
$addonRoot = Split-Path -Parent $PSScriptRoot
# Verifica cmap Unicode nos TTF reais: a simulação de FontString não renderiza glifos.
function Read-U16([byte[]]$Bytes, [int]$Offset) {
    return [int]$Bytes[$Offset] * 256 + [int]$Bytes[$Offset + 1]
}
function Read-U32([byte[]]$Bytes, [int]$Offset) {
    return [uint64]$Bytes[$Offset] * 16777216 + [uint64]$Bytes[$Offset + 1] * 65536 +
        [uint64]$Bytes[$Offset + 2] * 256 + [uint64]$Bytes[$Offset + 3]
}
function Get-UnicodeGlyph([byte[]]$Bytes, [int]$CodePoint) {
    $cmap = $null
    for ($i = 0; $i -lt (Read-U16 $Bytes 4); $i++) {
        $record = 12 + $i * 16
        if ([Text.Encoding]::ASCII.GetString($Bytes, $record, 4) -eq 'cmap') {
            $cmap = [int](Read-U32 $Bytes ($record + 8))
        }
    }
    if ($null -eq $cmap) { return 0 }
    for ($i = 0; $i -lt (Read-U16 $Bytes ($cmap + 2)); $i++) {
        $record = $cmap + 4 + $i * 8
        $platform = Read-U16 $Bytes $record
        $encoding = Read-U16 $Bytes ($record + 2)
        if ($platform -ne 0 -and -not ($platform -eq 3 -and $encoding -in @(1,10))) { continue }
        $sub = $cmap + [int](Read-U32 $Bytes ($record + 4))
        $format = Read-U16 $Bytes $sub
        if ($format -eq 4) {
            $segments = (Read-U16 $Bytes ($sub + 6)) / 2
            $ends = $sub + 14; $starts = $ends + 2 * $segments + 2
            $deltas = $starts + 2 * $segments; $ranges = $deltas + 2 * $segments
            for ($j = 0; $j -lt $segments; $j++) {
                $first = Read-U16 $Bytes ($starts + 2 * $j); $last = Read-U16 $Bytes ($ends + 2 * $j)
                if ($CodePoint -lt $first -or $CodePoint -gt $last) { continue }
                $delta = Read-U16 $Bytes ($deltas + 2 * $j); $range = Read-U16 $Bytes ($ranges + 2 * $j)
                if ($range -eq 0) { $glyph = ($CodePoint + $delta) % 65536 }
                else {
                    $glyph = Read-U16 $Bytes ($ranges + 2 * $j + $range + 2 * ($CodePoint - $first))
                    if ($glyph -ne 0) { $glyph = ($glyph + $delta) % 65536 }
                }
                if ($glyph -gt 0) { return $glyph }
                break
            }
        } elseif ($format -eq 12) {
            for ($j = 0; $j -lt (Read-U32 $Bytes ($sub + 12)); $j++) {
                $group = $sub + 16 + 12 * $j
                $first = Read-U32 $Bytes $group; $last = Read-U32 $Bytes ($group + 4)
                if ($CodePoint -ge $first -and $CodePoint -le $last) {
                    $glyph = (Read-U32 $Bytes ($group + 8)) + $CodePoint - $first
                    if ($glyph -gt 0) { return $glyph }
                }
            }
        }
    }
    return 0
}
foreach ($name in @('Cinzel-Regular','Cinzel-Bold','EBGaramond-Regular','EBGaramond-Italic')) {
    $fontBytes = [IO.File]::ReadAllBytes((Join-Path $addonRoot ('Fonts\' + $name + '.ttf')))
    if ((Get-UnicodeGlyph $fontBytes 0xD7) -eq 0) { throw "Fonte sem U+00D7: $name" }
}
Write-Output 'Fontes: U+00D7 confirmado nos quatro TTF (cmap Unicode, glifo diferente de .notdef).'
if (-not (Test-Path -LiteralPath $LuaDll -PathType Leaf)) {
    throw 'Runtime não encontrado. Informe -LuaDll com uma DLL Lua 5.1 de 64 bits instalada.'
}
if (-not [Environment]::Is64BitProcess) {
    throw 'Execute com PowerShell de 64 bits e uma DLL Lua 5.1 de 64 bits.'
}

# Harness de desenvolvimento: o addon não depende desta DLL nem deste script.
if (-not ('NerdWowLuaHost' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NerdWowLuaHost {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr LoadLibraryW(string path);
    [DllImport("kernel32.dll")]
    public static extern bool FreeLibrary(IntPtr module);
    [DllImport("lua51.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern IntPtr luaL_newstate();
    [DllImport("lua51.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern void luaL_openlibs(IntPtr state);
    [DllImport("lua51.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern int luaL_loadbuffer(IntPtr state, byte[] buffer, UIntPtr size, string name);
    [DllImport("lua51.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern int lua_pcall(IntPtr state, int nargs, int nresults, int errorFunction);
    [DllImport("lua51.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern IntPtr lua_tolstring(IntPtr state, int index, out UIntPtr size);
    [DllImport("lua51.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern void lua_settop(IntPtr state, int index);
    [DllImport("lua51.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern void lua_close(IntPtr state);
}
'@
}

function Get-LuaString([string]$Value) {
    $equals = '='
    while ($Value.Contains(']' + $equals + ']')) { $equals += '=' }
    return '[' + $equals + '[' + $Value + ']' + $equals + ']'
}

function Get-LuaResult([IntPtr]$State) {
    $length = [UIntPtr]::Zero
    $pointer = [NerdWowLuaHost]::lua_tolstring($State, -1, [ref]$length)
    if ($pointer -eq [IntPtr]::Zero) { return '(sem mensagem Lua)' }
    $buffer = New-Object byte[] ([int]$length.ToUInt64())
    [Runtime.InteropServices.Marshal]::Copy($pointer, $buffer, 0, $buffer.Length)
    return [Text.Encoding]::UTF8.GetString($buffer)
}

$library = [NerdWowLuaHost]::LoadLibraryW((Resolve-Path -LiteralPath $LuaDll).Path)
if ($library -eq [IntPtr]::Zero) { throw 'Falha ao carregar a DLL Lua 5.1 informada.' }
$state = [IntPtr]::Zero
try {
    $state = [NerdWowLuaHost]::luaL_newstate()
    if ($state -eq [IntPtr]::Zero) { throw 'Falha ao criar o estado Lua.' }
    [NerdWowLuaHost]::luaL_openlibs($state)
    $script = New-Object Text.StringBuilder
    [void]$script.AppendLine('local sources = {}')
    $files = @(Get-ChildItem -LiteralPath $addonRoot -Filter '*.lua' -Recurse -File | Sort-Object FullName)
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($addonRoot.Length + 1).Replace('\', '/')
        $source = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
        $bytes = [Text.Encoding]::UTF8.GetBytes($source)
        $result = [NerdWowLuaHost]::luaL_loadbuffer($state, $bytes, [UIntPtr]::new([uint64]$bytes.Length), $relative)
        if ($result -ne 0) { throw ('Sintaxe: ' + (Get-LuaResult $state)) }
        [NerdWowLuaHost]::lua_settop($state, 0)
        [void]$script.AppendLine(('sources[ ' + (Get-LuaString $relative) + ' ] = ' + (Get-LuaString $source)))
    }
    Write-Output ('Sintaxe aprovada: {0} arquivos Lua.' -f $files.Count)
    $toc = [IO.File]::ReadAllText((Join-Path $addonRoot 'NerdWow.toc'), [Text.Encoding]::UTF8)
    [void]$script.AppendLine(('local toc = ' + (Get-LuaString $toc)))
    $previewFonts = if ($PreviewPath) { Get-LuaString ((Join-Path $addonRoot 'Fonts').Replace('\','/')) } else { 'nil' }
    [void]$script.AppendLine(('return assert(loadstring(sources["Tests/Run.lua"], "Tests/Run.lua"))(sources, toc, '+$previewFonts+')'))
    $suite = [Text.Encoding]::UTF8.GetBytes($script.ToString())
    $result = [NerdWowLuaHost]::luaL_loadbuffer($state, $suite, [UIntPtr]::new([uint64]$suite.Length), 'NerdWow tests')
    if ($result -eq 0) { $result = [NerdWowLuaHost]::lua_pcall($state, 0, 1, 0) }
    $message = Get-LuaResult $state
    if ($result -ne 0) { throw $message }
    if ($PreviewPath) {
        $marker="`n<!--NERDWOW_PREVIEW-->`n"
        $split=$message.IndexOf($marker,[StringComparison]::Ordinal)
        if ($split -lt 0) { throw 'Prévia não produzida.' }
        [IO.File]::WriteAllText([IO.Path]::GetFullPath($PreviewPath),$message.Substring($split+$marker.Length),[Text.UTF8Encoding]::new($false))
        $message=$message.Substring(0,$split)
    }
    Write-Output $message
} finally {
    if ($state -ne [IntPtr]::Zero) { [NerdWowLuaHost]::lua_close($state) }
    [void][NerdWowLuaHost]::FreeLibrary($library)
}
