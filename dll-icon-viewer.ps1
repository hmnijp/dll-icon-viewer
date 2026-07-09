Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class NativeIcon {
    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    public static extern uint ExtractIconEx(string szFileName, int nIconIndex, out IntPtr phiconLarge, out IntPtr phiconSmall, uint nIcons);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(IntPtr hIcon);

    public static int GetIconCount(string filePath) {
        IntPtr large, small;
        uint count = ExtractIconEx(filePath, -1, out large, out small, 0);
        return (int)count;
    }

    public static IntPtr ExtractSmallIcon(string filePath, int index) {
        IntPtr large, small;
        uint ret = ExtractIconEx(filePath, index, out large, out small, 1);
        if (ret == 0) return IntPtr.Zero;
        if (small != IntPtr.Zero) { DestroyIcon(large); return small; }
        return large;
    }

    public static IntPtr ExtractLargeIcon(string filePath, int index) {
        IntPtr large, small;
        uint ret = ExtractIconEx(filePath, index, out large, out small, 1);
        if (ret == 0) return IntPtr.Zero;
        if (large != IntPtr.Zero) { DestroyIcon(small); return large; }
        return small;
    }

    public static int[] GetIcoSizes(string filePath) {
        byte[] data = System.IO.File.ReadAllBytes(filePath);
        if (data.Length < 6 || data[0] != 0 || data[1] != 0 || data[2] != 1) return new int[0];
        int count = data[4] | (data[5] << 8);
        if (count <= 0 || count > 100) return new int[0];
        int[] sizes = new int[count];
        for (int i = 0; i < count; i++) {
            int idx = 6 + i * 16;
            if (idx + 2 > data.Length) break;
            int w = data[idx];
            if (w == 0) w = 256;
            int h = data[idx + 1];
            if (h == 0) h = 256;
            sizes[i] = Math.Max(w, h);
        }
        return sizes;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Auto, EntryPoint = "ExtractIconEx")]
    public static extern uint ExtractIconExBatch(string szFileName, int nIconIndex, [Out] IntPtr[] phiconLarge, [Out] IntPtr[] phiconSmall, uint nIcons);

    public static int ExtractIconsLarge(string filePath, int startIndex, IntPtr[] icons, int count) {
        IntPtr[] small = new IntPtr[count];
        uint ret = ExtractIconExBatch(filePath, startIndex, icons, small, (uint)count);
        int extracted = (int)ret;
        if (extracted < 0) extracted = 0;
        if (extracted > count) extracted = count;
        for (int i = 0; i < extracted; i++) {
            if (small[i] != IntPtr.Zero) DestroyIcon(small[i]);
        }
        return extracted;
    }

    public static int ExtractIconsSmall(string filePath, int startIndex, IntPtr[] icons, int count) {
        IntPtr[] large = new IntPtr[count];
        uint ret = ExtractIconExBatch(filePath, startIndex, large, icons, (uint)count);
        int extracted = (int)ret;
        if (extracted < 0) extracted = 0;
        if (extracted > count) extracted = count;
        for (int i = 0; i < extracted; i++) {
            if (large[i] != IntPtr.Zero) DestroyIcon(large[i]);
        }
        return extracted;
    }

    public static void SavePngAsIco(string outputPath, byte[] pngBytes, int size) {
        byte w = size >= 256 ? (byte)0 : (byte)size;
        byte h = size >= 256 ? (byte)0 : (byte)size;
        using (var fs = new System.IO.FileStream(outputPath, System.IO.FileMode.Create)) {
            fs.WriteByte(0); fs.WriteByte(0);
            fs.WriteByte(1); fs.WriteByte(0);
            fs.WriteByte(1); fs.WriteByte(0);
            fs.WriteByte(w); fs.WriteByte(h);
            fs.WriteByte(0); fs.WriteByte(0);
            fs.WriteByte(1); fs.WriteByte(0);
            fs.WriteByte(32); fs.WriteByte(0);
            byte[] len = BitConverter.GetBytes(pngBytes.Length);
            fs.Write(len, 0, 4);
            int ofs = 6 + 16;
            byte[] off = BitConverter.GetBytes(ofs);
            fs.Write(off, 0, 4);
            fs.Write(pngBytes, 0, pngBytes.Length);
        }
    }
}
"@

$knownFiles = @(
    "%SystemRoot%\System32\shell32.dll"
    "%SystemRoot%\System32\imageres.dll"
    "%SystemRoot%\System32\ddores.dll"
    "%SystemRoot%\System32\accessibilitycpl.dll"
    "%SystemRoot%\System32\moricons.dll"
    "%SystemRoot%\System32\pifmgr.dll"
    "%SystemRoot%\System32\comctl32.dll"
    "%SystemRoot%\System32\setupapi.dll"
    "%SystemRoot%\System32\twinui.dll"
    "%SystemRoot%\System32\Windows.UI.Shell.dll"
    "%SystemRoot%\System32\pnpui.dll"
    "%SystemRoot%\System32\mstscax.dll"
    "%SystemRoot%\System32\mmcndmgr.dll"
    "%SystemRoot%\System32\compstui.dll"
    "%SystemRoot%\System32\wpdshext.dll"
)

$knownNames = @("shell32.dll", "imageres.dll", "ddores.dll", "accessibilitycpl.dll", "moricons.dll", "pifmgr.dll", "comctl32.dll", "setupapi.dll", "twinui.dll", "Windows.UI.Shell.dll", "pnpui.dll", "mstscax.dll", "mmcndmgr.dll", "compstui.dll", "wpdshext.dll")

$scaleNames = @("x1 (16x16)", "x2 (32x32)", "x4 (64x64)", "x8 (128x128)", "x16 (256x256)")
$scaleSizes = @(16, 32, 64, 128, 256)
$lblSizes  = @(7, 9, 10, 11, 12)

$form = New-Object System.Windows.Forms.Form
$form.Text = "DLL Icon Viewer"
$form.Size = New-Object System.Drawing.Size(1000, 700)
$form.MinimumSize = New-Object System.Drawing.Size(700, 400)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$global:appIconPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "dll-icon-viewer.ico")
try {
    $shell32 = [Environment]::ExpandEnvironmentVariables("%SystemRoot%\System32\shell32.dll")
    $hIcon96 = [NativeIcon]::ExtractLargeIcon($shell32, 96)
    if ($hIcon96 -ne [IntPtr]::Zero) {
        $tmpIcon = [System.Drawing.Icon]::FromHandle($hIcon96)
        $fs = New-Object System.IO.FileStream($global:appIconPath, [System.IO.FileMode]::Create)
        $tmpIcon.Save($fs)
        $fs.Close()
        $null = [NativeIcon]::DestroyIcon($hIcon96)
        $form.Icon = [System.Drawing.Icon]::new($global:appIconPath)
    }
} catch { }

$table = New-Object System.Windows.Forms.TableLayoutPanel
$table.Dock = "Fill"
$table.ColumnCount = 1
$table.RowCount = 3
$null = $table.RowStyles.Clear()
$null = $table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, [float]32)))
$null = $table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, [float]24)))
$null = $table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Fill)))
$table.Padding = New-Object System.Windows.Forms.Padding(0)

$topPanel = New-Object System.Windows.Forms.TableLayoutPanel
$topPanel.Dock = "Fill"
$topPanel.ColumnCount = 4
$topPanel.RowCount = 1
$topPanel.Padding = New-Object System.Windows.Forms.Padding(4, 3, 4, 3)
$null = $topPanel.ColumnStyles.Clear()
$null = $topPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, [float]100)))
$null = $topPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
$null = $topPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, [float]200)))
$null = $topPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, [float]140)))

$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.Dock = "Fill"
$txtPath.Text = [Environment]::ExpandEnvironmentVariables("%SystemRoot%\System32\shell32.dll")

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "Обзор..."
$btnBrowse.AutoSize = $true
$btnBrowse.FlatStyle = "System"
$btnBrowse.Margin = New-Object System.Windows.Forms.Padding(4, 0, 4, 0)
$btnBrowse.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "Файлы с иконками (*.dll;*.exe;*.icl;*.cpl;*.scr;*.ocx;*.ico;*.png;*.jpg;*.bmp)|*.dll;*.exe;*.icl;*.cpl;*.scr;*.ocx;*.ico;*.png;*.jpg;*.bmp|Все файлы (*.*)|*.*"
    $ofd.CheckFileExists = $true
    $ofd.InitialDirectory = $global:lastDir
    if ($ofd.ShowDialog() -eq "OK") {
        $txtPath.Text = $ofd.FileName
        $global:lastDir = [System.IO.Path]::GetDirectoryName($ofd.FileName)
        $global:currentFileName = [System.IO.Path]::GetFileName($ofd.FileName)
        Load-Icons $ofd.FileName
    }
})

$cmbKnown = New-Object System.Windows.Forms.ComboBox
$cmbKnown.DropDownStyle = "DropDownList"
$cmbKnown.Dock = "Fill"
$cmbKnown.Items.AddRange($knownNames)
$cmbKnown.SelectedIndex = 0
$cmbKnown.Add_SelectedIndexChanged({
    $selected = $knownFiles[$cmbKnown.SelectedIndex]
    $expanded = [Environment]::ExpandEnvironmentVariables($selected)
    $txtPath.Text = $expanded
    $global:lastDir = [System.IO.Path]::GetDirectoryName($expanded)
    Load-Icons $expanded
})

$cmbScale = New-Object System.Windows.Forms.ComboBox
$cmbScale.DropDownStyle = "DropDownList"
$cmbScale.Dock = "Fill"
$cmbScale.Items.AddRange($scaleNames)
$cmbScale.SelectedIndex = 1
$cmbScale.Add_SelectedIndexChanged({
    if ($global:cachedFilePath -eq $txtPath.Text -and $global:iconCache.Count -gt 0) {
        ReRender-FromCache
    } else {
        Load-Icons $txtPath.Text
    }
})

$topPanel.Controls.Add($txtPath, 0, 0)
$topPanel.Controls.Add($btnBrowse, 1, 0)
$topPanel.Controls.Add($cmbKnown, 2, 0)
$topPanel.Controls.Add($cmbScale, 3, 0)

$progressPanel = New-Object System.Windows.Forms.Panel
$progressPanel.Dock = "Fill"
$progressPanel.Visible = $false

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(6, 3)
$progressBar.Size = New-Object System.Drawing.Size(240, 18)
$progressBar.Anchor = "Left,Top"
$progressBar.Style = "Continuous"

$lblProgress = New-Object System.Windows.Forms.Label
$lblProgress.Location = New-Object System.Drawing.Point(252, 3)
$lblProgress.Size = New-Object System.Drawing.Size(200, 18)
$lblProgress.Anchor = "Left,Top"
$lblProgress.Text = "Загрузка..."

$progressPanel.Controls.AddRange(@($progressBar, $lblProgress))

$flowPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$flowPanel.Dock = "Fill"
$flowPanel.AutoScroll = $true
$flowPanel.WrapContents = $true
$flowPanel.FlowDirection = "LeftToRight"
$flowPanel.Padding = New-Object System.Windows.Forms.Padding(6)
$flowPanel.BackColor = [System.Drawing.Color]::White
$flowPanel.BorderStyle = "Fixed3D"

$table.Controls.Add($topPanel, 0, 0)
$table.Controls.Add($progressPanel, 0, 1)
$table.Controls.Add($flowPanel, 0, 2)

$form.Controls.Add($table)

$global:cancelLoad = $false
$global:lastDir = [System.IO.Path]::GetDirectoryName([Environment]::ExpandEnvironmentVariables("%SystemRoot%\System32\shell32.dll"))
$global:currentFileName = "shell32.dll"
$global:iconCache = @()
$global:cachedFilePath = $null

function Get-IcoBytes {
    param([System.Drawing.Bitmap]$bmp)
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $ms.Close()
    return $ms.ToArray()
}

function Scale-Bitmap {
    param([System.Drawing.Bitmap]$src, [int]$size)
    if ($src.Width -eq $size -and $src.Height -eq $size) { return $src }
    $result = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($result)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($src, 0, 0, $size, $size)
    $g.Dispose()
    if ($src.Width -ne $size -or $src.Height -ne $size) { $src.Dispose() }
    return $result
}

function Write-Timing {
    param([string]$label, [long]$ms)
    Write-Debug "$label`: $ms ms"
}

function Clear-FlowPanel {
    foreach ($ctrl in $flowPanel.Controls) {
        if ($ctrl -is [System.Windows.Forms.Panel]) {
            foreach ($child in $ctrl.Controls) {
                if ($child -is [System.Windows.Forms.PictureBox] -and $child.Image) {
                    $child.Image.Dispose()
                }
            }
        }
    }
    $flowPanel.Controls.Clear()
}

function ReRender-FromCache {
    $displaySize = $scaleSizes[$cmbScale.SelectedIndex]
    $flowPanel.Visible = $false
    Clear-FlowPanel
    $flowPanel.SuspendLayout()
    $swTotal = [System.Diagnostics.Stopwatch]::StartNew()
    $swScale = 0
    try {
        for ($i = 0; $i -lt $global:iconCache.Count; $i++) {
            $src = $global:iconCache[$i]
            if ($src.Width -ne $displaySize) {
                $swS = [System.Diagnostics.Stopwatch]::StartNew()
                $scaled = Scale-Bitmap ($src.Clone()) $displaySize
                $swScale += $swS.ElapsedMilliseconds
            } else {
                $scaled = $src.Clone()
            }
            Add-IconCell $scaled $i.ToString() $displaySize $global:currentFileName
        }
    } finally {
        $total = $swTotal.ElapsedMilliseconds
        Write-Timing "ReRender-FromCache (total)" $total
        Write-Timing "  scale" $swScale
        $lblProgress.Text = "Готово за ${total}ms"
        $flowPanel.ResumeLayout()
        $flowPanel.Visible = $true
    }
}

function Add-IconCell {
    param([System.Drawing.Bitmap]$bmp, [string]$labelText, [int]$displaySize, [string]$fileName)

    $cellW = $displaySize + 10
    $cellH = $displaySize + 18
    $scaleIdx = $cmbScale.SelectedIndex
    $lblSize = $lblSizes[$scaleIdx]

    $cellPanel = New-Object System.Windows.Forms.Panel
    $cellPanel.Size = New-Object System.Drawing.Size($cellW, $cellH)
    $cellPanel.Margin = New-Object System.Windows.Forms.Padding(2)

    $pb = New-Object System.Windows.Forms.PictureBox
    $pb.Size = New-Object System.Drawing.Size($displaySize, $displaySize)
    $pb.Location = New-Object System.Drawing.Point(5, 0)
    $pb.SizeMode = "Normal"
    $pb.Image = $bmp

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $labelText
    $lbl.TextAlign = "MiddleCenter"
    $lbl.Size = New-Object System.Drawing.Size($cellW, 16)
    $lbl.Location = New-Object System.Drawing.Point(0, $displaySize)
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", $lblSize)

    $cellPanel.Controls.Add($pb)
    $cellPanel.Controls.Add($lbl)

    $ctx = New-Object System.Windows.Forms.ContextMenuStrip

    $mSave = $ctx.Items.Add("Save PNG")
    $mSave.Tag = @{Bitmap = $bmp; Label = $labelText; FileName = $fileName}
    $mSave.Add_Click({
        $d = $this.Tag
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "PNG|*.png|BMP|*.bmp|ICO|*.ico"
        $sfd.FileName = "$($d.FileName)-$($d.Label).png"
        if ($sfd.ShowDialog() -eq "OK") {
            $ext = [System.IO.Path]::GetExtension($sfd.FileName).ToLower()
            if ($ext -eq ".ico") {
                $icoBytes = Get-IcoBytes $d.Bitmap
                [NativeIcon]::SavePngAsIco($sfd.FileName, $icoBytes, $d.Bitmap.Width)
            } else {
                $fmt = if ($ext -eq ".bmp") { [System.Drawing.Imaging.ImageFormat]::Bmp } else { [System.Drawing.Imaging.ImageFormat]::Png }
                $d.Bitmap.Save($sfd.FileName, $fmt)
            }
        }
    })

    $mCopyPng = $ctx.Items.Add("Copy PNG")
    $mCopyPng.Tag = $bmp
    $mCopyPng.Add_Click({
        [System.Windows.Forms.Clipboard]::SetImage($this.Tag)
    })

    $mBmp = $ctx.Items.Add("BMP")
    $mBmp.Tag = $bmp
    $mBmp.Add_Click({
        [System.Windows.Forms.Clipboard]::SetImage($this.Tag)
    })

    $mIco = $ctx.Items.Add("ICO")
    $mIco.Tag = @{Bitmap = $bmp; Label = $labelText; FileName = $fileName}
    $mIco.Add_Click({
        $d = $this.Tag
        $temp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "icon-$($d.FileName)-$($d.Label).ico")
        $icoBytes = Get-IcoBytes $d.Bitmap
        [NativeIcon]::SavePngAsIco($temp, $icoBytes, $d.Bitmap.Width)
        $files = New-Object System.Collections.Specialized.StringCollection
        $files.Add($temp)
        [System.Windows.Forms.Clipboard]::SetFileDropList($files)
    })

    $ctx.Items.Add("-")

    $mB64 = $ctx.Items.Add("base64")
    $mB64.Tag = $bmp
    $mB64.Add_Click({
        $bytes = Get-IcoBytes $this.Tag
        $b64 = [System.Convert]::ToBase64String($bytes)
        [System.Windows.Forms.Clipboard]::SetText("data:image/png;base64,$b64")
    })

    $mHtml = $ctx.Items.Add("HTML")
    $mHtml.Tag = $bmp
    $mHtml.Add_Click({
        $bytes = Get-IcoBytes $this.Tag
        $b64 = [System.Convert]::ToBase64String($bytes)
        [System.Windows.Forms.Clipboard]::SetText("<img src=""data:image/png;base64,$b64"" />")
    })

    $ctx.Items.Add("-")

    $mIdx = $ctx.Items.Add("""$labelText""")
    $mIdx.Tag = $labelText
    $mIdx.Add_Click({
        [System.Windows.Forms.Clipboard]::SetText($this.Tag)
    })

    $mFull = $ctx.Items.Add("""$fileName,$labelText""")
    $mFull.Tag = "$fileName,$labelText"
    $mFull.Add_Click({
        [System.Windows.Forms.Clipboard]::SetText($this.Tag)
    })

    $cellPanel.ContextMenuStrip = $ctx
    $flowPanel.Controls.Add($cellPanel)
}

function Load-DllIcons {
    param([string]$filePath)

    $scaleIdx = $cmbScale.SelectedIndex
    $displaySize = $scaleSizes[$scaleIdx]

    $global:totalTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $script:extractTime = 0
    $script:convertTime = 0
    $script:scaleTime = 0
    $script:uiTime = 0

    $progressPanel.Visible = $true
    $progressBar.Value = 0
    [System.Windows.Forms.Application]::DoEvents()

    try {
        # Cache hit: re-render from cache
        if ($global:cachedFilePath -eq $filePath -and $global:iconCache.Count -gt 0) {
            $count = $global:iconCache.Count
            $progressBar.Maximum = $count
            $flowPanel.SuspendLayout()
            $swUi = [System.Diagnostics.Stopwatch]::StartNew()
            for ($i = 0; $i -lt $count; $i++) {
                if ($global:cancelLoad) { break }
                $src = $global:iconCache[$i]
                if ($src.Width -ne $displaySize) {
                    $swS = [System.Diagnostics.Stopwatch]::StartNew()
                    $scaled = Scale-Bitmap ($src.Clone()) $displaySize
                    $script:scaleTime += $swS.ElapsedMilliseconds
                } else {
                    $scaled = $src.Clone()
                }
                Add-IconCell $scaled $i.ToString() $displaySize $global:currentFileName
                $progressBar.Value = $i + 1
                $lblProgress.Text = "$($i + 1) / $count"
                if ($i % 50 -eq 0) {
                    [System.Windows.Forms.Application]::DoEvents()
                }
            }
            $script:uiTime = $swUi.ElapsedMilliseconds
            $flowPanel.ResumeLayout()
            $total = $global:totalTimer.ElapsedMilliseconds
            Write-Timing "Cache re-render (total)" $total
            Write-Timing "  scale" $script:scaleTime
            Write-Timing "  ui" $script:uiTime
            $lblProgress.Text = "Готово за ${total}ms"
            return
        }

        # Cache miss: extract large (32x32) and cache
        $swCount = [System.Diagnostics.Stopwatch]::StartNew()
        $count = [NativeIcon]::GetIconCount($filePath)
        Write-Timing "GetIconCount" $swCount.ElapsedMilliseconds
        if ($count -le 0) {
            [System.Windows.Forms.MessageBox]::Show("Не удалось получить количество иконок из файла.", "Информация", "OK", "Information")
            $progressPanel.Visible = $false
            return
        }

        $global:currentFileName = [System.IO.Path]::GetFileName($filePath)
        $global:cachedFilePath = $filePath
        $global:iconCache = @()
        $progressBar.Maximum = $count

        $flowPanel.SuspendLayout()
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $extractBatch = 512
        $batchStart = 0

        while ($batchStart -lt $count) {
            if ($global:cancelLoad) { break }
            $remaining = $count - $batchStart
            $batchCount = [Math]::Min($extractBatch, $remaining)

            $swExtract = [System.Diagnostics.Stopwatch]::StartNew()
            $icons = New-Object IntPtr[] $batchCount
            $extracted = [NativeIcon]::ExtractIconsLarge($filePath, $batchStart, $icons, $batchCount)
            $script:extractTime += $swExtract.ElapsedMilliseconds

            for ($i = 0; $i -lt $extracted; $i++) {
                if ($global:cancelLoad) { break }
                $hIcon = $icons[$i]
                if ($hIcon -ne [IntPtr]::Zero) {
                    $swConv = [System.Diagnostics.Stopwatch]::StartNew()
                    $iconObj = [System.Drawing.Icon]::FromHandle($hIcon)
                    $bmp = $iconObj.ToBitmap()
                    $null = [NativeIcon]::DestroyIcon($hIcon)
                    $script:convertTime += $swConv.ElapsedMilliseconds

                    $global:iconCache += $bmp.Clone()

                    if ($displaySize -ne 32) {
                        $swScale = [System.Diagnostics.Stopwatch]::StartNew()
                        $bmp = Scale-Bitmap $bmp $displaySize
                        $script:scaleTime += $swScale.ElapsedMilliseconds
                    }

                    $swUi = [System.Diagnostics.Stopwatch]::StartNew()
                    Add-IconCell $bmp ($batchStart + $i).ToString() $displaySize $global:currentFileName
                    $script:uiTime += $swUi.ElapsedMilliseconds
                }
            }

            $batchStart += $extractBatch
            $progressBar.Value = [Math]::Min($batchStart, $count)
            $lblProgress.Text = "$([Math]::Min($batchStart, $count)) / $count"

            if ($stopwatch.ElapsedMilliseconds -gt 200) {
                [System.Windows.Forms.Application]::DoEvents()
                $stopwatch.Restart()
            }
        }

        $total = $global:totalTimer.ElapsedMilliseconds
        Write-Timing "Full load (total)" $total
        Write-Timing "  GetIconCount" $swCount.ElapsedMilliseconds
        Write-Timing "  ExtractIconEx" $script:extractTime
        Write-Timing "  Icon->Bitmap" $script:convertTime
        Write-Timing "  Scale" $script:scaleTime
        Write-Timing "  Add-IconCell" $script:uiTime
        $lblProgress.Text = "Готово за ${total}ms"
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Ошибка: $_", "Ошибка", "OK", "Error")
    } finally {
        $flowPanel.ResumeLayout()
    }
}

function Load-IcoFile {
    param([string]$filePath)

    $displaySize = $scaleSizes[$cmbScale.SelectedIndex]

    $progressPanel.Visible = $true
    [System.Windows.Forms.Application]::DoEvents()

    $global:totalTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $script:scaleTime = 0
    $script:uiTime = 0

    try {
        $swSizes = [System.Diagnostics.Stopwatch]::StartNew()
        $sizes = [NativeIcon]::GetIcoSizes($filePath)
        Write-Timing "GetIcoSizes" $swSizes.ElapsedMilliseconds
        if ($sizes.Length -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Не удалось прочитать иконки из файла.", "Информация", "OK", "Information")
            $progressPanel.Visible = $false
            return
        }

        $global:currentFileName = [System.IO.Path]::GetFileName($filePath)
        $progressBar.Maximum = $sizes.Length
        $progressBar.Value = 0

        $flowPanel.SuspendLayout()
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        for ($i = 0; $i -lt $sizes.Length; $i++) {
            if ($global:cancelLoad) { break }
            $nativeSize = $sizes[$i]
            $ico = [System.Drawing.Icon]::new($filePath, $nativeSize, $nativeSize)
            $bmp = $ico.ToBitmap()
            $ico.Dispose()

            if ($displaySize -ne $nativeSize) {
                $swS = [System.Diagnostics.Stopwatch]::StartNew()
                $bmp = Scale-Bitmap $bmp $displaySize
                $script:scaleTime += $swS.ElapsedMilliseconds
            }
            $swUi = [System.Diagnostics.Stopwatch]::StartNew()
            Add-IconCell $bmp "$nativeSize" $displaySize $global:currentFileName
            $script:uiTime += $swUi.ElapsedMilliseconds

            $progressBar.Value = $i + 1
            $lblProgress.Text = "{0} / {1}" -f ($i + 1), $sizes.Length

            if ($stopwatch.ElapsedMilliseconds -gt 200) {
                [System.Windows.Forms.Application]::DoEvents()
                $stopwatch.Restart()
            }
        }

        $total = $global:totalTimer.ElapsedMilliseconds
        Write-Timing "Ico load (total)" $total
        Write-Timing "  GetIcoSizes" $swSizes.ElapsedMilliseconds
        Write-Timing "  Scale" $script:scaleTime
        Write-Timing "  Add-IconCell" $script:uiTime
        $lblProgress.Text = "Готово за ${total}ms"
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Ошибка: $_", "Ошибка", "OK", "Error")
    } finally {
        $flowPanel.ResumeLayout()
    }
}

function Load-ImageFile {
    param([string]$filePath)

    $displaySize = $scaleSizes[$cmbScale.SelectedIndex]

    $progressPanel.Visible = $true
    [System.Windows.Forms.Application]::DoEvents()

    $totalTimer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $swLoad = [System.Diagnostics.Stopwatch]::StartNew()
        $img = [System.Drawing.Image]::FromFile($filePath)
        $bmp = $img -as [System.Drawing.Bitmap]
        $label = [System.IO.Path]::GetExtension($filePath).ToUpper().TrimStart(".")
        Write-Timing "Image.FromFile" $swLoad.ElapsedMilliseconds

        if ($bmp.Width -gt $displaySize -or $bmp.Height -gt $displaySize -or $bmp.Width -lt $displaySize) {
            $swS = [System.Diagnostics.Stopwatch]::StartNew()
            $bmp = Scale-Bitmap $bmp $displaySize
            Write-Timing "Scale" $swS.ElapsedMilliseconds
        }

        $global:currentFileName = [System.IO.Path]::GetFileName($filePath)
        $progressBar.Maximum = 1
        $progressBar.Value = 1
        $lblProgress.Text = "1 / 1"
        [System.Windows.Forms.Application]::DoEvents()

        $swUi = [System.Diagnostics.Stopwatch]::StartNew()
        $flowPanel.SuspendLayout()
        Add-IconCell $bmp $label $displaySize $global:currentFileName
        Write-Timing "Add-IconCell" $swUi.ElapsedMilliseconds
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Ошибка: $_", "Ошибка", "OK", "Error")
    } finally {
        $total = $totalTimer.ElapsedMilliseconds
        Write-Timing "Image load (total)" $total
        $lblProgress.Text = "Готово за ${total}ms"
        $flowPanel.ResumeLayout()
    }
}

function Load-Icons {
    param([string]$filePath)

    if (-not (Test-Path $filePath)) {
        [System.Windows.Forms.MessageBox]::Show("Файл не найден:`n$filePath", "Ошибка", "OK", "Exclamation")
        return
    }

    $global:cancelLoad = $true
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 50

    Clear-FlowPanel
    $flowPanel.Visible = $false
    $global:cancelLoad = $false

    if ($filePath -ne $global:cachedFilePath) {
        $global:iconCache = @()
        $global:cachedFilePath = $null
    }

    $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
    if ($ext -eq ".ico") {
        Load-IcoFile $filePath
    } elseif ($ext -in @(".png", ".jpg", ".jpeg", ".bmp", ".gif", ".tiff", ".wmf", ".emf")) {
        Load-ImageFile $filePath
    } else {
        Load-DllIcons $filePath
    }

    $progressPanel.Visible = $false
    $flowPanel.Visible = $true
    [System.Windows.Forms.Application]::DoEvents()
}

$form.Add_Shown({
    Load-Icons $txtPath.Text
})

[System.Windows.Forms.Application]::Run($form)
