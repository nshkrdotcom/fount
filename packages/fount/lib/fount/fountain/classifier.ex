defmodule Fount.Fountain.Classifier do
  @moduledoc false

  alias Fount.Source.Line

  @scene_prefix ~r/^(?:INT|EXT|EST|I\/E|INT\.?\/EXT|EXT\.?\/INT)(?:\.|\s)/iu
  @title_key ~r/^[^:\r\n]+:\s*/u

  def safe_text(%Line{content: content}) do
    if String.valid?(content), do: content, else: ""
  end

  def trimmed(line), do: line |> safe_text() |> String.trim()
  def trim_leading(line), do: line |> safe_text() |> String.trim_leading()
  def empty?(%Line{} = line), do: Line.empty?(line)

  def title_key?(%Line{} = line), do: Regex.match?(@title_key, trim_leading(line))

  def page_break?(line), do: Regex.match?(~r/^={3,}$/u, trimmed(line))
  def section?(line), do: Regex.match?(~r/^#+(?:\s|$)/u, trimmed(line))
  def synopsis?(line), do: Regex.match?(~r/^=(?!=)(?:\s|$)/u, trimmed(line))
  def lyric?(line), do: String.starts_with?(trim_leading(line), "~")
  def forced_action?(line), do: String.starts_with?(trim_leading(line), "!")
  def forced_character?(line), do: String.starts_with?(trim_leading(line), "@") and byte_size(trim_leading(line)) > 1

  def forced_scene_heading?(line) do
    case trim_leading(line) do
      <<".", next::utf8, _::binary>> -> next != ?. and char_alnum?(next)
      _ -> false
    end
  rescue
    _ -> false
  end

  def centered?(line) do
    text = trimmed(line)
    String.starts_with?(text, ">") and String.ends_with?(text, "<") and byte_size(text) >= 2
  end

  def forced_transition?(line) do
    text = trim_leading(line)
    String.starts_with?(text, ">") and not centered?(line)
  end

  def standalone_note_start?(line), do: String.starts_with?(trimmed(line), "[[")
  def standalone_boneyard_start?(line), do: String.starts_with?(trimmed(line), "/*")

  def scene_heading?(line, previous, following) do
    text = trim_leading(line)
    automatic = Regex.match?(@scene_prefix, text) and empty_neighbor?(previous) and empty_neighbor?(following)
    forced_scene_heading?(line) or automatic
  rescue
    _ -> false
  end

  def transition?(line, previous, following) do
    text = trim_leading(line)

    cond do
      centered?(line) -> false
      forced_transition?(line) -> true
      not empty_neighbor?(previous) or not empty_neighbor?(following) -> false
      not uppercase?(text) -> false
      String.ends_with?(text, "TO:") -> true
      true -> false
    end
  end

  def character?(line, previous, following) do
    text = trim_leading(line)
    forced = forced_character?(line)
    body = if forced, do: binary_part(text, 1, byte_size(text) - 1), else: text
    body = body |> String.trim_trailing() |> String.trim_trailing("^") |> String.trim_trailing()
    name = body |> strip_character_extension() |> String.trim()

    forced or
      (empty_neighbor?(previous) and not empty_neighbor?(following) and uppercase?(body) and
         Regex.match?(~r/\p{L}/u, name))
  rescue
    _ -> false
  end

  def character_parts(line) do
    source = safe_text(line)
    leading = leading_bytes(source)
    text = binary_part(source, leading, byte_size(source) - leading)
    forced? = String.starts_with?(text, "@")
    marker = if forced?, do: 1, else: 0
    after_marker = binary_part(text, marker, byte_size(text) - marker)
    dual? = String.ends_with?(String.trim_trailing(after_marker), "^")

    without_dual =
      after_marker
      |> String.trim_trailing()
      |> then(fn value ->
        if dual? and byte_size(value) > 0,
          do: binary_part(value, 0, byte_size(value) - 1) |> String.trim_trailing(),
          else: value
      end)

    {name_raw, extension} = split_character_extension(without_dual)
    name = String.trim(name_raw)
    local = leading + marker + find_offset(after_marker, name)

    %{
      name: name,
      extension: extension,
      dual?: dual?,
      forced?: forced?,
      content_offset: local,
      content_bytes: byte_size(name)
    }
  end

  def scene_parts(line) do
    source = safe_text(line)
    leading = leading_bytes(source)
    text = binary_part(source, leading, byte_size(source) - leading)
    forced? = String.starts_with?(text, ".") and not String.starts_with?(text, "..")
    marker = if forced?, do: 1, else: 0
    body = binary_part(text, marker, byte_size(text) - marker)

    {heading_raw, number} =
      case Regex.run(~r/^(.*?)(?:\s+#([^#]+)#\s*)$/u, body, capture: :all_but_first) do
        [heading, number] -> {heading, String.trim(number)}
        _ -> {body, nil}
      end

    heading = String.trim(heading_raw)
    local = leading + marker + find_offset(body, heading)

    %{
      heading: heading,
      number: number,
      forced?: forced?,
      content_offset: local,
      content_bytes: byte_size(heading)
    }
  end

  def transition_parts(line) do
    source = safe_text(line)
    leading = leading_bytes(source)
    text = binary_part(source, leading, byte_size(source) - leading)
    forced? = String.starts_with?(text, ">")
    marker = if forced?, do: 1, else: 0
    body = binary_part(text, marker, byte_size(text) - marker)
    value = String.trim(body)
    local = leading + marker + find_offset(body, value)

    %{text: value, forced?: forced?, content_offset: local, content_bytes: byte_size(value)}
  end

  def section_parts(line) do
    source = safe_text(line)
    leading = leading_bytes(source)
    trimmed = String.trim(source)
    hashes = trimmed |> String.graphemes() |> Enum.take_while(&(&1 == "#")) |> length()
    after_hashes = binary_part(trimmed, hashes, byte_size(trimmed) - hashes)
    inner_leading = leading_bytes(after_hashes)
    title = String.trim(after_hashes)

    %{
      text: title,
      level: hashes,
      content_offset: leading + hashes + inner_leading,
      content_bytes: byte_size(title)
    }
  end

  def synopsis_parts(line) do
    source = safe_text(line)
    leading = leading_bytes(source)
    trimmed = String.trim(source)

    after_marker =
      if String.starts_with?(trimmed, "="), do: binary_part(trimmed, 1, byte_size(trimmed) - 1), else: trimmed

    inner_leading = leading_bytes(after_marker)
    text = String.trim(after_marker)

    %{
      text: text,
      content_offset: leading + if(String.starts_with?(trimmed, "="), do: 1, else: 0) + inner_leading,
      content_bytes: byte_size(text)
    }
  end

  def centered_parts(line) do
    source = safe_text(line)
    leading = leading_bytes(source)
    trimmed = String.trim(source)
    interior_bytes = max(byte_size(trimmed) - 2, 0)
    interior = if interior_bytes > 0, do: binary_part(trimmed, 1, interior_bytes), else: ""
    inner_leading = leading_bytes(interior)
    inner = String.trim(interior)

    %{
      text: inner,
      content_offset: leading + 1 + inner_leading,
      content_bytes: byte_size(inner)
    }
  end

  defp leading_bytes(source), do: byte_size(source) - byte_size(String.trim_leading(source))

  defp find_offset(_source, ""), do: 0

  defp find_offset(source, value) do
    case :binary.match(source, value) do
      {offset, _} -> offset
      :nomatch -> 0
    end
  end

  defp empty_neighbor?(nil), do: true
  defp empty_neighbor?(%Line{} = line), do: empty?(line)

  defp uppercase?(text) when text == "", do: false
  defp uppercase?(text), do: String.upcase(text) == text

  defp strip_character_extension(text), do: elem(split_character_extension(text), 0)

  defp split_character_extension(text) do
    case Regex.run(~r/^(.*?)(\s+\(.*\))$/u, text, capture: :all_but_first) do
      [name, extension] -> {name, String.trim(extension)}
      _ -> {text, nil}
    end
  end

  defp char_alnum?(codepoint) do
    <<codepoint::utf8>> =~ ~r/[\p{L}\p{N}]/u
  end
end
