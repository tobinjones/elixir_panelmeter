# Installation and Connections

## Pinout

The pin numbering below is for the top view of the module.

```text
                 ADMX3652
                 TOP VIEW

        CH1_HI   1  o         o  5   VCC
        CH1_LO   2  o         o  6   EN

        CH2_HI   3  o         o  7   TX
        CH2_LO   4  o         o  8   RX
                              o  9   CTRL
                              o 10   GND
```

| Pin | Mnemonic | Function |
|---:|---|---|
| 1 | CH1_HI | Channel 1 input high |
| 2 | CH1_LO | Channel 1 input low |
| 3 | CH2_HI | Channel 2 input high |
| 4 | CH2_LO | Channel 2 input low |
| 5 | VCC | +5 V supply |
| 6 | EN | Enable input; low shuts down the module |
| 7 | TX | UART transmit, module to host |
| 8 | RX | UART receive, host to module |
| 9 | CTRL | External trigger input |
| 10 | GND | Power ground |

## Supply

Apply 4.5 V to 5.5 V between VCC and GND. Normal specifications use VCC = 5.0 V.

Typical operating current is 310 mA. Typical inrush current is 860 mA when the module is enabled. Size the supply and local wiring for the inrush current as well as the steady-state load.

## Enable input

EN has an internal pull-up and an approximate threshold of 1.05 V.

- Leave EN floating if shutdown control is not required.
- Pull EN low to shut down the module.
- When controlling EN from a host GPIO, a high-impedance output with no pull enables the module; a pull-down disables it.

This method avoids driving the pin directly and is suitable for a 3.3 V host interface.

**Observed:** Some processors default unused GPIO pins to input with an internal pull-down. Such a configuration can hold EN low. Check the host pin configuration if the module does not start.

Repeated enable cycles produce the 860 mA inrush current and should not be used unnecessarily on a shared supply rail.

## UART connections

Connect the module TX output to the host RX input and the module RX input to the host TX output. The UART uses 3.3 V logic levels and is electrically compatible with 1.8 V, 2.5 V, and 3.3 V interfaces within the [specified digital input limits](specifications.md#digital-levels).

The default serial format is:

```text
460800 baud
8 data bits
no parity
1 stop bit
```

## External trigger input

CTRL is a rising-edge trigger input. The minimum specified pulse width is 1 µs. Edge polarity is fixed and cannot be changed by command.

## Mounting

The recommended removable connection uses Mill-Max 0327-0-15-01-34-27-10-0 receptacles. The solder-mount hole for each receptacle should be at least 1.91 mm in diameter.

The module also has two M3 threaded mounting points. Maximum thread engagement is 3 mm. A screw entering farther than 3 mm may damage the module.

The module may be soldered directly to a host board where minimum height is required. When direct soldering is used:

- do not exceed 350 °C soldering-iron temperature;
- keep continuous soldering time below 5 s;
- do not use wave or reflow soldering;
- provide a means of isolating the measurement terminals and accessing the module pins if in-system calibration is required.

See [Mechanical information](mechanical.md#package) for package dimensions.

---
