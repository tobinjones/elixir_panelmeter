defmodule ADMX3652.ProtocolTest do
  use ExUnit.Case, async: true

  alias ADMX3652.Protocol

  describe "decode/1" do
    test "decodes measurements and overloads" do
      assert Protocol.decode("Channel1: 1.25\r\n") == {:measurement, 1, 1.25}
      assert Protocol.decode("Channel2: -3.5") == {:measurement, 2, -3.5}
      assert Protocol.decode("Channel1 OVERLOAD") == {:overload, 1}
      assert Protocol.decode("Channel2 OVERLOAD") == {:overload, 2}
    end

    test "decodes configuration responses" do
      assert Protocol.decode("CHAN[1]-RANGE: 0.25") == {:range, 1, 0.25}
      assert Protocol.decode("CHAN[2]-RANGE: 2") == {:range, 2, 2.0}
      assert Protocol.decode("CHAN[1]-NPLC: 0.5") == {:nplc, 1, 0.5}
      assert Protocol.decode("CHAN[2]-NPLC: 10") == {:nplc, 2, 10.0}
      assert Protocol.decode("Current BAUDRATE  : 115200") == {:baud_rate, 115_200}
      assert Protocol.decode("Current NPLC-CHAN1: 1") == {:nplc, 1, 1.0}
      assert Protocol.decode("Current NPLC-CHAN2: 2") == {:nplc, 2, 2.0}
      assert Protocol.decode("Trigger Mode : INTernal") == {:trigger_source, :internal}
      assert Protocol.decode("Trigger Mode : EXTernal") == {:trigger_source, :external}
    end

    test "decodes identity and mode responses" do
      assert Protocol.decode("ADMX3652") == {:identity, "ADMX3652"}
      assert Protocol.decode("User Mode") == {:mode, :user}
      assert Protocol.decode("Debug Mode") == {:mode, :debug}
      assert Protocol.decode("Production Mode") == {:mode, :production}
    end

    test "decodes device information" do
      assert Protocol.decode("Device Information: ADMX3652") ==
               {:information, :device, "ADMX3652"}

      assert Protocol.decode("Hardware Revsion: A") ==
               {:information, :hardware_revision, "A"}

      assert Protocol.decode("Firmware Revsion: 1.2.3") ==
               {:information, :firmware_revision, "1.2.3"}

      assert Protocol.decode("Batch NO.: 42") == {:information, :batch_number, "42"}

      assert Protocol.decode("Manufacture Date: 2026-08-18") ==
               {:information, :manufacture_date, "2026-08-18"}

      assert Protocol.decode("User Information: bench") == {:information, :user, "bench"}
    end

    test "decodes lifecycle messages" do
      assert Protocol.decode("DAQ is ready to use") == {:device_message, :ready}

      assert Protocol.decode("Image validation passed.") ==
               {:device_message, :image_validation_passed}

      assert Protocol.decode("ADC self check done") ==
               {:device_message, :adc_self_check_done}

      assert Protocol.decode("Waiting for Reference Stable...") ==
               {:device_message, :waiting_for_reference}

      assert Protocol.decode("Found application") == {:device_message, :application_found}

      assert Protocol.decode("Launching application...") ==
               {:device_message, :launching_application}

      assert Protocol.decode("Reset reason: watchdog") ==
               {:device_message, {:reset_reason, "watchdog"}}

      assert Protocol.decode("FW: release build") ==
               {:device_message, {:firmware_build, "release build"}}

      assert Protocol.decode("Bootloader(Version 2.1) is jumping to application...") ==
               {:device_message, {:bootloader, "2.1"}}
    end

    test "decodes asynchronous and error queue errors" do
      assert Protocol.decode(~s(**ERROR: -12, "bad input")) ==
               {:async_error, -12, "bad input"}

      assert Protocol.decode(~s(7, "range error")) == {:error_queue, 7, "range error"}
    end

    test "returns :unknown for malformed or unrecognised lines" do
      assert Protocol.decode("Channel1: nope") == :unknown
      assert Protocol.decode("Current BAUDRATE  : 0") == :unknown
      assert Protocol.decode("7, not quoted") == :unknown
      assert Protocol.decode("something else") == :unknown
    end
  end
end
