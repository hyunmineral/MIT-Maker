#!/usr/bin/env bash
# Build a Recoil firmware variant from source with arm-none-eabi-gcc (no make, no prebuilt objects).
# Compiles Core/Src, the STM32G4 HAL driver sources and the startup file with the same flags as the
# STM32CubeIDE "Release" configuration, then links with STM32G431CBUX_FLASH.ld.
#
#   bash build_variant.sh <out_name> [-DNAME=VALUE ...]
#   bash build_variant.sh recoil_normal                                   # closed-loop firmware (needs AS5600)
#   bash build_variant.sh recoil_first_boot -DFIRST_TIME_BOOTUP=1         # first flash of a virgin board
#   bash build_variant.sh recoil_demo_standalone -DDEMO_STANDALONE=1      # button demo (needs AS5600)
#   bash build_variant.sh recoil_openloop -DOPENLOOP_NO_ENCODER=1         # no encoder, CAN open loop
#   bash build_variant.sh recoil_openloop_demo -DOPENLOOP_NO_ENCODER=1 -DDEMO_STANDALONE=1
#
# Toolchain: set ARM_GCC_BIN to the folder containing arm-none-eabi-gcc (default: STM32CubeIDE 2.2.0 bundle).
# Output: <out_name>.elf / .map next to this script; objects in build/<out_name>/.
set -euo pipefail
ARM_GCC_BIN="${ARM_GCC_BIN:-/c/ST/STM32CubeIDE_2.2.0/STM32CubeIDE/plugins/com.st.stm32cube.ide.mcu.externaltools.gnu-tools-for-stm32.14.3.rel1.win32_1.0.100.202602081740/tools/bin}"
export PATH="$ARM_GCC_BIN:$PATH"
command -v arm-none-eabi-gcc >/dev/null || { echo "arm-none-eabi-gcc not found; set ARM_GCC_BIN" >&2; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJ="$HERE/../Recoil-Motor-Controller-B-G431B-ESC1"
NAME="${1:?usage: build_variant.sh <out_name> [-DNAME=VALUE ...]}"; shift
OBJ="$HERE/build/$NAME"
rm -rf "$OBJ"; mkdir -p "$OBJ"
cd "$PROJ"

ARCH=(-mcpu=cortex-m4 -mfpu=fpv4-sp-d16 -mfloat-abi=hard -mthumb --specs=nano.specs)
CFLAGS=("${ARCH[@]}" -std=gnu11 -DUSE_HAL_DRIVER -DSTM32G431xx
  -ICore/Inc -IDrivers/STM32G4xx_HAL_Driver/Inc -IDrivers/STM32G4xx_HAL_Driver/Inc/Legacy
  -IDrivers/CMSIS/Device/ST/STM32G4xx/Include -IDrivers/CMSIS/Include
  -Os -ffunction-sections -fdata-sections -Wall)

# link order = CubeIDE objects.list order (Core, startup, HAL), so the image matches the IDE build
objs=()
cc() { local o="$OBJ/$(basename "$1" .c).o"; arm-none-eabi-gcc -c "$1" "${CFLAGS[@]}" "${DEFS[@]}" -o "$o"; objs+=("$o"); }
DEFS=("$@")
for src in Core/Src/*.c; do cc "$src"; done
arm-none-eabi-gcc -c -x assembler-with-cpp "${ARCH[@]}" Core/Startup/startup_stm32g431cbux.s -o "$OBJ/startup_stm32g431cbux.o"
objs+=("$OBJ/startup_stm32g431cbux.o")
for src in Drivers/STM32G4xx_HAL_Driver/Src/*.c; do cc "$src"; done

arm-none-eabi-gcc -o "$HERE/$NAME.elf" "${objs[@]}" "${ARCH[@]}" -TSTM32G431CBUX_FLASH.ld --specs=nosys.specs \
  -Wl,--gc-sections -static -u _printf_float -Wl,--start-group -lc -lm -Wl,--end-group \
  -Wl,--no-warn-rwx-segments -Wl,-Map="$HERE/$NAME.map"
arm-none-eabi-size "$HERE/$NAME.elf"
