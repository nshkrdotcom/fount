defmodule Fount.SceneHeading do
  @moduledoc "Conservative semantic decomposition of a scene heading. Raw heading text remains authoritative."

  @time_terms [
    "DAY",
    "NIGHT",
    "MORNING",
    "AFTERNOON",
    "EVENING",
    "DAWN",
    "DUSK",
    "SUNSET",
    "SUNRISE",
    "EARLY MORNING",
    "LATE MORNING",
    "LATE AFTERNOON",
    "LATE NIGHT",
    "PREDAWN"
  ]

  @relative_terms ["LATER", "CONTINUOUS", "SAME", "MOMENTS LATER", "SAME NIGHT", "LATER THAT NIGHT"]

  @doc "True when a heading is recognized by Fountain without the forced `.` marker."
  @spec standard_fountain?(binary()) :: boolean()
  def standard_fountain?(heading) when is_binary(heading) do
    Regex.match?(~r/^(?:INT|EXT|EST|I\/E|INT\.?\/EXT|EXT\.?\/INT)(?:\.|\s)/iu, String.trim(heading))
  end

  @spec parse(binary(), keyword()) :: map()
  def parse(raw, opts \\ []) when is_binary(raw) do
    trimmed = String.trim(raw)
    time_terms = terms(opts, :time_terms, @time_terms)
    relative_terms = terms(opts, :relative_time_terms, @relative_terms)
    {context, rest} = context_and_body(trimmed)
    parts = split_location_parts(rest)

    {location_parts, terminal} = terminal_parts(parts, time_terms, relative_terms)
    parent_place = List.first(location_parts)
    subplaces = Enum.drop(location_parts, 1)

    %{
      raw: raw,
      context: context,
      locations: location_parts,
      location: Enum.join(location_parts, " - "),
      parent_place: parent_place,
      subplace: if(subplaces == [], do: nil, else: Enum.join(subplaces, " - ")),
      subplaces: subplaces,
      geography: nil,
      time: terminal.time,
      time_of_day: terminal.time_of_day,
      date_or_era: terminal.date_or_era,
      relative_time: terminal.relative_time,
      modifiers: terminal.modifiers,
      unknown_modifiers: terminal.unknown_modifiers
    }
  end

  defp terms(opts, key, defaults) do
    configured = Keyword.get(opts, key, defaults)
    extras = Keyword.get(opts, :extra_time_terms, [])

    (configured ++ if(key == :time_terms, do: extras, else: []))
    |> Enum.map(&normalize_term/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp context_and_body(trimmed) do
    case Regex.run(
           ~r/^(INT\.?\/EXT\.?|EXT\.?\/INT\.?|INT\.?|EXT\.?|EST\.?|I\/E\.?)\s*(.*)$/iu,
           trimmed,
           capture: :all_but_first
         ) do
      [context, rest] when rest != "" -> {normalize_context(context), String.trim(rest)}
      _ -> {nil, trimmed}
    end
  end

  defp terminal_parts([], _time_terms, _relative_terms), do: {[], empty_terminal()}

  defp terminal_parts(parts, time_terms, relative_terms) do
    last = List.last(parts)
    prefix = Enum.drop(parts, -1)

    case parse_terminal(last, time_terms, relative_terms) do
      %{location_fragment: nil} = terminal ->
        {prefix, Map.delete(terminal, :location_fragment)}

      %{location_fragment: fragment} = terminal ->
        {prefix ++ [fragment], Map.delete(terminal, :location_fragment)}
    end
  end

  defp parse_terminal(value, time_terms, relative_terms) do
    {base, paren} = trailing_parenthetical(value)
    base = String.trim(base)
    upper = normalize_term(base)

    cond do
      time_like?(upper, time_terms, relative_terms) ->
        terminal_for_time(base, upper, paren, time_terms, relative_terms)

      paren != nil ->
        terminal = classify_parenthetical(paren)

        Map.merge(empty_terminal(), terminal)
        |> Map.put(:location_fragment, base)

      true ->
        Map.put(empty_terminal(), :location_fragment, String.trim(value))
    end
  end

  defp terminal_for_time(base, upper, paren, time_terms, relative_terms) do
    relative? = upper in relative_terms
    time_of_day = time_of_day(upper, time_terms)
    paren_fields = if paren, do: classify_parenthetical(paren), else: %{}

    empty_terminal()
    |> Map.merge(paren_fields)
    |> Map.put(:location_fragment, nil)
    |> Map.put(:time, base)
    |> Map.put(:time_of_day, time_of_day)
    |> Map.put(:relative_time, if(relative?, do: base, else: Map.get(paren_fields, :relative_time)))
    |> Map.update!(:modifiers, fn modifiers -> if(paren, do: Enum.uniq(modifiers ++ [paren]), else: modifiers) end)
  end

  defp time_of_day(upper, time_terms) do
    cond do
      upper in time_terms -> upper
      Regex.match?(~r/\bNIGHT\b/u, upper) -> "NIGHT"
      Regex.match?(~r/\bMORNING\b/u, upper) -> "MORNING"
      Regex.match?(~r/\bAFTERNOON\b/u, upper) -> "AFTERNOON"
      Regex.match?(~r/\bEVENING\b/u, upper) -> "EVENING"
      Regex.match?(~r/\b(?:DAWN|SUNRISE|PREDAWN)\b/iu, upper) -> upper
      Regex.match?(~r/\b(?:DUSK|SUNSET)\b/u, upper) -> upper
      Regex.match?(~r/^\d{1,2}(?::\d{2})?\s*(?:AM|PM)$/u, upper) -> upper
      true -> nil
    end
  end

  defp classify_parenthetical(value) do
    trimmed = String.trim(value)
    upper = normalize_term(trimmed)

    cond do
      relative_modifier?(upper) ->
        %{date_or_era: nil, relative_time: trimmed, modifiers: [trimmed], unknown_modifiers: []}

      date_or_era?(upper) ->
        %{date_or_era: trimmed, relative_time: nil, modifiers: [trimmed], unknown_modifiers: []}

      true ->
        %{date_or_era: nil, relative_time: nil, modifiers: [trimmed], unknown_modifiers: [trimmed]}
    end
  end

  defp date_or_era?(upper) do
    Regex.match?(~r/^(?:\d{4}|\d{2}s|\d{4}s|SPRING|SUMMER|FALL|AUTUMN|WINTER)(?:\s+.+)?$/u, upper) or
      Regex.match?(~r/\b(?:BCE|BC|CE|AD)\b/u, upper)
  end

  defp relative_modifier?(upper) do
    Regex.match?(~r/\b(?:LATER|EARLIER|BEFORE|AFTER|AGO|NEXT|PREVIOUS|SAME)\b/u, upper)
  end

  defp trailing_parenthetical(value) do
    case Regex.run(~r/^(.*?)(?:\s*)\(([^()]*)\)\s*$/u, value, capture: :all_but_first) do
      [base, modifier] when modifier != "" -> {base, modifier}
      _ -> {value, nil}
    end
  end

  defp split_location_parts(value) do
    value
    |> String.graphemes()
    |> do_split_parts(0, "", [])
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp do_split_parts([], _depth, current, acc), do: Enum.reverse([current | acc])

  defp do_split_parts(["(" | rest], depth, current, acc),
    do: do_split_parts(rest, depth + 1, current <> "(", acc)

  defp do_split_parts([")" | rest], depth, current, acc),
    do: do_split_parts(rest, max(depth - 1, 0), current <> ")", acc)

  defp do_split_parts([" ", "-", " " | rest], 0, current, acc),
    do: do_split_parts(rest, 0, "", [current | acc])

  defp do_split_parts([grapheme | rest], depth, current, acc),
    do: do_split_parts(rest, depth, current <> grapheme, acc)

  defp empty_terminal do
    %{
      time: nil,
      time_of_day: nil,
      date_or_era: nil,
      relative_time: nil,
      modifiers: [],
      unknown_modifiers: []
    }
  end

  defp normalize_context(value), do: value |> String.upcase() |> String.replace(".", "")
  defp normalize_term(value), do: value |> to_string() |> String.trim() |> String.upcase()

  defp time_like?(upper, time_terms, relative_terms) do
    upper in time_terms or upper in relative_terms or
      Regex.match?(~r/^\d{1,2}(?::\d{2})?\s*(?:AM|PM)$/u, upper)
  end
end
