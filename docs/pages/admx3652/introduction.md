# Introduction

**Applicable hardware:** Rev. 4.3.1<br>
**Applicable firmware:** Rev. 4.9.2

This manual describes operation of the ADMX3652 with hardware Rev. 4.3.1 and firmware Rev. 4.9.2. Where observed Rev. 4.9.2 behaviour differs from the ADMX3652 data sheet Rev. B (10/2024) or EVAL-ADMX3652 User Guide UG-2138 Rev. C (3/2025), the behaviour described here applies to this firmware revision.

Unless otherwise stated, numerical performance specifications are taken from the ADMX3652 data sheet. Behaviour identified as **Observed** was measured on hardware Rev. 4.3.1 with firmware Rev. 4.9.2 and should not be assumed for other revisions.

---

## Description

The ADMX3652 is a dual-channel DC digital voltmeter module. Each channel provides fixed ranges of ±0.2 V, ±2 V, and ±20 V, with automatic range selection available. The module has 6½-digit specified resolution and a maximum reading rate of 1 kSPS.

The module is controlled through a UART using a SCPI-style ASCII command set. Measurements and command responses are returned as ASCII text on the same UART.

| Item | Description |
|---|---|
| Channels | 2 |
| DC ranges | ±0.2 V, ±2 V, ±20 V, and auto range |
| Maximum reading rate | 1 kSPS |
| Trigger sources | Internal timer or external CTRL input |
| Supply | 5 V nominal |
| Typical operating current | 310 mA |
| Typical inrush current | 860 mA |
| Interface | UART, 8 data bits, no parity, 1 stop bit |
| Default baud rate | 460,800 bps |
| Operating temperature | 0 °C to 45 °C |
| Package | ML-10-1, 10-lead module |
| Ordering model | ADMX3652Z-ML |
| Evaluation board | EVAL-ADMX3652Z-INT |

The `Z` suffix denotes a RoHS-compliant part.

## Important operating information

> #### Important {: .warning}
>
> Read the following before writing host software.

1. **Channel 1 starts in continuous measurement after reset.** Wait for `DAQ is ready to use`, stop both channels, and drain any remaining input before beginning normal request/response traffic.

2. **Send each command, including its terminator, in one UART write.** An unterminated command fragment is discarded. A command split across writes is not reassembled.

3. **Successful set commands normally return no response.** Check the error queue when confirmation is required.

4. **Some operating state cannot be queried.** The host should keep its own copy of the configured read mode, auto-range selection, and power-line frequency.

5. **Do not issue calibration, non-volatile-memory, bootloader, or privileged-mode write commands during normal operation.** See [Restricted commands](calibration.md#restricted-commands).

## ESD and operating limits

The module is ESD-sensitive and is intended for indoor use. Use normal ESD handling precautions during installation and service.

Absolute maximum ratings are stress limits. Operation at or near an absolute maximum rating is not implied. Exposure beyond the normal operating limits may affect reliability or cause permanent damage.

Allow 30 minutes warm-up before measurements requiring rated accuracy.

## Measurement principle

The input stage uses a precision ADC driver and precision resistor network to provide the three measurement ranges. The module is factory calibrated to correct gain and offset errors for each range. Calibration data is retained in non-volatile memory.

The measurement aperture is controlled by NPLC. At NPLC values of 1 or greater, firmware 4.9.2 derives the aperture from the selected 50 Hz or 60 Hz power-line frequency. Shorter NPLC settings use fixed apertures. See [NPLC and aperture](measurements.md#nplc-and-aperture), [Power-line frequency](measurements.md#power-line-frequency), and [Conversion time](triggering.md#conversion-time).

---
