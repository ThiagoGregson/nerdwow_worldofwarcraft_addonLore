param(
    [string]$LuaDll = 'C:\Program Files\obs-studio\bin\64bit\lua51.dll'
)

$ErrorActionPreference = 'Stop'
$addonRoot = Split-Path -Parent $PSScriptRoot
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
    [void]$script.AppendLine('return assert(loadstring(sources["Tests/Run.lua"], "Tests/Run.lua"))(sources, toc)')
    $suite = [Text.Encoding]::UTF8.GetBytes($script.ToString())
    $result = [NerdWowLuaHost]::luaL_loadbuffer($state, $suite, [UIntPtr]::new([uint64]$suite.Length), 'NerdWow tests')
    if ($result -eq 0) { $result = [NerdWowLuaHost]::lua_pcall($state, 0, 1, 0) }
    $message = Get-LuaResult $state
    if ($result -ne 0) { throw $message }
    Write-Output $message
} finally {
    if ($state -ne [IntPtr]::Zero) { [NerdWowLuaHost]::lua_close($state) }
    [void][NerdWowLuaHost]::FreeLibrary($library)
}
