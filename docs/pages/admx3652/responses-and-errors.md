# Responses, Errors, and Device Messages

## Response conventions

Host parsers should allow for the following firmware conventions:

- trailing spaces are inconsistent;
- spacing before a colon varies between responses;
- `Revsion` is misspelled in revision responses;
- manufacture and calibration dates use different formats;
- numeric configuration values are returned with six decimal places;
- channel labels differ between configuration, measurements, and overload reports.

Trim leading and trailing white space where it is not significant, but do not depend on a normalized label spelling that the firmware does not transmit.

## Error queue

**Observed:** The error queue holds 17 entries.

Errors remain queued until read with `SYSTem:ERRor?`, cleared with `*CLS`, or cleared by reset.

Each protocol error is normally reported twice:

1. asynchronously when it occurs; and
2. later when removed from the error queue.

If the queue is full, a further error also causes:

```text
**ERROR: -350, "Queue overflow"
```

The IEEE 488.2 status registers do not indicate this condition.

## Error codes

| Code | Text | Common cause |
|---:|---|---|
| 0 | `No error` | Empty queue or `*CLS` response |
| −101 | `Invalid character` | Malformed syntax; split command |
| −108 | `Parameter not allowed` | Extra parameter |
| −109 | `Missing parameter` | Required parameter omitted |
| −113 | `Undefined header` | Unknown command or invalid abbreviation |
| −200 | `Execution error` | Invalid channel, NPLC/baud conflict, invalid sub-1 NPLC |
| −224 | `Illegal parameter value` | Value outside an allowed enumeration |
| −350 | `Queue overflow` | Additional error when queue is full |
| −363 | `Input buffer overrun` | Over-length command |

## Error formats

An asynchronous error has the form:

```text
**ERROR: -101, "Invalid character"
```

The same error read from the queue has the form:

```text
-101,"Invalid character"
```

Some errors include additional plain-text lines before the coded error.

For example, an invalid NPLC/baud combination may return:

```text
Error: Baudrate shall be > 460800 for NPLC 0.010000
Current BAUDRATE  : 460800
Current NPLC-CHAN1: 10.000000
Current NPLC-CHAN2: 10.000000
**ERROR: -200, "Execution error"
```

Do not assume that one command produces exactly one response line.

## Device messages

The module can also transmit uncoded text.

| Message | Meaning |
|---|---|
| `DAQ is ready to use` | Startup complete |
| `Reset reason: Software` | Restart caused by `*RST` |
| `Reset reason: POR/PDR` | Power-on reset |
| `Waiting for Reference Stable...` | Startup progress |
| `Image validation passed.` | Startup progress |
| `Found application` | Bootloader startup |
| `Launching application...` | Bootloader startup |
| `Bootloader(Version …) is jumping to application...` | Bootloader startup |
| `ChannelN OVERLOAD` | Measurement overrange |
| `Channel Index Input Error!` | Invalid channel argument |
| `New Baudrate N is being set...` | Baud change accepted |
| `Baudrate N was already set` | Requested baud already active |
| `Baudrate N is NOT supported...` | Unsupported baud |
| `Adc...` or `ADC encounter ADC_ERROR...` | ADC or self-test fault |
| `Power monitor value ...` | Supply-monitor fault |
| `calibration data stored successfully` | Calibration NVM write completed |
| `calibration data erased successfully` | Calibration NVM erased |
| `=In-Application Programming Application =` | Bootloader active |
| `Execute the application` | Bootloader command response |
| `Waiting for the file to be sent` | Bootloader waiting for YMODEM data |

An ADC or power-monitor fault should be treated as a hardware or supply problem, not as a normal SCPI error.

---

---

## Observed Firmware Behaviour

This appendix collects Rev. 4.9.2 behaviour that is useful for integration but is not treated as a guaranteed product specification.

### Startup traffic

- Power-up may contain NUL bytes.
- Bootloader application-launch text may appear twice.
- `DAQ is ready to use` is the reliable ready indication.
- Channel 1 begins continuous acquisition after startup.

### Serial parser

- An unterminated command fragment is discarded at the end of a host write.
- A command split across writes is not reconstructed.
- Maximum accepted command length is 253 bytes including terminator.
- Large over-length writes may be silently dropped.
- Measurement lines are emitted as two low-level UART writes.

### Measurement state

- `MEASure:VOLTage:DC?` stops a streaming channel under internal trigger.
- Read-mode commands are idempotent.
- Read mode cannot be queried.
- Auto-range enable state cannot be queried.
- Line-frequency selection cannot be queried.
- Mixed read modes under external trigger are accepted but should be treated as unsupported.

### External trigger

- Trigger pulses received during conversion are discarded rather than queued.
- Maximum observed external-trigger throughput is approximately 714 readings/s at NPLC = 0.05.
- Two armed channels alternate conversions.

### Timing

At NPLC ≥ 1, single-read time is approximately:

```text
2 × NPLC / fLINE + 3 ms
```

At NPLC < 1, fixed firmware apertures are used.

### Line frequency

The Rev. B data sheet states that the DVM automatically detects AC line frequency. Firmware 4.9.2 was observed instead to use the value selected with `SYSTem:PLC:SET`. No automatic line-frequency detection was observed.

### Error handling

- Error queue depth is 17.
- An error is normally sent asynchronously and also retained in the queue.
- Queue overflow generates an additional `-350` line.
- IEEE 488.2 status registers remain zero.

---
