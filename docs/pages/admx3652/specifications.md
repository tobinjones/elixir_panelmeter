# Performance and Specifications

Unless otherwise noted: VCC = 5.0 V, EN floating, auto-zero enabled.

## DC measurement specifications

### Resolution and reading rate

| Condition | Reading rate |
|---|---:|
| NPLC = 0.05 | 1000 samples/s |
| NPLC = 0.1 | 500 samples/s |
| NPLC = 10 | 5 samples/s |
| NPLC = 100 | 0.5 samples/s |

The data sheet specifies 6½-digit resolution under its stated conditions and identifies NPLC = 0.05 as a 5½-digit operating point.

### Input characteristics

| Range | Input resistance | Input bias current |
|---|---:|---:|
| ±0.2 V | 200 MΩ | 1 nA |
| ±2 V | 2 GΩ | 1 nA |
| ±20 V | 20 GΩ | 1 nA |

All ranges provide 10 % overrange before an overload indication.

## DC accuracy

Accuracy is specified as:

```text
±(% of reading + % of range)
```

Conditions: NPLC = 100, auto-zero on, 30 min warm-up.

| Range | Resolution | 24 h, % rdg | 24 h, % rng | 90 d, % rdg | 90 d, % rng | Temp. coeff., % rdg/°C | Temp. coeff., % rng/°C |
|---|---:|---:|---:|---:|---:|---:|---:|
| 200 mV | 200 nV | 0.0017 | 0.0017 | 0.0098 | 0.0040 | 0.0005 | 0.0005 |
| 2 V | 2 µV | 0.0005 | 0.0002 | 0.0017 | 0.0008 | 0.0005 | 0.0001 |
| 20 V | 20 µV | 0.0006 | 0.0001 | 0.0012 | 0.0004 | 0.0005 | 0.0001 |

24-hour values apply at TCAL ±1 °C with TCAL = 25 °C.<br>
90-day values apply at TCAL ±5 °C.

## RMS noise

2 V range, 1000 samples:

| NPLC | RMS noise, ppm of range |
|---:|---:|
| 100 | 0.091 |
| 10 | 0.216 |
| 1 | 0.225 |
| 0.50 | 0.246 |
| 0.25 | 0.250 |
| 0.10 | 2.5 |
| 0.05 | 4.0 |

## Noise rejection

| Parameter | Condition | Specification |
|---|---|---:|
| CMRR | NPLC = 100, 1 kΩ in CHx_LO | 100 dB |
| NMRR | NPLC ≥ 1 | 90 dB |
| NMRR | NPLC < 1 | 0 dB |

The Rev. B data sheet prints the lower NMRR condition as `NPLC ≤ 1`, which overlaps the 90 dB condition at NPLC = 1. Firmware timing and the line-synchronised integration boundary place NPLC = 1 in the NPLC ≥ 1 case used in this manual.

## Power and digital interface

### Supply

| Parameter | Min | Typ | Max | Unit |
|---|---:|---:|---:|---|
| Input voltage | 4.5 | 5.0 | 5.5 | V |
| EN threshold | — | 1.05 | — | V |
| Inrush current | — | 860 | — | mA |
| Operating current | — | 310 | — | mA |

### Digital levels

| Signal | Parameter | Min | Typ | Max | Unit |
|---|---|---:|---:|---:|---|
| CTRL, UART RX | Logic high | 2.31 | — | — | V |
| CTRL, UART RX | Logic low | — | — | 0.99 | V |
| UART TX | Logic high | 3.2 | 3.3 | — | V |
| UART TX | Logic low | 0.0 | 0.1 | — | V |

### Trigger and system-speed specifications

| Parameter | Condition | Value |
|---|---|---:|
| CTRL minimum pulse width | rising edge | 1 µs |
| Maximum data rate | — | 1 kSPS |
| Auto-range time | NPLC = 10, auto-zero on | 400 ms |
| Trigger latency | NPLC = 10, auto-zero on, external trigger | 400 ms |

## Operating environment

| Parameter | Rating |
|---|---|
| Operating temperature | 0 °C to 45 °C |
| Storage temperature | −40 °C to +70 °C |
| Relative humidity | 10 % to 90 %, noncondensing |
| Maximum altitude | 2000 m at 25 °C ambient |
| Pollution degree | 2 |
| Intended environment | Indoor use |
| Recommended calibration interval | 1 year |
| Warm-up to rated accuracy | 30 minutes |

## Absolute maximum ratings

| Parameter | Absolute maximum rating |
|---|---|
| VCC to GND | 0 V to 7 V |
| EN to GND | 0 V to VCC |
| CTRL to GND | −0.5 V to +3.8 V |
| UART TX to GND | −0.5 V to +3.8 V |
| UART RX to GND | −0.5 V to +3.8 V |
| CH1 analog input to GND | 70 V |
| CH2 analog input to GND | 70 V |

These are stress ratings only.

---
