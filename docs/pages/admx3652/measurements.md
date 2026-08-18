# Making Measurements

## Measurement state

Two settings determine how readings are produced:

- the **trigger source**, common to both channels; and
- the **read mode**, set independently for each channel.

| Trigger source | Read mode | Operation |
|---|---|---|
| Internal | Single (`OFF`) | One reading for each `MEASure:VOLTage:DC?` command |
| Internal | Continuous (`ON`) | Free-running readings |
| External | Single (`OFF`) | `MEASure` arms the channel; CTRL pulses produce readings |
| External | Continuous (`ON`) | First CTRL pulse starts free-running acquisition |

Under external trigger, mixed single and continuous read modes are accepted by the firmware but should not be used. Their measurement validity has not been established.

## Range selection

Set a fixed range with:

```text
CONFigure:VOLTage:DC {1|2},{0.2|2|20}
```

Select automatic ranging with:

```text
CONFigure:VOLTage:DC {1|2},AUTO
```

Query the resolved range with:

```text
CONFigure:VOLTage:DC? {1|2}
```

Example:

```text
CHAN[1]-RANGE: 0.200000
```

When auto range is enabled, the query returns the range currently selected by the instrument. It does not indicate that automatic ranging is enabled.

### Auto-range settling

The data sheet specifies 400 ms auto-range time at NPLC = 10 with auto-zero enabled.

**Observed:** Range selection changes by one range step per conversion. A transition from 20 V to 0.2 V therefore takes two or three readings, depending on the starting state. At NPLC = 10 this is approximately 0.8 s to 1.2 s.

Do not use the first range query after startup as an indication of the final auto-selected range.

## NPLC and aperture

Set NPLC with:

```text
CONFigure:VOLTage:DC:NPLCycles {1|2},{n}
```

Query it with:

```text
CONFigure:VOLTage:DC:NPLCycles? {1|2}
```

Example:

```text
CHAN[1]-NPLC: 10.000000
```

At NPLC ≥ 1, increasing NPLC increases integration time and improves line-frequency rejection. At NPLC < 1 the firmware uses fixed apertures and line-frequency rejection is not provided.

### Accepted NPLC values

**Observed:** Firmware 4.9.2 accepts:

- 0.05
- 0.1
- 0.25
- 0.5
- any positive real value of 1 or greater

Values such as 3.5, 200, and 1000 are accepted. Below 1, values other than the four listed above are rejected.

A negative value is not validated correctly by firmware 4.9.2 and may be parsed as zero. Do not send negative NPLC values.

The minimum NPLC also depends on baud rate; see [Baud rate and NPLC](serial-interface.md#baud-rate-and-nplc).

## Power-line frequency

For NPLC ≥ 1, select the local power-line frequency:

```text
SYSTem:PLC:SET 50
```

or:

```text
SYSTem:PLC:SET 60
```

The default is 50 Hz.

There is no query for this setting.

**Observed:** Firmware 4.9.2 uses the commanded 50 Hz or 60 Hz value and does not automatically detect the line frequency. This differs from the description in the ADMX3652 Rev. B data sheet.

The host should therefore set this value explicitly after every reset.

## Measurement output

Normal readings have the form:

```text
Channel1: 0.0000014
Channel2: 3.29473
```

The value is in volts. It is fixed-point ASCII with no exponent and no unit suffix.

The number of decimal places depends on the selected range.

| Range | Decimal places | Example | Output LSB |
|---|---:|---|---|
| 0.2 V | 7 | `0.0000014` | 100 nV |
| 2 V | 6 | `0.000001` | 1 µV |
| 20 V | 5 | `-0.00001` | 10 µV |

The output format does not change with NPLC. At short apertures the number of printed digits therefore exceeds the effective measurement resolution.

Negative zero may be returned as:

```text
-0.00000
```

A parser should accept a sign on zero.

## Overload

An input more than 10 % beyond the selected range is reported as:

```text
Channel1 OVERLOAD
```

Note that an overload line contains a space after the channel number, not the colon used in a normal reading.

No error is added to the error queue for an overload.

| Selected range | Behaviour after `OVERLOAD` |
|---|---|
| 20 V | One overload line completes the response |
| AUTO | One overload line completes the response |
| 2 V | Overload lines repeat until the range changes or the channel is stopped |
| 0.2 V | Overload lines repeat until the range changes or the channel is stopped |

**Observed:** On the 0.2 V and 2 V ranges, overload retry continues indefinitely. A host timeout does not stop it. Stop the channel or select another range.

At NPLC = 10 and 50 Hz, the repeated overload interval is approximately 200 ms, shorter than the normal 403 ms single-read time.

## Configuration state that can be read back

| Setting | Query available |
|---|---|
| Resolved range | Yes |
| NPLC | Yes |
| Trigger source | Yes |
| Baud rate | Yes |
| Auto-range enable | No |
| Single/continuous read mode | No |
| Power-line frequency | No |
| Armed state | External-trigger status only |

The host should maintain a copy of settings that cannot be queried.

---
