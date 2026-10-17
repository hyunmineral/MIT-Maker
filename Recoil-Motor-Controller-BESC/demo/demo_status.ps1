# Read the demo firmware state over SWD (hotplug, CPU keeps running).
# Symbol addresses come from demo/recoil_demo_standalone.elf via arm-none-eabi-nm (the ELF must be the one flashed).
#   powershell -File demo_status.ps1 [-Elf recoil_openloop_demo.elf]
param([string]$Elf = 'recoil_demo_standalone.elf')
$PROG = 'C:\ST\STM32CubeIDE_2.2.0\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.cubeprogrammer.win32_2.2.500.202603051304\tools\bin\STM32_Programmer_CLI.exe'
$NM = 'C:\ST\STM32CubeIDE_2.2.0\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.gnu-tools-for-stm32.14.3.rel1.win32_1.0.100.202602081740\tools\bin\arm-none-eabi-nm.exe'
$ELF = Join-Path $PSScriptRoot $Elf
$sym = @{}
foreach ($l in & $NM $ELF) { $p = $l -split '\s+'; if ($p.Count -eq 3) { $sym[$p[2]] = [Convert]::ToUInt32($p[0], 16) } }

# offsets inside MotorController (computed with offsetof for this source tree)
$OFF = @{ mode = 16; error = 20; target = 92; pos = 96; iq = 192; vbus = 256; flux = 316 }

$lo = [Math]::Min($sym['demo_state'], $sym['controller']) -band 0xFFFFFFFC
$len = ($sym['controller'] + 0x150) - $lo
$out = & $PROG -c port=SWD mode=Hotplug -r32 ("0x{0:X8}" -f $lo) ("0x{0:X}" -f $len) 2>&1 | Out-String
$words = @{}
foreach ($m in [regex]::Matches($out, '0x([0-9A-F]{8})\s*:\s*((?:[0-9A-F]{8}[ \t]*)+)')) {
  $base = [Convert]::ToUInt32($m.Groups[1].Value, 16); $i = 0
  foreach ($w in ($m.Groups[2].Value.Trim() -split '\s+')) { $words[[uint32]($base + 4 * $i)] = [Convert]::ToUInt32($w, 16); $i++ }
}
function U8($a) { ($words[[uint32]($a -band 0xFFFFFFFC)] -shr (8 * ($a % 4))) -band 0xFF }
function U32($a) { $words[[uint32]$a] }
function F32($a) { [BitConverter]::ToSingle([BitConverter]::GetBytes([uint32](U32 $a)), 0) }
$C = $sym['controller']
$modes = @{0 = 'DISABLED (init not finished?)'; 1 = 'IDLE'; 2 = 'DAMPING'; 5 = 'CALIBRATION'; 0x13 = 'POSITION'; 0x21 = 'VALPHABETA_OVERRIDE (open loop)' }
$mode = (U32 ($C + $OFF.mode)) -band 0xFF
if ($sym.ContainsKey('i2c_scan_done')) {
  $found = @(); for ($k = 0; $k -lt (U32 $sym['i2c_scan_count']); $k++) { $found += ('0x{0:X2}' -f (U8 ($sym['i2c_scan_found'] + $k))) }
  "i2c scan    : done=0x{0:X8}  found=[{1}]  AS5600(0x36) read error=0x{2:X8}" -f (U32 $sym['i2c_scan_done']), ($found -join ','), (U32 $sym['i2c_scan_error'])
}
"demo_state  : {0}  (0 wait for button, 1 calibrated/idle, 2 sine running)" -f (U8 $sym['demo_state'])
"mode        : 0x{0:X2} {1}" -f $mode, $modes[[int]$mode]
"error       : 0x{0:X8}" -f (U32 ($C + $OFF.error))
"bus voltage : {0:N2} V" -f (F32 ($C + $OFF.vbus))
"position    : {0:N3} motor rad  (target {1:N3})" -f (F32 ($C + $OFF.pos)), (F32 ($C + $OFF.target))
"i_q         : {0:N3} A" -f (F32 ($C + $OFF.iq))
"flux_offset : {0:N4} rad (0 = not calibrated)" -f (F32 ($C + $OFF.flux))
