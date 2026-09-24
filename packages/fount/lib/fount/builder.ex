defmodule Fount.Builder do
  @moduledoc "Pipeline-friendly structured screenplay builder. Generated source is reparsed through Fount's canonical Fountain path."

  alias Fount.Fragment

  defstruct title_page: [], fragments: [], newline: "\n"

  @type t :: %__MODULE__{title_page: [{String.t(), [String.t()]}], fragments: [Fragment.t() | binary()], newline: binary()}

  @spec new(keyword()) :: t()
  def new(opts \\ []), do: %__MODULE__{newline: Keyword.get(opts, :newline, "\n")}

  @spec title(t(), binary(), binary() | [binary()]) :: t()
  def title(%__MODULE__{} = builder, key, values) when is_binary(key) do
    normalized = values |> List.wrap() |> Enum.map(&to_string/1)
    %{builder | title_page: builder.title_page ++ [{String.trim(key), normalized}]}
  end

  @spec add(t(), Fragment.t() | binary() | [Fragment.t() | binary()]) :: t()
  def add(%__MODULE__{} = builder, items) do
    %{builder | fragments: builder.fragments ++ List.wrap(items)}
  end

  @spec scene(t(), binary(), [Fragment.t() | binary()], keyword()) :: t()
  def scene(%__MODULE__{} = builder, heading, content \\ [], opts \\ []) do
    add(builder, Fragment.scene(heading, content, Keyword.put_new(opts, :newline, builder.newline)))
  end

  @spec action(t(), binary(), keyword()) :: t()
  def action(%__MODULE__{} = builder, text, opts \\ []),
    do: add(builder, Fragment.action(text, Keyword.put_new(opts, :newline, builder.newline)))

  @spec dialogue(t(), binary(), binary() | [binary()], keyword()) :: t()
  def dialogue(%__MODULE__{} = builder, character, text, opts \\ []),
    do: add(builder, Fragment.dialogue(character, text, Keyword.put_new(opts, :newline, builder.newline)))

  @spec transition(t(), binary(), keyword()) :: t()
  def transition(%__MODULE__{} = builder, text, opts \\ []),
    do: add(builder, Fragment.transition(text, Keyword.put_new(opts, :newline, builder.newline)))

  @spec section(t(), binary(), pos_integer()) :: t()
  def section(%__MODULE__{} = builder, title, level \\ 1),
    do: add(builder, Fragment.section(title, level, newline: builder.newline))

  @spec synopsis(t(), binary()) :: t()
  def synopsis(%__MODULE__{} = builder, text), do: add(builder, Fragment.synopsis(text, newline: builder.newline))

  @spec note(t(), binary()) :: t()
  def note(%__MODULE__{} = builder, text), do: add(builder, Fragment.note(text, newline: builder.newline))

  @spec page_break(t()) :: t()
  def page_break(%__MODULE__{} = builder), do: add(builder, Fragment.page_break(newline: builder.newline))

  @spec to_fountain(t()) :: binary()
  def to_fountain(%__MODULE__{} = builder) do
    title = title_page_source(builder.title_page, builder.newline)
    body = builder.fragments |> Enum.map(&Fragment.source/1) |> IO.iodata_to_binary()

    cond do
      title == "" -> body
      body == "" -> title <> builder.newline
      true -> title <> builder.newline <> builder.newline <> body
    end
  end

  @spec to_document(t(), keyword()) :: {:ok, Fount.Document.t()} | {:error, term()}
  def to_document(%__MODULE__{} = builder, opts \\ []), do: builder |> to_fountain() |> Fount.parse(opts)

  defp title_page_source(entries, newline) do
    entries
    |> Enum.map(fn {key, values} ->
      case values do
        [] -> key <> ":"
        [value] -> key <> ": " <> value
        values -> [key <> ":" | Enum.map(values, &("   " <> &1))] |> Enum.join(newline)
      end
    end)
    |> Enum.join(newline)
  end
end
