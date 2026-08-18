# Serial Interface

## UART format and baud rates

The UART format is 8 data bits, no parity, and 1 stop bit.

Supported baud rates are:

```text
9600
14400
19200
38400
57600
115200
230400
460800
```

The default is 460800 bps. The selected baud rate is retained across `*RST` and power removal.

## Baud rate and NPLC

Firmware 4.9.2 enforces a minimum NPLC for each baud rate.

| Baud rate | Minimum NPLC |
|---:|---:|
| 9600 | 10 |
| 14400 | 10 |
| 19200 | 10 |
| 38400 | 1 |
| 57600 | 0.5 |
| 115200 | 0.25 |
| 230400 | 0.1 |
| 460800 | 0.05 |

The restriction is checked both when changing NPLC and when changing baud rate. An invalid combination is rejected without changing either setting.

## Command terminators

Commands may end with:

```text
\r
\n
\r\n
```

Responses always end with:

```text
\r\n
```

An empty command consisting only of a terminator is ignored.

## UART write framing

Each complete command, including its terminator, must be delivered in a single host write.

**Observed:** The module does not retain an unterminated fragment for the next write.

| Host writes | Result |
|---|---|
| `*IDN?` with no terminator | Discarded |
| later `\r\n` | Ignored |
| `*IDN` then `?\r\n` | Second write parsed as a separate invalid command |
| several complete terminated commands in one write | All are processed |

Maximum observed command length is 253 bytes including the terminator.

| Total command length | Behaviour |
|---:|---|
| up to 253 bytes | Accepted normally |
| 254 to approximately 1008 bytes | `-363, "Input buffer overrun"` |
| 1024 bytes or more | Silently discarded |

The module recovers without reset after these errors.

## Command syntax

Commands are case-insensitive. Leading and trailing white space is accepted. A leading colon is accepted.

A space is required before an argument. Do not insert a space before `?`.

Examples:

| Command form | Result |
|---|---|
| `*idn?` | Accepted |
| `CONF:volt:dc? 1` | Accepted |
| `:CONF:VOLT:DC? 1` | Accepted |
| `CONF:VOLT:DC?1` | Rejected, `-101` |
| `*IDN ?` | Rejected, `-101` |

### Keyword abbreviations

Most keywords accept the uppercase short form or the full word shown below. Intermediate abbreviations are not accepted.

| Keyword | Short form | Full form |
|---|---|---|
| `CONFigure` | `CONF` | `CONFIGURE` |
| `VOLTage` | `VOLT` | `VOLTAGE` |
| `NPLCycles` | `NPLC` | `NPLCYCLES` |
| `TRIGger` | `TRIG` | `TRIGGER` |
| `SOURce` | `SOUR` | `SOURCE` |
| `INFormation` | `INF` | `INFORMATION` |
| `ERRor` | `ERR` | `ERROR` |
| `CONTINUOUS` | none | `CONTINUOUS` |
| `BAUDRATE` | none | `BAUDRATE` |
| `TIMES` | none | `TIMES` |

`CONFIGURE:INFormation?` is an exception: `CONFIGURE` must be written in full.

## Compound commands

Commands may be separated by semicolons. The parser retains the current SCPI header path after a semicolon.

```text
CONF:VOLT:DC? 1;CONF:VOLT:DC? 2
```

returns the Channel 1 range and then an undefined-header error, because the second `CONF` is interpreted relative to the current path.

Use a leading colon for a second full path:

```text
CONF:VOLT:DC? 1;:CONF:VOLT:DC? 2
```

IEEE 488.2 common commands reset the path:

```text
*IDN?;*IDN?
```

An error in one sub-command does not stop later sub-commands. Responses and error lines may therefore be interleaved.

## Reading responses

Frame UART input on CRLF. Do not use fixed-size reads or a short inter-byte timeout.

**Observed:** A measurement line is transmitted in two UART writes separated by approximately 1 ms. For example, the module may transmit:

```text
Channel1
```

followed by:

```text
: 0.00000\r\n
```

A CRLF-framed receiver sees the intended single line.

## Multi-line responses

Some queries return a fixed number of lines.

| Query | Lines |
|---|---:|
| `CONFIGURE:INFormation?` | 3 |
| `SYSTem:INFormation?` with no selector | 6 |
| individual calibration query | 5 |
| `SYSTem:CAL:DATA?` | 15 |

No terminator line or sentinel follows a multi-line response. The host must know the expected line count.

---
