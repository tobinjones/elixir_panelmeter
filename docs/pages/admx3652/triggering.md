# Triggering and Acquisition

## Internal trigger

Select internal triggering with:

```text
TRIGger:SOURce INTernal
```

### Single-read operation

Set the required channel to single-read mode:

```text
CONFigure:CONTINUOUS:READ 1,OFF
```

Then request each measurement:

```text
MEASure:VOLTage:DC? 1
```

The command returns one reading after the conversion time.

### Continuous operation

Start continuous acquisition with:

```text
CONFigure:CONTINUOUS:READ 1,ON
```

The module then transmits readings without further requests.

Stop acquisition with:

```text
CONFigure:CONTINUOUS:READ 1,OFF
```

### Effect of `MEASure` on a streaming channel

**Observed:** If `MEASure:VOLTage:DC?` is sent to a channel that is already streaming under internal trigger, one reading is returned and that channel is left in single-read mode. No error is reported.

If the other channel is streaming, a single `MEASure` on the idle channel is interleaved with the stream and does not stop the streaming channel.

## External trigger

Select external triggering with:

```text
TRIGger:SOURce EXTernal
```

CTRL responds to a rising edge. Minimum specified pulse width is 1 µs.

### Single-read external trigger

Set the channel to single-read mode:

```text
CONFigure:CONTINUOUS:READ 1,OFF
```

Arm it with:

```text
MEASure:VOLTage:DC? 1
```

No voltage reading is returned at this point. The module returns channel enable status, for example:

```text
Channel1: ENABLED
Channel2: DISABLED
```

Each subsequent valid CTRL pulse produces a reading. The channel remains armed for later pulses.

Disarm it with:

```text
CONFigure:CONTINUOUS:READ 1,OFF
```

### Continuous external trigger

With continuous mode enabled, the first CTRL pulse starts free-running acquisition. Further CTRL pulses do not time individual readings.

## Two-channel acquisition

**Observed:** The two channels share the conversion path and are serviced sequentially.

With both channels streaming, readings alternate between channels. The per-channel period is approximately:

```text
period(CH1) = aperture(CH1) + aperture(CH2)
period(CH2) = aperture(CH1) + aperture(CH2)
```

Examples at 50 Hz:

| Configuration | Approximate per-channel period |
|---|---:|
| CH1 only, NPLC 10 | 400.9 ms |
| CH1 only, NPLC 1 | 40.6 ms |
| CH1 + CH2, NPLC 10 / 10 | 802.0 ms |
| CH1 + CH2, NPLC 1 / 10 | 441.6 ms |

When both externally triggered channels are armed, each trigger produces one conversion and the reported channels alternate. Each channel therefore receives one reading for every two accepted trigger events.

## Trigger latency and missed triggers

The data sheet specifies 400 ms trigger latency at NPLC = 10, auto-zero enabled, with external trigger.

**Observed:** A CTRL pulse received while a conversion is in progress is discarded; trigger events are not queued.

The delivered reading period is therefore the smallest whole multiple of the trigger period that is not shorter than the conversion time.

| Trigger period | Conversion time | Delivered period |
|---:|---:|---:|
| 800 ms | 403 ms | 800 ms |
| 200 ms | 403 ms | 600 ms |
| 1.4 ms | 1.4 ms | 1.4 ms |
| 1.3 ms | 1.4 ms | 2.6 ms |

Do not trigger faster than the conversion rate. A slightly excessive trigger rate can reduce rather than merely limit the delivered reading rate.

**Observed:** The maximum external-trigger rate at NPLC = 0.05 is approximately 714 readings/s. The 1 kSPS rate is obtained in internal continuous mode.

## Conversion time

With auto-zero enabled, firmware 4.9.2 shows the following approximate single-read times.

For NPLC ≥ 1:

```text
t ≈ 2 × NPLC / fLINE + 3 ms
```

For NPLC < 1, fixed aperture values are used.

| NPLC | 50 Hz | 60 Hz |
|---:|---:|---:|
| 0.05 | 4.0 ms | 4.0 ms |
| 0.1 | 5.0 ms | 5.0 ms |
| 0.25 | 8.0 ms | 8.0 ms |
| 0.5 | 13.0 ms | 13.0 ms |
| 1 | 43.2 ms | 36.5 ms |
| 10 | 403.6 ms | 337.0 ms |
| 100 | 4006.8 ms | approximately 3336 ms |

These values are **observed**, not additional guaranteed specifications.

## Throughput

| Mode | Observed rate at NPLC = 0.05 |
|---|---:|
| Internal continuous, one channel | 997.7 samples/s |
| Single-read polling | approximately 250 samples/s |
| External trigger | approximately 714 samples/s maximum |

The rated 1 kSPS throughput requires internal continuous acquisition.

---
