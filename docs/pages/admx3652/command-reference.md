# Command Reference

## Command summary

| Command | Function |
|---|---|
| `*RST` | Reset and restart |
| `*IDN?` | Read identity |
| `*CLS` | Clear error queue |
| `*OPC?`, `*WAI` | Minimal IEEE 488.2 compatibility |
| `*ESR?`, `*STB?`, `*ESE?`, `*SRE?` | Status stubs |
| `SYSTem:PLC:SET` | Set 50/60 Hz line frequency |
| `CONFigure:VOLTage:DC` | Set or query range |
| `CONFigure:VOLTage:DC:NPLCycles` | Set or query NPLC |
| `CONFigure:CONTINUOUS:READ` | Set single/continuous mode |
| `CONFIGURE:INFormation?` | Read baud and both NPLC values |
| `CONFigure?` | Stub |
| `MEASure:VOLTage:DC?` | Read or arm a channel |
| `TRIGger:SOURce` | Set or query trigger source |
| `SYSTem:BAUDRATE:SET` | Set or query baud rate |
| `SYSTem:INFormation?` | Read identity fields |
| `SYSTem:MODE?` | Read privilege mode |
| `SYSTem:VERSion?` | Read SCPI version |
| `SYSTem:CAL:DATE?` | Read calibration date |
| `SYSTem:CAL:TIMES?` | Read calibration count |
| `SYSTem:ERRor?` | Pop one queued error |
| `SYSTem:ERRor:COUNt?` | Read error queue depth |
| `STATus:...` | Status stubs |
| calibration queries | Read stored calibration data |

Commands that write calibration data, identity NVM, privilege mode, or firmware-update state are listed separately under [Restricted commands](calibration.md#restricted-commands).

## IEEE 488.2 common commands

### `*RST`

**Function:** Reset the instrument and restart firmware.

**Syntax**

```text
*RST
```

All measurement settings return to reset defaults. Baud rate and calibration data are retained.

The error queue is cleared and privilege mode returns to User Mode.

Wait for:

```text
DAQ is ready to use
```

before sending further configuration.

**Observed:** Ready time is approximately 4.64 s after the command.

### `*IDN?`

**Function:** Read instrument identity.

**Syntax**

```text
*IDN?
```

**Response**

```text
ADMX3652
```

The response contains one field and may include a trailing space. It is not the four-field IEEE 488.2 identification form.

### `*CLS`

**Function:** Clear the error queue.

**Syntax**

```text
*CLS
```

Treat this as a set command. Firmware 4.9.2 may emit:

```text
**ERROR: 0, "No error"
```

but this response is not sufficiently consistent to use as an acknowledgement.

### `*OPC?`

Returns:

```text
1
```

### `*WAI`

Accepted with no response.

### `*ESR?`, `*STB?`, `*ESE?`, `*SRE?`

Return:

```text
0
```

These registers do not reflect the error queue. Use `SYSTem:ERRor:COUNt?` for fault detection.

Do not issue `*CAL?`. Its behaviour on this firmware has not been established.

## Measurement configuration

### `SYSTem:PLC:SET`

**Function:** Set line frequency used for NPLC ≥ 1.

**Syntax**

```text
SYSTem:PLC:SET {50|60}
```

**Default:** 50 Hz

There is no query form. Set this value after reset rather than relying on the default.

### `CONFigure:VOLTage:DC`

**Function:** Set channel range.

**Syntax**

```text
CONFigure:VOLTage:DC {1|2},{0.2|2|20|AUTO}
```

Each channel is configured separately.

### `CONFigure:VOLTage:DC?`

**Function:** Read the resolved channel range.

**Syntax**

```text
CONFigure:VOLTage:DC? {1|2}
```

**Example response**

```text
CHAN[1]-RANGE: 0.200000
```

With auto range enabled, the returned value is the presently selected range, not the word `AUTO`.

### `CONFigure:VOLTage:DC:NPLCycles`

**Function:** Set channel aperture in power-line cycles.

**Syntax**

```text
CONFigure:VOLTage:DC:NPLCycles {1|2},{n}
```

Accepted values are described under [NPLC and aperture](measurements.md#nplc-and-aperture). The [baud-rate restriction](serial-interface.md#baud-rate-and-nplc) also applies.

### `CONFigure:VOLTage:DC:NPLCycles?`

**Function:** Read channel NPLC.

**Syntax**

```text
CONFigure:VOLTage:DC:NPLCycles? {1|2}
```

**Example response**

```text
CHAN[1]-NPLC: 10.000000
```

### `CONFigure:CONTINUOUS:READ`

**Function:** Select single or continuous read mode.

**Syntax**

```text
CONFigure:CONTINUOUS:READ {1|2},{ON|OFF}
```

`ON` selects continuous read. `OFF` selects single read and also disarms an externally triggered channel.

There is no query form.

The word `CONTINUOUS` must be written in full.

### `CONFIGURE:INFormation?`

**Function:** Read baud rate and NPLC values for both channels.

**Syntax**

```text
CONFIGURE:INFormation?
```

**Response**

```text
Current BAUDRATE  : 460800
Current NPLC-CHAN1: 10.000000
Current NPLC-CHAN2: 10.000000
```

`CONFIGURE` must be written in full.

### `CONFigure?`

This command is a stub. It returns:

```text
VOLT +
```

regardless of the active configuration.

## Measurement command

### `MEASure:VOLTage:DC?`

**Function:** Read or arm a channel, depending on trigger source.

**Syntax**

```text
MEASure:VOLTage:DC? {1|2}
```

With internal trigger, one voltage reading is returned. Sending this command again before that reading arrives restarts the conversion rather than queueing a second one; see [Overlapping `MEASure` requests](triggering.md#overlapping-measure-requests).

With external trigger, the channel is armed and the command returns channel enable state instead of a voltage.

Example:

```text
Channel1: ENABLED
Channel2: DISABLED
```

A channel argument outside 1 or 2 produces:

```text
Channel Index Input Error!
**ERROR: -200, "Execution error"
```

See [Triggering and acquisition](triggering.md) for complete state behaviour.

## Trigger commands

### `TRIGger:SOURce`

**Function:** Set trigger source for both channels.

**Syntax**

```text
TRIGger:SOURce {INTernal|EXTernal}
```

**Default:** `INTernal`

No commands are provided for trigger slope, delay, count, or software trigger.

### `TRIGger:SOURce?`

**Function:** Read trigger source.

**Syntax**

```text
TRIGger:SOURce?
```

**Responses**

```text
Trigger Mode : INTernal
```

or:

```text
Trigger Mode : EXTernal
```

## Baud rate

### `SYSTem:BAUDRATE:SET`

**Function:** Set UART baud rate.

**Syntax**

```text
SYSTem:BAUDRATE:SET {rate}
```

A successful change is acknowledged at the old baud rate:

```text
New Baudrate 115200 is being set...
```

After this line is received, reconfigure the host UART.

**Observed:** The first command transmitted at the new baud rate is lost. Send one expendable query, such as `*IDN?`, and ignore its missing response before resuming normal traffic.

If the requested rate is already selected:

```text
Baudrate N was already set
```

No baud change occurs.

If the rate is unsupported:

```text
Baudrate N is NOT supported, only support 9600/…/460800
```

No baud change occurs.

If the selected NPLC does not permit the requested rate, the command is rejected and the baud rate remains unchanged.

### `SYSTem:BAUDRATE:SET?`

**Function:** Read current baud rate.

**Response**

```text
BAUDRATE  : 460800
```

## System information

### `SYSTem:INFormation?`

**Function:** Read one or all identity fields.

**Syntax**

```text
SYSTem:INFormation? [selector]
```

| Selector | Example response |
|---|---|
| `HARdware` | `Hardware Revsion: Rev4.3.1 ` |
| `FIRmware` | `Firmware Revsion: Rev4.9.2 ` |
| `BATch` | `Batch NO.: 522605110269 ` |
| `MANufacture` | `Manufacture Date: 2026.05.16 ` |
| `DEVice` | `Device Information: ADMX3652 ` |
| `USEr` | `User Information: Standard ` |
| none | Six lines, one for each field |

`Revsion` is the spelling transmitted by the firmware.

### `SYSTem:MODE?`

Returns the current privilege mode, normally:

```text
User Mode
```

Firmware 4.9.2 also contains Debug and Production modes. Normal measurement software should not enter either mode.

### `SYSTem:VERSion?`

Returns:

```text
1999.0
```

### `SYSTem:CAL:DATE?`

Returns the stored calibration date.

Example:

```text
Calibration Date year-month-day: 2026-5-23
```

### `SYSTem:CAL:TIMES?`

Returns the recorded number of calibrations.

Example:

```text
Calibration Times : 1
```

## Error and status commands

### `SYSTem:ERRor?`

Removes and returns the oldest queued error.

Example:

```text
-101,"Invalid character"
```

If no error is queued:

```text
0,"No error"
```

### `SYSTem:ERRor:COUNt?`

Returns the number of queued errors without removing them.

Example:

```text
6
```

Use this query for routine fault detection.

### `STATus:QUEStionable?`
### `STATus:QUEStionable:EVENt?`
### `STATus:QUEStionable:ENABle?`

These are stubs and return:

```text
0
```

`STATus:PRESet` is accepted with no response.

## Read-only calibration queries

The following commands read stored calibration values and do not alter them:

```text
SYSTem:ZERO:CAL? {1|2}
SYSTem:POS:FULL:CAL? {1|2}
SYSTem:NEG:FULL:CAL? {1|2}
SYSTem:CAL:DATA? {1|2}
```

The first three return five lines each. `SYSTem:CAL:DATA?` returns all three five-line blocks.

See [Calibration data format](calibration.md#calibration-data-format) for the returned format.

---

---

## Programming Summary

### Normal startup

```text
wait for: DAQ is ready to use

CONFigure:CONTINUOUS:READ 1,OFF
CONFigure:CONTINUOUS:READ 2,OFF
*CLS

drain receive buffer

SYSTem:PLC:SET 50
CONFigure:VOLTage:DC 1,2
CONFigure:VOLTage:DC:NPLCycles 1,10
TRIGger:SOURce INTernal
```

### Single reading

```text
CONFigure:CONTINUOUS:READ 1,OFF
MEASure:VOLTage:DC? 1
```

Response:

```text
Channel1: 0.123456
```

### Continuous readings

```text
CONFigure:CONTINUOUS:READ 1,ON
```

Read CRLF-terminated lines.

Stop with:

```text
CONFigure:CONTINUOUS:READ 1,OFF
```

### External trigger

```text
TRIGger:SOURce EXTernal
CONFigure:CONTINUOUS:READ 1,OFF
MEASure:VOLTage:DC? 1
```

After the enable-status response, apply rising-edge pulses to CTRL.

### Parser rules

- One complete command and terminator per host write.
- Frame responses on `\r\n`.
- Trim trailing spaces.
- Accept `-0.00000`.
- Recognise both `ChannelN: value` and `ChannelN OVERLOAD`.
- Do not assume one response line per command.
- Do not use `*ESR?` or `*STB?` for error detection.
- Use `SYSTem:ERRor:COUNt?`.
- Keep host-side copies of read mode, auto-range selection, and line frequency.

### Commands used in ordinary operation

```text
*RST
*IDN?
*CLS

SYSTem:PLC:SET {50|60}
SYSTem:BAUDRATE:SET {rate}
SYSTem:BAUDRATE:SET?

CONFigure:VOLTage:DC {ch},{0.2|2|20|AUTO}
CONFigure:VOLTage:DC? {ch}
CONFigure:VOLTage:DC:NPLCycles {ch},{n}
CONFigure:VOLTage:DC:NPLCycles? {ch}
CONFigure:CONTINUOUS:READ {ch},{ON|OFF}

MEASure:VOLTage:DC? {ch}

TRIGger:SOURce {INTernal|EXTernal}
TRIGger:SOURce?

SYSTem:ERRor?
SYSTem:ERRor:COUNt?
```

---

---

## Unimplemented Commands

The following command families have been tested and return `-113` or otherwise do not provide functional instrument control.

| Command or family | Consequence |
|---|---|
| `TRACe:` | No reading buffer |
| `DATA:` | No reading buffer |
| `FORMat:` | ASCII output only |
| `*TRG` | No software trigger |
| `TRIGger:IMMediate` | No software trigger |
| `TRIGger:` except `SOURce` | No slope, delay, count, or timing control |
| `SENSe:` | Range and NPLC are under `CONFigure:` instead |
| `SYSTem:HELP:HEADers?` | Instrument cannot enumerate its command set |
| `SYSTem:PRESet` | Not implemented |
| `*OPT?` | Not implemented |
| `*LRN?` | Not implemented |
| `*SAV` | Setup storage not implemented |
| `*RCL` | Setup recall not implemented |
| `*TST?` | No command-driven self test |
| `SYSTem:PLC:SET?` | No readback of line-frequency setting |
| auto-zero commands | Auto-zero cannot be disabled |

Because there is no reading buffer, measurements must be removed from the UART as they are produced. This is especially important in continuous mode.

---
