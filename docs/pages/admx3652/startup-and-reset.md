# Reset, Startup, and Stored Settings

## Startup sequence

Firmware 4.9.2 emits bootloader and application messages during startup. Host software should ignore startup detail and wait for:

```text
DAQ is ready to use
```

The following sequence is provided for diagnostics.

| Approx. time after `*RST` | Approx. time after power-on | Message |
|---:|---:|---|
| — | 0 | NUL bytes may be present |
| 5 ms | 10 ms | `Bootloader(Version 1.1.0) is jumping to application...` |
| 6 ms | 12 ms | `Found application` |
| 7 ms | 13 ms | `Launching application...` |
| — | 0.14–0.63 s | burst of NUL bytes may occur |
| — | about 0.64 s | bootloader/application launch may repeat |
| 2.06 s | about 2.70 s | `Image validation passed.` |
| 2.06 s | about 2.70 s | `Reset reason: ...` |
| 2.06 s | about 2.70 s | firmware revision/build line |
| 2.07 s | about 2.70 s | `Waiting for Reference Stable...` |
| 3.04 s | about 3.68 s | `ADC self check done` |
| 4.64 s | about 5.28 s | `DAQ is ready to use` |

Power-up timing varies more than commanded-reset timing. Cold-start timing after an extended power-off is not specified here.

## Reset defaults

A power cycle and `*RST` produce the same measurement defaults.

| Setting | Reset state |
|---|---|
| CH1 range | 2 V resolved range, auto range enabled |
| CH2 range | 20 V resolved range; auto-range state not established |
| NPLC, both channels | 10 |
| Line frequency | 50 Hz |
| Trigger source | Internal |
| CH1 read mode | Continuous, running |
| CH2 read mode | Single, stopped |
| Error queue | Cleared |
| Privilege mode | User |
| Baud rate | Retained |

Set both ranges explicitly after reset. Channel 1 starts measuring immediately and may still be changing range under auto range.

## Stored settings

Only the following are retained through reset and power loss:

- UART baud rate;
- calibration data and associated calibration metadata.

Measurement settings are not stored. Reapply the complete operating configuration after every restart.

## Changing baud rate safely

1. Send `SYSTem:BAUDRATE:SET {rate}` at the current baud.
2. Wait for:

   ```text
   New Baudrate N is being set...
   ```

3. Reconfigure the host UART to the new rate.
4. Send one expendable query such as `*IDN?`.
5. Ignore the missing response to that first query.
6. Resume normal traffic.

Do not change the host baud rate after any of these responses:

```text
Baudrate N was already set
Baudrate N is NOT supported, only support ...
```

or after a baud/NPLC rejection error.

## Bootloader recovery

The banner:

```text
=In-Application Programming Application =
```

indicates that the module is in its bootloader rather than the measurement application.

In this state normal SCPI commands are not accepted. The bootloader uses bare single-character commands with no terminator:

- `1` starts YMODEM receive and returns `Waiting for the file to be sent`;
- `2` runs the stored application and eventually returns `DAQ is ready to use`.

The bootloader is normally encountered only during or after firmware update activity.

---
