# A Study on Robot Actuator Control Using a Variational Quantum Circuit Policy

**A Study on Robot Actuator Control Using a Variational Quantum Circuit Policy (v2.2, measured results)**

---

**Research areas**: Robotics · Control engineering · Artificial intelligence · FPGA

**Date**: October 13, 2026 (v2.2, real-hardware open-loop drive added · v2.1 web visualization · v1.0: October 3, 2026)

**Equipment**: PYNQ-Z2 FPGA board (XC7Z020), B-G431B-ESC1 motor controller (Recoil firmware), MAD 5010 motor + 15:1 cycloidal reducer

> **Before reading this paper**
> - **Relation to v1.0**: The experimental results in v1.0 were "values that assumed the goals had been achieved." Editions from v2.0 onward (currently v2.2) contain **only results that were actually implemented and measured**.
> - **Scope of measurement**: Control performance was measured in computer simulation and on the real FPGA board, in an environment where only the motor controller was replaced by a software emulator. After the broken motor controller was replaced with a new board (2026-10-13), **we succeeded in driving the real actuator from the FPGA board over CAN**, but because there is no angle sensor (encoder), we performed only open-loop drive without measuring position. **Real-hardware closed-loop control and a real-hardware VQC comparison were therefore not carried out.**
> - **What "quantum" means**: The "quantum" in this study is not a real quantum computer; it is **the mathematics of a quantum circuit computed on an ordinary chip**.

---

## Abstract

To move a robot joint, a **control policy** must decide "how much force to apply right now" 1,000 times per second. In this study, instead of a neural network, we built a **policy that borrows the mathematical structure of a quantum circuit (VQC, 72 learned numbers)** and implemented, on a real board, a control system that computes it on an **FPGA chip**.

The architecture is split into two layers. A simple position controller (PD) inside the motor controller holds the joint stably, and the VQC only adds "how much extra push to give" (feed-forward torque).

**There are three results.**
1. **The VQC policy worked properly.** In simulation, its tracking error was about 6 times smaller (1.43 ± 0.07 mrad) than with the position controller alone (8.79 mrad).
2. **However, the VQC was not more efficient than a neural network.** A small neural network with 65 numbers reached 0.98 mrad, about 32% more accurate than the VQC. A large neural network with 4,673 numbers was no better than the small one. The research hypothesis that "a VQC does as well as a neural network with fewer numbers" is **rejected for this task**.
3. **The FPGA implementation succeeded.** We built a circuit that computes a 64-amplitude quantum state in 22.5 µs at 100 MHz, and on the real board it produced practically the same answers as the CPU computation (difference of 4×10⁻⁷ or less, at the level of floating-point rounding). The FPGA path, including CPU-side preparation, takes 29 µs, about 2.2 times faster than computing on the board's CPU (64.6 µs). In a 1 kHz loop with the motor-controller emulator running in the same program, the top 1% of period jitter was 4.1 µs with the FPGA policy, smaller than with the CPU policy (22.9 µs).

With the new motor controller, we also succeeded in driving the real actuator from the FPGA board over CAN (4,000 predefined sine commands, 0 missed replies). However, this was open-loop drive without position measurement because there is no angle sensor, and because the round-trip time of the USB CAN adapter (1.81 ms) is longer than the 1 kHz period, we could not put the VQC policy in the real-hardware loop. A real-hardware closed-loop comparison remains future work (Section 4.6).

**Keywords**: robot actuator, parameterized quantum circuit (VQC), residual control, FPGA, HLS, CAN

---

## 1. Introduction

### 1.1 Motivation

A humanoid robot has more than 12 joints, and for each joint it must decide "how much force to apply" 1,000 times per second. The component responsible for this decision is the **control policy**, and these days it is usually built as an **artificial neural network (MLP)**.

Neural networks have many numbers (parameters) to store. This led to the idea: "If we use the mathematical structure of a quantum circuit, could we do a similar job with far fewer numbers?" The reason is that n qubits represent a state with 2ⁿ numbers, while the tuning knobs (parameters) grow only in proportion to n.

### 1.2 Research questions

> **Question 1.** Can a quantum circuit (VQC) policy control a joint more accurately than **a neural network of similar size**, or reach the same accuracy with fewer numbers?
>
> **Question 2.** Can that computation be done on an FPGA **fast enough and consistently enough within a 1 kHz control period**?

### 1.3 Changes from v1.0

v1.0 used only one comparison neural network, with 4,801 numbers, and claimed a "66.7× reduction." But without comparing against a neural network with a similar number of parameters, there is no way to know whether that reduction is really due to the VQC (v1.0 itself noted this as a limitation). In v2.0, we **added a 65-number neural network as a control group** and compared all models with **the same inputs, the same training procedure, and 3 random seeds**.

---

## 2. Background

### 2.1 Robot joints and the control architecture

A joint consists of a BLDC motor, a 15:1 reducer, and an angle sensor (in this real-hardware setup the angle sensor is not yet installed, Section 4.6). The motor controller (B-G431B-ESC1) regulates current (FOC) 10,000 times per second and position 2,000 times per second. Position regulation follows the equation below.

`torque = kp × (target angle − current angle) − kd × current velocity + τ_ff`

The last term, **τ_ff (feed-forward torque)**, is a value sent by an external computer over CAN. The policy in this study computes exactly this τ_ff 1,000 times per second. With only the position regulator, the joint follows the target with a lag (because of inertia, friction, and damping), so τ_ff pushes ahead by that amount.

### 2.2 Qubits and the VQC

The state of 6 qubits is represented by 2⁶ = 64 complex numbers. The VQC is a circuit that repeats the following 4 times.
1. Convert the 6 joint-state quantities into angles and rotate each qubit with an RY gate (data re-uploading).
2. Apply RX, RY, and RZ gates in sequence with learned angles.
3. Connect neighboring qubits in a ring with CNOT gates.

At the end, the measurement expectation value of the first qubit, ⟨Z₀⟩ (−1 to +1), is read and converted by `τ_ff = 0.8 × tanh(2⟨Z₀⟩)`. The number of learned numbers is 6 qubits × 3 axes × 4 layers = **72**.

### 2.3 FPGA and HLS

An FPGA is a chip into which you build computation circuits directly. The Zynq chip on the PYNQ-Z2 contains both a CPU (PS) and an FPGA (PL). HLS is a tool that converts C code into an FPGA circuit. In this study, the same C code was used both for the CPU program and for the FPGA circuit.

---

## 3. Methods

### 3.1 Experimental setup

| Category | Details |
|---|---|
| Training | Trained with PyTorch on a PC (Windows 11) together with the joint model |
| Execution board | PYNQ-Z2 — 1 kHz control loop on the CPU, VQC computation on the FPGA |
| Motor controller | Control-performance experiments: **emulator** — implements the real firmware's communication protocol and position-control equation as-is / Real-hardware open-loop (Section 4.6): new B-G431B-ESC1 (no encoder, open-loop firmware) |
| Communication | The board's CAN controller (loopback mode), an in-program connection, or a USB CAN adapter (CANable 2.0, Section 4.6) |

### 3.2 Joint model and domain randomization

The joint model includes inertia, viscous friction, Coulomb friction, reducer efficiency, communication delay (0–2 ms), and the firmware's torque filter and limits. Because we could not measure the real values, we trained and evaluated **while varying them randomly over wide ranges** (a 4× range for inertia, an 8× range for friction).

### 3.3 Training method

1. **Behavior cloning (BC)**: First, train the policy to imitate the "ideal feed-forward" computed from a physics formula.
2. **Closed-loop fine-tuning (BPTT)**: Then, inside the joint model, let the policy actually control the joint for 0.6 seconds at a time and adjust the numbers in the direction that reduces tracking error.

### 3.4 Comparison baselines

| Policy | Learned numbers | Description |
|---|---|---|
| PD only | 0 | τ_ff = 0 |
| Model feed-forward | 0 | Computed from the nominal physics formula (baseline for when the model is known) |
| **VQC** | **72** | 6 qubits · 4 layers |
| Small neural network | 65 | Input 6 → hidden 8 → output 1 |
| Large neural network | 4,673 | Input 6 → 64 → 64 → 1 |

All learned policies use the same input transformation and the same output transformation, and were repeated with 3 seeds.

---

## 4. Results

### 4.1 Accuracy — VQC vs neural network

![Figure 1. VQC vs MLP vs baselines](figures/png/fig3-vqc-vs-mlp.png)

**Figure 1. Tracking error and parameter count by policy**

Averages over 256 simulations × 3 seconds. Learned policies show the mean ± standard deviation over 3 seeds.

| Policy | Learned numbers | Error (randomized conditions) | Error (nominal conditions) |
|---|---|---|---|
| PD only | 0 | 8.79 mrad | 8.53 mrad |
| Model feed-forward | 0 | 1.55 | 1.10 |
| **VQC** | **72** | **1.43 ± 0.07** | **1.09 ± 0.12** |
| Small neural network | 65 | 0.98 ± 0.01 | 0.53 ± 0.05 |
| Large neural network | 4,673 | 1.01 ± 0.01 | 0.61 ± 0.01 |

(1 mrad ≈ 0.057°)

**How to read this**
- **The VQC is useful.** Its tracking error is about 6 times smaller than with PD alone, and similar to the physics-model feed-forward.
- **A neural network of the same size is better.** The 65-number neural network's error is about 32% smaller than the VQC's (72 numbers).
- **The large neural network was unnecessary.** Since the 4,673-number network is no better than the 65-number one, a small model was sufficient for this task from the start. v1.0's claim that "the VQC reduced the number of parameters 66-fold" was an illusion that arose from comparing only against the large neural network.
- **It is weak on abrupt motions.** On the most aggressive trajectory, the maximum error of the VQC (seed 0) was about 19 mrad, more than twice that of the physics formula (8 mrad).

### 4.2 Lessons from the initial design

- **Having the VQC produce the entire torque by itself does not work well.** When we trained it to imitate the whole position controller, the VQC could not reproduce the part near the target that "reacts strongly to even a small error," and it explained only about 74% of the variation in the position controller's output (R² ≈ 0.74). We therefore left the position controller to the motor controller and changed the VQC to handle only the feed-forward (residual architecture).
- **Feeding its own output back as an input causes oscillation.** When we put the previous output into the input, the output fed back on itself and oscillated (torque change 0.029 → 0.0026 after removal).

### 4.3 FPGA implementation

![Figure 2. HLS optimization stages](figures/png/fig14-hls-optimization.png)

**Figure 2. Computation time at each HLS optimization stage**

Even with the same C code, the speed varied greatly depending on how it was converted into an FPGA circuit.

| Stage | What changed | Computation time |
|---|---|---|
| Initial | Converted as-is | 15,343 clocks (target speed not met) |
| Two intermediate stages | Unrolling arrays into registers, etc. | Around 12,000 clocks (target speed still not met, circuit got larger) |
| Stage 4 | Separated the read array from the write array | 2,643 clocks = 26.4 µs |
| **Final** | tanh·cos·sin computed by the CPU | **2,248 clocks = 22.5 µs** |

The key was stage 4. When computing one qubit, reading and writing the same array made the tool decide that "the next computation cannot start until the previous one finishes," so it processed only one at a time. Separating where it reads from where it writes allowed a new computation to start every clock.

**An unexpected problem**: The stage 4 circuit was perfect in simulation, but **on the real board it gave wrong answers for some inputs**.
- Narrowing it down, it was wrong only in the middle range of the tanh computation.
- Slowing the clock from 100 MHz to 50 and 25 MHz produced the same errors, so it was not a timing problem.
- The root cause has not yet been identified.

We therefore had the CPU compute functions such as tanh, cos, and sin (only 13 numbers, so this finishes quickly) and left only the heavy 64-amplitude computation to the FPGA. As a result, the circuit became smaller and faster (22.5 µs, multiplier usage 66% → 32%: HLS estimate, 32.7% measured after placement), and on the board it produced practically the same answers as the CPU (difference of 4×10⁻⁷ or less).

### 4.4 Is there enough time?

![Figure 3. Time usage within the 1 kHz (1 ms) period](figures/png/fig5-timing-budget.png)

**Figure 3. Time usage within the 1 kHz (1 ms) period**

| Item | Measured |
|---|---|
| VQC computation — FPGA (including CPU-side preparation, C) | 29.0 µs (top 1% also 29.8 µs) |
| VQC computation — CPU only (C program) | 64.6 µs |
| Difference between the two results | 4×10⁻⁷ or less (at the level of floating-point rounding) |
| Control-period jitter (FPGA policy, motor-controller emulator running in the same program) | median 1.2 µs, top 1% 4.1 µs, max 4.7 µs |
| CAN round trip (on-board loopback, two programs exchanging messages) | median 482 µs, 1.1% loss |

Using the board's built-in CAN path, we expect the real CAN round trip to be about 350–420 µs: the time for 2 messages plus board-side processing time (estimate). Adding the VQC computation still fits within 1 ms. The round trip with the real motor controller was measured only via the USB adapter, and at 1.81 ms it was longer than the 1 ms period (Section 4.6). There is not yet a measurement of the board's built-in CAN path.

### 4.5 Checking with the web simulator

So that anyone can check the research results directly, we built a website, **VQC Actuator Lab** (in English, in the `website/` folder of the project repository). On the site you can do the following.
- Rotate an actuator assembled from the project's actual 3D-printed part files, and take it apart or cut it open.
- Run, in the browser, a simulation in which the trained VQC and neural network control the joint 1,000 times per second.

We verified that the web computation matches the research code. Under the same conditions, the tracking errors agreed to the fourth decimal place (PD 6.0093, VQC 1.2159, neural network 0.8107 mrad).

![Figure 4. Browser simulator](figures/png/fig19-site-simulator.png)

**Figure 4. Browser simulator — PD + VQC on a heavy, high-friction joint with 2 ms delay**

In a head-to-head comparison of the four methods on the same 24 random joints, the results were PD only 6.85, physics formula 0.78, VQC 1.30, and neural network 1.04 mrad. Because the sample (24 joints, 1 sine type) is smaller than in Section 4.1, the absolute values and the rank of the physics formula differ, but the core ordering "PD only > VQC > same-size neural network" (by error) was the same.

### 4.6 Driving the real actuator (open-loop)

After replacing the broken motor controller with a new board (2026-10-13), we moved the real actuator for the first time. However, because there is no sensor (encoder) to measure the motor angle, **we could not run experiments that control while measuring position.** Instead, we drove it with an **open-loop method** in which the magnetic field inside the motor is slowly rotated to predefined angles and the rotor follows. For this, we created a new mode in the motor-controller firmware that operates without an encoder.

Commands were sent from the FPGA board (PYNQ-Z2) through a USB CAN adapter (CANable 2.0) to the motor controller. A ±0.3 rad, 0.25 Hz output-shaft sine command was sent 200 times per second for 20 seconds. The command was a predefined sine wave, not the VQC, and it was sent by the board's CPU, not by the FPGA circuit. All angles below are command values (not measured values).

| Item | Result |
|---|---|
| Commands sent / missed replies | 4,000 / 0 |
| Command round-trip time | median 1.81 ms, top 1% 1.97 ms, max 11.0 ms |
| Motor phase current | mean 0.80 A, max 1.37 A |
| Output shaft | Moved (confirmed visually) |

This result confirmed that **the real command path works** from the FPGA board → CAN → motor controller → motor. However, two limitations emerged. First, the round-trip time through the USB adapter (about 1.8 ms) is longer than the 1 kHz control period (1 ms). A 1 kHz experiment therefore requires the CAN path built into the FPGA board, but that path did not work this time. Second, because there is no encoder, the core metric of this study—"how well it follows the target angle"—could not be measured on real hardware.

---

## 5. Discussion

### 5.1 Why the VQC did not beat the neural network

What the policy had to learn in this task was a **smooth, simple function**, roughly "a force proportional to the reference velocity and acceleration + friction compensation." Such a function is easily represented by a neural network with just 8 hidden neurons. In contrast, the VQC's output is a combination of sines and cosines (a Fourier-series form), which can actually be a disadvantage when representing near-linear relationships or abrupt changes. In the end, the advantage of "fewer numbers" was meaningless in this task, because a neural network was also sufficient with 65 numbers.

### 5.2 This is not "quantum advantage"

A 6-qubit circuit can be emulated exactly on an ordinary chip by computing just 64 numbers. These results have nothing to do with quantum-mechanical effects, and the VQC is best understood as "a mathematical function of a particular form."

### 5.3 What we still gained

- **A control system that runs on a real board**: We confirmed that the 1 kHz loop and FPGA acceleration work on the real board (with the motor controller emulated), and that the CAN command path works all the way to the real motor controller (USB adapter, 200 Hz). The path for communicating with the real motor controller at 1 kHz does not work yet.
- **A fair comparison framework**: The VQC and neural networks can be compared directly with the same inputs, the same training, and the same evaluation.
- **FPGA design lessons**: Even with the same C code, the computation time differs by about 7 times (15,343 → 2,248 clocks) depending on how HLS converts it. And a circuit that passes simulation must still be verified on the board.

### 5.4 Limitations

1. **Real-hardware closed-loop control was not performed.** After replacing the motor controller, we succeeded in moving the real actuator open-loop (Section 4.6). But because there is no angle sensor, position could not be measured. All control performance is therefore based on simulation or the emulator environment.
2. **The joint model values are estimates.** They must be measured on the real joint and the policies retrained.
3. **The CAN path for 1 kHz was not measured.** The round-trip time on the real bus via the USB adapter (CANable) was a median of 1.81 ms, longer than the 1 kHz period. The board's built-in CAN path required for 1 kHz (PS CAN + SN65HVD230) did not work, so the latency, jitter, and loss of that path are still unknown.
4. **The root cause of the FPGA wrong-answer problem was not identified.** It was only worked around.
5. **The conditions were not broadened.** Experiments varying the number of qubits and layers were not done.

---

## 6. Conclusion

This study implemented, on a real board, a 1 kHz control system that accelerates a quantum circuit policy on an FPGA. The FPGA computation, at 22.5 µs (29 µs including CPU preparation, short of the original 10 µs target), is fast enough for the 1 kHz period and agreed with the CPU computation to within 4×10⁻⁷. In simulation, the VQC policy's tracking error was about 6 times smaller than with the position controller alone. In addition, with the new motor controller, we drove the real actuator open-loop from the FPGA board over CAN (4,000 commands, 0 missed replies). However, because there is no encoder, real-hardware closed-loop control and a real-hardware VQC comparison were not carried out, so all conclusions about control performance are based on simulation or the emulator environment.

On the other hand, in terms of accuracy, **a neural network of the same size was more accurate than the VQC.** The hypothesis that "a VQC does as well as a neural network with fewer numbers" is therefore **not supported** for this single-joint feed-forward task. v1.0's "66.7× reduction, 23.4% loss" were numbers that came from assumptions and an unfair comparison.

The next step is to install an angle sensor (AS5600 encoder), restore the board's built-in CAN path for 1 kHz (PS CAN + SN65HVD230), and then repeat the same comparison on the real joint. The motor-controller replacement and open-loop drive are done (Section 4.6), and the comparison framework and control system for that comparison are ready. The procedure and predicted values for the real-hardware tests are compiled in a separate scenario document (`actuator-vqc-control-report-scenario.md`). All numbers in that document are predictions. For example, on a chirp trajectory faster than the training range, the VQC error is predicted to grow to about 4 times that of the neural network.

---

## References

- Berkeley Humanoid Lite (HybridRobotics), Recoil Motor Controller (T-K-233)
- AMD/Xilinx, *Vitis HLS User Guide (UG1399)*, *Zynq-7000 TRM (UG585)*
- PYNQ Project, *PYNQ-Z2 v3.1 image*
- Pérez-Salinas et al., "Data re-uploading for a universal quantum classifier," *Quantum* 4, 226 (2020)
- Schuld et al., "Effect of data encoding on the expressive power of variational quantum machine learning models," *PRA* 103, 032430 (2021)

---

## Appendix A. Glossary

| Term | Meaning |
|---|---|
| Feed-forward (τ_ff) | Force added in advance, before an error occurs |
| Residual architecture | An architecture in which a learned policy only adds corrections on top of a basic controller |
| mrad | Milliradian, 1 mrad ≈ 0.057° |
| BC / BPTT | Behavior cloning / closed-loop training that computes gradients backward through time |
| Domain randomization | A method of training while randomly varying model values, to make the policy robust to differences from reality |
| HLS | A tool that converts C code into an FPGA circuit |
| II | How many clocks apart the pipeline starts a new computation (1 is best) |
| C/RTL co-simulation | Verification that compares the results of the C code and the converted circuit on the same inputs |
| Jitter | How irregular the period is |

## Appendix B. Equipment and raw results

| Item | Specification |
|---|---|
| FPGA board | PYNQ-Z2, XC7Z020 (LUT 53,200 / DSP 220) |
| Final FPGA circuit | 22.5 µs @ 100 MHz, LUT 15,404 (29.0 %), DSP 72 (32.7 %) |
| Motor / reducer | MAD 5010 110KV / 15:1 cycloidal |
| Motor controller | B-G431B-ESC1, Recoil 0x20250226 (the first board failed because a component overheated during soldering; replaced with a new board on 2026-10-13. No encoder → open-loop build) |
| Raw data | `docs/results/results.json`, `docs/results/logs/`, code: project repository `pynq-can/` |
