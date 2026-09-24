defmodule Fount.Fragment do
  @moduledoc "Structured screenplay generation primitives that compile to canonical Fountain source."

  @enforce_keys [:source]
  defstruct [:source, :kind]

  @type t :: %__MODULE__{source: binary(), kind: atom() | nil}

  @spec raw(binary()) :: t()
  def raw(source) when is_binary(source), do: %__MODULE__{source: source, kind: :raw}

  @spec sequence([t() | binary()]) :: t()
  def sequence(items) do
    source = items |> Enum.map(&source/1) |> IO.iodata_to_binary()
    %__MODULE__{source: source, kind: :sequence}
  end

  @spec action(binary(), keyword()) :: t()
  def action(text, opts \\ []) when is_binary(text) do
    newline = newline(opts)
    force? = Keyword.get(opts, :force, false)
    prefix = if force?, do: "!", else: ""
    %__MODULE__{source: prefix <> normalize(text, newline) <> newline <> newline, kind: :action}
  end

  @spec dialogue(binary(), binary() | [binary()], keyword()) :: t()
  def dialogue(character, dialogue, opts \\ []) when is_binary(character) do
    newline = newline(opts)
    character = String.trim(character)
    force? = Keyword.get(opts, :force, String.upcase(character) != character)
    cue = if force?, do: "@" <> character, else: character

    extension =
      case Keyword.get(opts, :extension) do
        nil -> ""
        "" -> ""
        value -> " " <> ensure_parenthetical(to_string(value))
      end

    dual = if Keyword.get(opts, :dual, false), do: " ^", else: ""

    parentheticals =
      opts
      |> Keyword.get(:parenthetical, [])
      |> List.wrap()
      |> Enum.map_join("", fn value -> ensure_parenthetical(to_string(value)) <> newline end)

    lines =
      dialogue
      |> List.wrap()
      |> Enum.flat_map(&split_lines/1)
      |> drop_terminal_empty()
      |> Enum.map(fn
        "" -> "  "
        value -> value
      end)
      |> Enum.join(newline)

    %__MODULE__{
      source: cue <> extension <> dual <> newline <> parentheticals <> lines <> newline <> newline,
      kind: :dialogue
    }
  end

  @spec scene(binary(), [t() | binary()], keyword()) :: t()
  def scene(heading, content \\ [], opts \\ []) when is_binary(heading) do
    newline = newline(opts)
    heading = String.trim(heading)
    force? = Keyword.get(opts, :force, not Fount.SceneHeading.standard_fountain?(heading))
    prefix = if force?, do: ".", else: ""

    number =
      case Keyword.get(opts, :number) do
        nil -> ""
        "" -> ""
        value -> " ##{value}#"
      end

    body = content |> List.wrap() |> Enum.map(&source/1) |> IO.iodata_to_binary()
    source = prefix <> heading <> number <> newline <> newline <> body
    %__MODULE__{source: ensure_blank_terminated(source, newline), kind: :scene}
  end

  @spec transition(binary(), keyword()) :: t()
  def transition(text, opts \\ []) when is_binary(text) do
    newline = newline(opts)
    text = String.trim(text)
    standard? = String.upcase(text) == text and String.ends_with?(text, "TO:")
    force? = Keyword.get(opts, :force, not standard?)
    prefix = if force?, do: ">", else: ""
    %__MODULE__{source: prefix <> text <> newline <> newline, kind: :transition}
  end

  @spec section(binary(), pos_integer(), keyword()) :: t()
  def section(title, level \\ 1, opts \\ []) when is_binary(title) and is_integer(level) and level > 0 do
    newline = newline(opts)
    %__MODULE__{source: String.duplicate("#", level) <> " " <> String.trim(title) <> newline, kind: :section}
  end

  @spec synopsis(binary(), keyword()) :: t()
  def synopsis(text, opts \\ []) when is_binary(text),
    do: %__MODULE__{source: "= " <> String.trim(text) <> newline(opts), kind: :synopsis}

  @spec centered(binary(), keyword()) :: t()
  def centered(text, opts \\ []) when is_binary(text),
    do: %__MODULE__{source: ">" <> String.trim(text) <> "<" <> newline(opts) <> newline(opts), kind: :centered}

  @spec lyric(binary(), keyword()) :: t()
  def lyric(text, opts \\ []) when is_binary(text),
    do: %__MODULE__{source: "~" <> normalize(text, newline(opts)) <> newline(opts) <> newline(opts), kind: :lyric}

  @spec note(binary(), keyword()) :: t()
  def note(text, opts \\ []) when is_binary(text) do
    newline = newline(opts)
    %__MODULE__{source: "[[" <> normalize(text, newline) <> "]]" <> newline <> newline, kind: :note}
  end

  @spec boneyard(binary(), keyword()) :: t()
  def boneyard(text, opts \\ []) when is_binary(text) do
    newline = newline(opts)
    %__MODULE__{source: "/*" <> normalize(text, newline) <> "*/" <> newline <> newline, kind: :boneyard}
  end

  @spec page_break(keyword()) :: t()
  def page_break(opts \\ []), do: %__MODULE__{source: "===" <> newline(opts) <> newline(opts), kind: :page_break}

  @spec source(t() | binary()) :: binary()
  def source(%__MODULE__{source: source}), do: source
  def source(source) when is_binary(source), do: source

  defp newline(opts), do: Keyword.get(opts, :newline, "\n")

  defp normalize(value, newline) do
    value
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.replace("\n", newline)
  end

  defp split_lines(value) when is_binary(value) do
    value
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.split("\n", trim: false)
  end

  defp drop_terminal_empty(lines) do
    case Enum.reverse(lines) do
      ["" | rest] when rest != [] -> Enum.reverse(rest)
      _ -> lines
    end
  end

  defp ensure_parenthetical(value) do
    value = String.trim(value)
    if String.starts_with?(value, "(") and String.ends_with?(value, ")"), do: value, else: "(" <> value <> ")"
  end

  defp ensure_blank_terminated(source, newline) do
    cond do
      String.ends_with?(source, newline <> newline) -> source
      String.ends_with?(source, newline) -> source <> newline
      true -> source <> newline <> newline
    end
  end
end
