# Getting Started

This section gives a conservative startup sequence suitable for host software.

## Power-up

1. Apply the 5 V supply or release EN.
2. Configure the host UART for the stored baud rate. A new module normally uses 460,800 bps.
3. Ignore NUL bytes and startup text until the line:

```text
DAQ is ready to use
```

is received.

Do not use an earlier boot message as the ready indication.

**Observed:** `DAQ is ready to use` appears approximately 5.3 s after power-up on a warm module. A commanded `*RST` reaches the same point in approximately 4.6 s.

## Establish a quiet interface

Channel 1 begins continuous measurement shortly after startup. Stop both channels before sending ordinary queries.

Send:

```text
CONFigure:CONTINUOUS:READ 1,OFF
CONFigure:CONTINUOUS:READ 2,OFF
*CLS
```

Then drain any complete or partial measurement line already in the receive buffer.

Do not assume that a query sent immediately after `DAQ is ready to use` will be the next line returned.

## Apply a complete configuration

After every reset or power cycle, set the measurement state explicitly. A typical single-channel setup is:

```text
SYSTem:PLC:SET 50
CONFigure:VOLTage:DC 1,2
CONFigure:VOLTage:DC:NPLCycles 1,10
TRIGger:SOURce INTernal
CONFigure:CONTINUOUS:READ 1,OFF
```

Set the power-line frequency to the local mains frequency when NPLC is 1 or greater.

## Take a single reading

With internal trigger and single-read mode:

```text
MEASure:VOLTage:DC? 1
```

A normal response is:

```text
Channel1: 0.123456
```

The response is in volts. No unit suffix is transmitted.

## Start continuous readings

To start free-running measurements on Channel 1:

```text
CONFigure:CONTINUOUS:READ 1,ON
```

Read complete CRLF-terminated lines until acquisition is no longer required, then send:

```text
CONFigure:CONTINUOUS:READ 1,OFF
```

One measurement already in progress may still be returned after the stop command.

---
