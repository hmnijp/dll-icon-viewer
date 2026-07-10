# build.ps1 — build dll-icon-viewer.exe from source

try {
    if (-not (Get-Command ps2exe -ErrorAction SilentlyContinue)) {
        Install-Module -Name ps2exe -Scope CurrentUser -Force
    }
    Import-Module ps2exe

    Add-Type -AssemblyName System.Drawing
    Add-Type @"
    using System; using System.Runtime.InteropServices;
    public class N {
        [DllImport("shell32.dll")] public static extern uint ExtractIconEx(string s, int i, out IntPtr l, out IntPtr s2, uint n);
        [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
    }
"@
    $h = [IntPtr]::Zero; $s = [IntPtr]::Zero
    $null = [N]::ExtractIconEx("$env:SystemRoot\System32\shell32.dll", 96, [ref]$h, [ref]$s, 1)
    $icoPath = Join-Path $PSScriptRoot "iconic___.ico"
    $fs = New-Object System.IO.FileStream($icoPath, [System.IO.FileMode]::Create)
    [System.Drawing.Icon]::FromHandle($h).Save($fs)
    $fs.Close()
    $null = [N]::DestroyIcon($h)

    Invoke-ps2exe -InputFile (Join-Path $PSScriptRoot "dll-icon-viewer.ps1") `
        -OutputFile (Join-Path $PSScriptRoot "dll-icon-viewer.exe") `
        -noConsole -lcid 1049 -icon $icoPath

    Remove-Item $icoPath

    Write-Host "Done: dll-icon-viewer.exe"
} catch {
    Write-Host "Error: $_"
}

Read-Host "Press Enter to exit"
