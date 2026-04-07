# SGPIO-INTERFACE

# SGPIO Interface — Full Spec-Compliant Verilog RTL Implementation

A complete hardware implementation of the **Serial GPIO (SGPIO)**
interface based on **SFF-8485 Revision 0.7**, designed and verified.

---

## About

SGPIO (Serial General Purpose Input Output) is a 4-wire serial
protocol used in SAS/SATA storage systems. It runs alongside the
main data interface on the same connector and handles two things:

- Controlling drive bay LED indicators (Activity, Locate, Error)
- Reading back drive presence status from the backplane

This implementation covers the full specification — not just the
basic protocol layer but also hardware blink generators, all LED
control modes, the activity auto-flash state machine with all four
timing controls, and correct bus idle vs tristate behaviour.

---

## Repository Structure
SGPIO-INTERFACE/
│
├── src/
│   └── sgpio_initiator.v        # RTL source - full spec implementation
│
├── tb/
│   └── tb_sgpio.v               # Testbench - 13 test cases
│
├── sim/
│   ├── run.do                   # ModelSim run script
│   └── sgpio_wave.vcd           # Simulation waveform dump
│
├── docs/
│   ├── SGPIO_Project_Report_v1.pdf   # Basic version report
│   └── SGPIO_Project_Report_v2.pdf   # Full spec version report
│
└── README.md

---

## What is Implemented

### Protocol Layer (SFF-8485 Chapter 7)
- SCLK generation with configurable half-period (HALF parameter)
- Frame structure: N×3 data bits + 1 end marker + 4 vendor bits
- SLOAD end-of-stream marker at correct position
- Data driven on rising SCLK edge, SDI sampled on falling SCLK edge
- Bus tristate on reset: SCLK=SLOAD=SDO=1 (spec section 7.2)
- Bus idle when disabled: SCLK=0, SLOAD=0 (not tristate — spec section 7.2)
- Vendor bits L0-L3 = 0000b in normal mode (spec section 8.3)

### Blink Generators A and B (SFF-8485 Table 16)
- Two independent hardware counters running continuously
- Configurable rate via bga_rate and bgb_rate inputs
- Code 0h = 1/8 second, Code 1h = 2/8 second ... Code Fh = 16/8 second
- Both generators feed into the OD bit selection logic

### Activity LED Modes — Table 25 (3-bit field per drive)
| Code | Mode |
|------|------|
| 000b | Always OFF |
| 001b | Always ON |
| 010b | Blink Generator A, ON first half |
| 011b | Blink Generator A, OFF first half |
| 100b | Auto-flash on EOF trigger |
| 101b | Auto-flash on SOF trigger |
| 110b | Blink Generator B, ON first half |
| 111b | Blink Generator B, OFF first half |

### Locate LED Modes — Table 26 (2-bit field per drive)
| Code | Mode |
|------|------|
| 00b | OFF (default) |
| 01b | ON |
| 10b | Blink Generator A, ON first |
| 11b | Blink Generator A, OFF first |

### Error LED Modes — Table 27 (3-bit field per drive)
| Code | Mode |
|------|------|
| 000b | OFF (default) |
| 001b | ON |
| 010b | Blink Generator A, ON first |
| 011b | Blink Generator A, OFF first |
| 110b | Blink Generator B, ON first |
| 111b | Blink Generator B, OFF first |

### Activity Auto-Flash State Machine (SFF-8485 Tables 17-20)
5-state machine per drive for activity modes 100b and 101b:
State 0  IDLE        -> LED OFF, waits for SOF or EOF trigger
State 1  STRETCH ON  -> LED ON,  holds for minimum ON time (Table 20)
State 2  MAX ON      -> LED ON,  counts to maximum ON time (Table 18)
re-trigger resets the counter
State 3  FORCE OFF   -> LED OFF, mandatory dark period (Table 17)
State 4  STRETCH OFF -> LED OFF, minimum OFF time (Table 19)
then back to State 0

---

## Module Interface
```verilog
module sgpio_initiator
  #(parameter N     = 4,        // number of drives (min 4 per spec)
    parameter HALF  = 250,      // SCLK half-period in sys_clk cycles
    parameter TBASE = 6250000)  // sys_clk cycles per 1/8 second
   (input  clk,
    input  rst_n,               // active-low async reset
    input  en,                  // 0=idle(SCLK=0), 1=run

    input  [3:0] bga_rate,      // blink gen A rate  (Table 16)
    input  [3:0] bgb_rate,      // blink gen B rate  (Table 16)
    input  [3:0] frc_off,       // force activity off (Table 17)
    input  [3:0] max_on,        // max activity on    (Table 18)
    input  [3:0] str_off,       // stretch act off    (Table 19)
    input  [3:0] str_on,        // stretch act on     (Table 20)

    input  [(N*8)-1:0] gpio_tx, // {act[2:0], loc[1:0], err[2:0]} per drive
    input  [N-1:0]     sof,     // start-of-frame trigger per drive
    input  [N-1:0]     eof,     // end-of-frame trigger per drive

    output [(N*3)-1:0] gpio_rx, // received drive status bits
    output             rx_rdy,  // pulses HIGH 1 cycle per frame

    output SCLK,
    output SLOAD,
    output SDO,
    input  SDI);
```

### gpio_tx Bit Packing

For each drive index i (0 = drive 0, 1 = drive 1, etc.):
gpio_tx[ i8 +: 3 ]  = error mode   (3 bits, Table 27)
gpio_tx[ i8+3 +: 2] = locate mode  (2 bits, Table 26)
gpio_tx[ i*8+5 +: 3] = activity mode(3 bits, Table 25)

Example — Drive 0 activity always on, locate on, error off:
```verilog
gpio_tx[7:0] = 8'b001_01_000;
//              act  loc err
```

---

## Design Parameters and Timing

| Parameter | Default | Meaning |
|-----------|---------|---------|
| N | 4 | Number of drives |
| HALF | 250 | SCLK half-period cycles |
| TBASE | 6250000 | Cycles per 1/8 second at 50 MHz |

At 50 MHz system clock with HALF=250:
SCLK period    = 250 x 2 x 20 ns = 10,000 ns = 100 kHz
SCLK HIGH time = 5000 ns  (spec min: 4400 ns)  PASS
SCLK LOW time  = 5000 ns  (spec min: 4700 ns)  PASS
Frame duration = 17 x 10 us = 170 us

---

## Timing Compliance — SFF-8485 Table 5

| Requirement | Spec Minimum | Achieved | Result |
|-------------|-------------|----------|--------|
| SCLK Period | 10 us | 10 us | PASS |
| SCLK HIGH Time | 4400 ns | 5000 ns | PASS |
| SCLK LOW Time | 4700 ns | 5000 ns | PASS |
| Data Setup (fall edge) | 200 ns | ~5000 ns | PASS |
| Data Hold (fall edge) | 4400 ns | ~5000 ns | PASS |

---

## Testbench — 13 Test Cases

| Test | What It Tests | Spec Reference |
|------|--------------|----------------|
| T1 | Bus idle: SCLK=0, SLOAD=0 when en=0 | Section 7.2 |
| T2 | All LEDs off (mode 000/00/000) | Tables 25/26/27 |
| T3 | All LEDs always on (mode 001/01/001) | Tables 25/26/27 |
| T4 | Activity blink gen A, on-first (010b) | Table 25 |
| T5 | Activity blink gen A, off-first (011b) | Table 25 |
| T6 | Activity blink gen B, on-first (110b) | Table 25 |
| T7 | Locate on + locate blink gen A | Table 26 |
| T8 | Error on + error blink gen A + error blink gen B | Table 27 |
| T9 | SOF auto-flash + re-trigger test | Table 25, Section 7.4 |
| T10 | EOF auto-flash | Table 25, Section 7.4 |
| T11 | Mixed pattern — all 4 drives, different modes | All tables |
| T12 | Disable after run — idle check | Section 7.2 |
| T13 | Full reset — tristate check | Section 7.2/7.3/7.4 |

The testbench also includes:
- Simulated backplane target that drives SDI with real drive-status bits
- Automatic RX frame checker — prints PASS/FAIL per frame
- 64ms reset detection per spec section 7.1
- `$dumpvars` waveform export to sgpio_wave.vcd

---

## How to Simulate

### ModelSim (recommended)
```bash
vlib work
vmap work work
vlog src/sgpio_initiator.v tb/tb_sgpio.v
vsim tb_sgpio
```

In the ModelSim transcript:
```tcl
add wave *
run -all
wave zoom full
```

Or run everything with one command using the do script:
```bash
vsim -do sim/run.do
```

### Icarus Verilog + GTKWave
```bash
iverilog -g2005 -o sim src/sgpio_initiator.v tb/tb_sgpio.v
vvp sim
gtkwave sgpio_wave.vcd
```

---

## Waveform Signals to Watch

| Signal | Expected Behaviour |
|--------|--------------------|
| SCLK | Regular square wave at 100 kHz. Goes to 0 when en=0 |
| SLOAD | Pulses HIGH once every 17 SCLK cycles |
| SDO | Changes pattern per test — blinking during gen A/B tests |
| SDI | Target drives ID_PAT after first SLOAD=1 sync |
| gpio_rx | Shows 000000001000 from frame 2 onwards |
| rx_rdy | Short pulse once per completed frame |
| sof_r / eof_r | Pulses during T9 and T10 tests |
| fc | Frame counter increments to 106 across full simulation |

---

## Tools Used

| Tool | Version |
|------|---------|
| ModelSim | Intel FPGA Edition 2020.1 |
| Icarus Verilog | 12.0 (optional) |
| GTKWave | 3.3.x |

---

## Reference

**SFF-8485 Revision 0.7** — Serial GPIO (SGPIO) Bus Specification
Published February 2006, SFF Committee / SNIA
https://www.snia.org/sff/specifications

---



