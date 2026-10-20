# Third-party components

| Component | Location | Origin | License |
|---|---|---|---|
| Recoil motor controller firmware | `Recoil-Motor-Controller-BESC/` | https://github.com/T-K-233/Recoil-Motor-Controller-BESC (commit `3571ab6`), with local changes listed in `Recoil-Motor-Controller-BESC/LOCAL_CHANGES.md` | MIT (`Recoil-Motor-Controller-BESC/LICENSE`) |
| STM32G4 HAL driver | `Recoil-Motor-Controller-BESC/.../Drivers/STM32G4xx_HAL_Driver/` | STMicroelectronics | see `Drivers/STM32G4xx_HAL_Driver/LICENSE.txt` |
| CMSIS | `Recoil-Motor-Controller-BESC/.../Drivers/CMSIS/` | Arm / STMicroelectronics | see `Drivers/CMSIS/LICENSE.txt` |
| three.js 0.160 | `website/vendor/three/` | https://threejs.org | MIT |
| Chart.js 4.4.1 | `website/vendor/chart.umd.js` | https://www.chartjs.org | MIT |
| PYNQ-Z2 board files | `pynq-can/vivado/board_files/pynq-z2/` | TUL / Xilinx board store | as distributed by the board vendor |
| Actuator 3D parts (STL) | `hardware/actuator_cad_5010_cycloidal_stl.zip`, `website/models/` | "5010 Cycloidal Gear Actuator" printable design | check the original publisher's license before redistribution |

Reference only (not included): Berkeley Humanoid Lite, https://github.com/HybridRobotics/berkeley-humanoid-lite
(commit `984741a`) — the Recoil host protocol and motor configuration were cross-checked against it.
