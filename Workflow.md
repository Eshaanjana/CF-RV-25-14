# CF-RV-25-14 - Workflow

## Problem statement:

Add support to send and read the PC from instruction commit log (rtl.dump) and to test on coremark with gdb in simulation and FPGA.

## Team members :

- Eshaanjana S
- Tanuja Sree R

---

## Objective:

To enhance the Shakti C-Class core by capturing instruction commit data (PC, opcode, destination register/value, memory address/value) during simulation and FPGA execution. This data will be extracted into a commit log and validated using `gdb`. This enables real-time debug, trace logging, and verification.

---

## Phase 1 Workflow: Capturing PC from Write-Back Stage into BRAM

### 1. Environment Setup

- Install prerequisites:
  - Bluespec compiler (BSC)
  - Verilator
  - GDB with RISC-V support (`riscv64-unknown-elf-gdb`)
  - Shakti Docker container&#x20;
  - Make, Python3, Git
- Clone the Shakti C-Class repo:
  ```bash
  git clone https://gitlab.com/shaktiproject/cores/c-class.git
  ```

### 2. RTL Analysis

- Navigate to `src/stage5/`.
- Open `stage5.bsv` — this is the Write-Back stage.
- Identify signal sources for:
  - PC: `fuid.pc`
  - Instruction type: from `rx_commitlog`
  - Destination register: `fuid.rd`
  - Destination value: `baseout.rdvalue` or `memop.atomic_rd_data`

### 3. Modify RTL to Store PC

- Inside rule `rl_writeback_baseout` and/or `rl_writeback_memop`, capture `fuid.pc`.
- Add logic to write `fuid.pc` into a BRAM-like structure or FIFO buffer.
  - This can be done using a register file, RAM primitive, or queue.
  - Use a global counter to index entries.

### 4. Simulation with Verilator

- Build simulation setup using `bsc -sim ...`
- Create a testbench (`mkTb.bsv`) that instantiates the core and observes the output BRAM/register structure.
- Run CoreMark or a sample program (`coremark.elf`) through Verilator.

### 5. Output Verification

- Print or dump BRAM contents at the end of simulation.
- Create a small function to export `rg_pc_log` contents to a file (`rtl.dump`).

### 6. Debug using GDB

- Load ELF binary into GDB:
- Match PC values from simulation (`rtl.dump`) with GDB output for correctness.

---

