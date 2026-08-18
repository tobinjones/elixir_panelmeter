# Calibration

## General

The recommended calibration interval is one year.

The calibration model is three-point per channel:

- zero;
- positive full scale;
- negative full scale.

The resulting data contains an offset, positive gain, and negative gain for each range.

A calibration source should be substantially more accurate than the module. The existing procedure specifies a reference source at least four times more accurate, such as an instrument in the class of a Fluke 5720A or 5730A.

## Reading calibration information

The following queries are read-only:

```text
SYSTem:CAL:DATE?
SYSTem:CAL:TIMES?
SYSTem:ZERO:CAL? {1|2}
SYSTem:POS:FULL:CAL? {1|2}
SYSTem:NEG:FULL:CAL? {1|2}
SYSTem:CAL:DATA? {1|2}
```

Reading these values does not alter calibration.

## Recognising valid stored data

Stored gain constants are normally close to unity and offsets are normally small. A calibration block that is absent or entirely zero indicates erased or corrupt calibration data.

See [Calibration data format](#calibration-data-format) for the data format.

## Calibration procedure

The complete calibration sequence writes:

1. zero calibration;
2. positive full-scale calibration;
3. negative full-scale calibration;
4. calibration date;
5. calibration data to non-volatile memory.

The firmware enforces this order.

Calibration should be performed only with an appropriate reference source and a documented service procedure.

## Restricted commands

> **CAUTION — CALIBRATION AND NON-VOLATILE MEMORY**
>
> Do not send the commands in this section from normal measurement software. Several alter calibration or non-volatile state. `SYSTem:CAL:STORE OFF` erases stored calibration.

| Command | Effect |
|---|---|
| `SYSTem:CAL:STORE OFF` | Erases stored calibration |
| `SYSTem:CAL:STORE ON` | Commits staged calibration |
| `SYSTem:ZERO:CAL {ch},{v}` | Writes zero calibration |
| `SYSTem:POS:FULL:CAL {ch},{v}` | Writes positive full-scale calibration |
| `SYSTem:NEG:FULL:CAL {ch},{v}` | Writes negative full-scale calibration |
| `SYSTem:CAL:DATE {y},{m},{d}` | Writes calibration date |
| `SYSTem:WRITe:INFormation USEr,"..."` | Changes User Information |
| `SYSTem:INFormation:STORE ON` | Stores identity metadata in NVM |
| `SYSTem:MODE "DEBUG","DebugADIDvm!"` | Enters Debug Mode |
| `SYSTem:SERIAL:UPGRADE ON` | Enters bootloader |

Calibration query commands differ from calibration write commands only by the question mark. Do not construct calibration commands by string substitution unless the host software positively distinguishes read and write operations.

---

---

## Calibration Data Format

The calibration queries return five-line blocks.

Example zero and positive-gain blocks:

```text
CHAN[1]
 OFFSET:
   X0_1 : 0.00000536
   X1   : 0.00000173
   X10  : 0.00000097
CHAN[1]
 POS_GAIN:
   X0_1 : 1.00763237
   X1   : 1.00762260
   X10  : 1.00760925
```

The three block headings are:

```text
OFFSET:
POS_GAIN:
NEG_GAIN:
```

The keys describe analog gain rather than voltage range:

| Key | Analog gain | DVM range |
|---|---:|---:|
| `X0_1` | 0.1 | 20 V |
| `X1` | 1 | 2 V |
| `X10` | 10 | 0.2 V |

The underscore in `X0_1` represents the decimal point in the gain name.

`SYSTem:ZERO:CAL?`, `SYSTem:POS:FULL:CAL?`, and `SYSTem:NEG:FULL:CAL?` each return one five-line block.

`SYSTem:CAL:DATA?` returns all three blocks in this order:

1. offset;
2. positive gain;
3. negative gain.

Stored values are printed with eight decimal places. Field alignment is cosmetic and should not be used for parsing.
