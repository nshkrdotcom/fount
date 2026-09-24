defmodule Fount.SceneHeading do
  @moduledoc "Conservative semantic decomposition of a scene heading. Raw heading text remains authoritative."


  @doc "True when a heading is recognized by Fountain without the forced `.` marker."
  @spec standard_fountain?(binary()) :: boolean()
  def standard_fountain?(heading) when is_binary(heading) do
    Regex.match?(~r/^(?:INT|EXT|EST|I\/E|INT\.?\/EXT|EXT\.?\/INT)(?:\.|\s)/iu, String.trim(heading))
  end

  @spec parse(binary()) :: map()
  def parse(raw) when is_binary(raw) do
    trimmed = String.trim(raw)

    {context, rest} =
      case Regex.run(~r/^(INT\.?\/EXT\.?|EXT\.?\/INT\.?|INT\.?|EXT\.?|EST\.?|I\/E\.?)\s+(.*)$/iu, trimmed, capture: :all_but_first) do
        [context, rest] -> {normalize_context(context), rest}
        _ -> {nil, trimmed}
      end

    parts = String.split(rest, ~r/\s+-\s+/u)

    {location_parts, time} =
      case parts do
        [] -> {[], nil}
        [only] -> {[only], nil}
        many ->
          last = List.last(many)
          if time_like?(last), do: {Enum.drop(many, -1), last}, else: {many, nil}
      end

    %{
      raw: raw,
      context: context,
      locations: Enum.map(location_parts, &String.trim/1),
      location: Enum.join(location_parts, " - "),
      time: time,
      modifiers: []
    }
  end

  defp normalize_context(value), do: value |> String.upcase() |> String.replace(".", "")

  defp time_like?(value) do
    upper = String.upcase(String.trim(value))

    upper in ["DAY", "NIGHT", "MORNING", "AFTERNOON", "EVENING", "DAWN", "DUSK", "SUNSET", "SUNRISE", "LATER", "CONTINUOUS", "SAME"] or
      Regex.match?(~r/^\d{1,2}(?::\d{2})?\s*(?:AM|PM)$/u, upper)
  end
end
