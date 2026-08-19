defmodule ADMX3652.Protocol do
  @moduledoc false

  @type channel :: 1 | 2

  @type decoded ::
          {:measurement, channel(), float()}
          | {:overload, channel()}
          | {:range, channel(), float()}
          | {:nplc, channel(), float()}
          | {:baud_rate, pos_integer()}
          | {:identity, binary()}
          | {:mode, :user | :debug | :production}
          | {:information, atom(), binary()}
          | {:device_message, term()}
          | {:async_error, integer(), binary()}
          | {:error_queue, integer(), binary()}
          | :unknown

  @spec decode(binary()) :: decoded()
  def decode(raw_line) when is_binary(raw_line) do
    trimmed_line = String.trim(raw_line)

    case trimmed_line do
      # Measurements

      "Channel1: " <> value ->
        decode_measurement(1, value)

      "Channel2: " <> value ->
        decode_measurement(2, value)

      "Channel1 OVERLOAD" ->
        {:overload, 1}

      "Channel2 OVERLOAD" ->
        {:overload, 2}

      # Configuration

      "CHAN[1]-RANGE: " <> value ->
        decode_float(value, &{:range, 1, &1})

      "CHAN[2]-RANGE: " <> value ->
        decode_float(value, &{:range, 2, &1})

      "CHAN[1]-NPLC: " <> value ->
        decode_float(value, &{:nplc, 1, &1})

      "CHAN[2]-NPLC: " <> value ->
        decode_float(value, &{:nplc, 2, &1})

      "Current BAUDRATE  : " <> value ->
        decode_baud_rate(value)

      "Current NPLC-CHAN1: " <> value ->
        decode_float(value, &{:nplc, 1, &1})

      "Current NPLC-CHAN2: " <> value ->
        decode_float(value, &{:nplc, 2, &1})

      # Simple query responses

      "ADMX3652" ->
        {:identity, "ADMX3652"}

      "User Mode" ->
        {:mode, :user}

      "Debug Mode" ->
        {:mode, :debug}

      "Production Mode" ->
        {:mode, :production}

      # Device information

      "Device Information: " <> value ->
        {:information, :device, String.trim(value)}

      "Hardware Revsion: " <> value ->
        {:information, :hardware_revision, String.trim(value)}

      "Firmware Revsion: " <> value ->
        {:information, :firmware_revision, String.trim(value)}

      "Batch NO.: " <> value ->
        {:information, :batch_number, String.trim(value)}

      "Manufacture Date: " <> value ->
        {:information, :manufacture_date, String.trim(value)}

      "User Information: " <> value ->
        {:information, :user, String.trim(value)}

      # Startup / lifecycle messages

      "DAQ is ready to use" ->
        {:device_message, :ready}

      "Image validation passed." ->
        {:device_message, :image_validation_passed}

      "ADC self check done" ->
        {:device_message, :adc_self_check_done}

      "Waiting for Reference Stable..." ->
        {:device_message, :waiting_for_reference}

      "Found application" ->
        {:device_message, :application_found}

      "Launching application..." ->
        {:device_message, :launching_application}

      "Reset reason: " <> reason ->
        {:device_message, {:reset_reason, String.trim(reason)}}

      "FW: " <> description ->
        {:device_message, {:firmware_build, String.trim(description)}}

      # Everything less conveniently expressed by prefix matching

      _ ->
        decode_other(trimmed_line)
    end
  end

  defp decode_measurement(channel, value) do
    decode_float(value, &{:measurement, channel, &1})
  end

  defp decode_baud_rate(value) do
    decode_integer(value, fn
      number when number > 0 -> {:baud_rate, number}
      _number -> :unknown
    end)
  end

  defp decode_other(line) do
    cond do
      match = Regex.run(~r/^Bootloader\(Version (.+)\) is jumping to application\.\.\.$/, line) ->
        [_, version] = match
        {:device_message, {:bootloader, version}}

      match = Regex.run(~r/^\*\*ERROR:\s*(-?\d+),\s*"([^"]*)"$/, line) ->
        [_, code, message] = match
        {:async_error, String.to_integer(code), message}

      match = Regex.run(~r/^(-?\d+),\s*"([^"]*)"$/, line) ->
        [_, code, message] = match
        {:error_queue, String.to_integer(code), message}

      true ->
        :unknown
    end
  end

  defp decode_float(value, fun) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> fun.(number)
      _ -> :unknown
    end
  end

  defp decode_integer(value, fun) do
    case Integer.parse(String.trim(value)) do
      {number, ""} -> fun.(number)
      _ -> :unknown
    end
  end
end
