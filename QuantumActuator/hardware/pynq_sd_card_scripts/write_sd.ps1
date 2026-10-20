# Write the PYNQ-Z2 image directly to the SD card
# Safety: proceeds only if serial number, capacity, bus type and non-system/non-boot status all match

$ErrorActionPreference = 'Stop'

$IMG            = 'D:\robot\pynq-image\pynq_z2_v3.1.1.img'
$LOG            = 'D:\robot\pynq-image\write_sd.log'
$EXPECT_DISK    = 2
$EXPECT_SERIAL  = '121220160204'
$EXPECT_SIZE_GB = 29.13
$EXPECT_BUS     = 'USB'

function Log($m) {
    $line = "{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
    Write-Host $line
    Add-Content -Path $LOG -Value $line -Encoding UTF8
}

Set-Content -Path $LOG -Value "" -Encoding UTF8
Log "=== PYNQ-Z2 SD write started ==="

# --- 0. Administrator check ---
$pr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Log "FATAL: not running as administrator."
    exit 1
}
Log "Administrator rights confirmed"

# --- 1. Image check ---
if (-not (Test-Path $IMG)) { Log "FATAL: image not found: $IMG"; exit 1 }
$imgSize = (Get-Item $IMG).Length
Log ("Image: {0} ({1:N0} bytes / {2:N2} GB)" -f $IMG, $imgSize, ($imgSize/1GB))

# --- 2. Strict target-disk verification ---
$d = Get-Disk -Number $EXPECT_DISK -ErrorAction SilentlyContinue
if (-not $d) { Log "FATAL: disk $EXPECT_DISK not found"; exit 1 }

$sizeGB = [math]::Round($d.Size/1GB, 2)
Log "Target candidate: #$($d.Number) '$($d.FriendlyName)' SN=$($d.SerialNumber) ${sizeGB}GB $($d.BusType) Boot=$($d.IsBoot) System=$($d.IsSystem)"

$fail = @()
if ($d.SerialNumber -ne $EXPECT_SERIAL)      { $fail += "serial mismatch (expected $EXPECT_SERIAL, actual $($d.SerialNumber))" }
if ([math]::Abs($sizeGB - $EXPECT_SIZE_GB) -gt 0.5) { $fail += "capacity mismatch (expected ${EXPECT_SIZE_GB}GB, actual ${sizeGB}GB)" }
if ($d.BusType -ne $EXPECT_BUS)              { $fail += "bus type mismatch ($($d.BusType))" }
if ($d.IsBoot)                               { $fail += "this is the boot disk — never allowed" }
if ($d.IsSystem)                             { $fail += "this is the system disk — never allowed" }
if ($d.Size -lt $imgSize)                    { $fail += "card is smaller than the image" }

if ($fail.Count -gt 0) {
    Log "FATAL: safety verification failed — not writing"
    $fail | ForEach-Object { Log "   - $_" }
    exit 1
}
Log "Safety verification passed (serial/capacity/bus/non-system all match)"

# --- 3. Take the disk offline ---
Log "Taking the disk offline..."
try {
    Set-Disk -Number $EXPECT_DISK -IsReadOnly $false -ErrorAction SilentlyContinue
    Set-Disk -Number $EXPECT_DISK -IsOffline $true
    Start-Sleep -Seconds 2
    Log "Disk is offline"
} catch {
    Log "Warning: could not take the disk offline ($($_.Exception.Message)) — continuing"
}

# --- 4. Write ---
$CHUNK = 4MB
$path  = "\\.\PhysicalDrive$EXPECT_DISK"
Log "Writing: $path"

$fsIn = $null; $fsOut = $null
try {
    $fsIn  = [System.IO.File]::Open($IMG, 'Open', 'Read', 'Read')
    $fsOut = New-Object System.IO.FileStream($path, 'Open', 'Write', 'ReadWrite')

    $buf = New-Object byte[] $CHUNK
    $done = 0; $lastPct = -5
    $sw = [Diagnostics.Stopwatch]::StartNew()

    while ($true) {
        $n = $fsIn.Read($buf, 0, $CHUNK)
        if ($n -le 0) { break }
        if ($n % 512 -ne 0) { $n = [math]::Ceiling($n/512) * 512 }   # sector alignment
        $fsOut.Write($buf, 0, $n)
        $done += $n
        $pct = [math]::Floor($done * 100 / $imgSize)
        if ($pct -ge $lastPct + 5) {
            $lastPct = $pct
            $mbs = $done / 1MB / [math]::Max($sw.Elapsed.TotalSeconds, 0.01)
            Log ("  write {0,3}%  {1,6:N2} GB  {2,6:N0}s  {3,5:N1} MB/s" -f $pct, ($done/1GB), $sw.Elapsed.TotalSeconds, $mbs)
        }
    }
    $fsOut.Flush($true)
    Log ("Write complete: {0:N0} bytes, {1:N0} s" -f $done, $sw.Elapsed.TotalSeconds)
}
catch {
    Log "FATAL: write failed — $($_.Exception.Message)"
    if ($fsOut) { $fsOut.Dispose() }
    if ($fsIn)  { $fsIn.Dispose() }
    Set-Disk -Number $EXPECT_DISK -IsOffline $false -ErrorAction SilentlyContinue
    exit 1
}
finally {
    if ($fsOut) { $fsOut.Dispose() }
    if ($fsIn)  { $fsIn.Dispose() }
}

# --- 5. Verify (read back and compare with the image) ---
Log "Verifying (full comparison)..."
$ok = $true
try {
    $fsIn  = [System.IO.File]::Open($IMG, 'Open', 'Read', 'Read')
    $fsChk = New-Object System.IO.FileStream($path, 'Open', 'Read', 'ReadWrite')
    $b1 = New-Object byte[] $CHUNK
    $b2 = New-Object byte[] $CHUNK
    $done = 0; $lastPct = -5
    $sw = [Diagnostics.Stopwatch]::StartNew()

    while ($done -lt $imgSize) {
        $n1 = $fsIn.Read($b1, 0, $CHUNK)
        if ($n1 -le 0) { break }
        $need = $n1; if ($need % 512 -ne 0) { $need = [math]::Ceiling($need/512)*512 }
        $n2 = 0
        while ($n2 -lt $need) {
            $r = $fsChk.Read($b2, $n2, $need - $n2)
            if ($r -le 0) { break }
            $n2 += $r
        }
        for ($i = 0; $i -lt $n1; $i++) {
            if ($b1[$i] -ne $b2[$i]) {
                Log "FATAL: mismatch — offset $($done + $i)"
                $ok = $false; break
            }
        }
        if (-not $ok) { break }
        $done += $n1
        $pct = [math]::Floor($done * 100 / $imgSize)
        if ($pct -ge $lastPct + 10) {
            $lastPct = $pct
            Log ("  verify {0,3}%  {1,6:N2} GB  {2,6:N0}s" -f $pct, ($done/1GB), $sw.Elapsed.TotalSeconds)
        }
    }
    Log ("Verification finished: {0}" -f $(if ($ok) { "all bytes match — success" } else { "FAILED" }))
}
catch { Log "Error during verification: $($_.Exception.Message)"; $ok = $false }
finally {
    if ($fsChk) { $fsChk.Dispose() }
    if ($fsIn)  { $fsIn.Dispose() }
}

# --- 6. Bring the disk back online ---
Log "Bringing the disk back online..."
Set-Disk -Number $EXPECT_DISK -IsOffline $false -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

if ($ok) {
    Log "=== Done: SD card written successfully ==="
    Log "Next: power OFF -> insert SD -> JP4=SD -> power ON"
    exit 0
} else {
    Log "=== Failed: try again or use another card ==="
    exit 1
}
