defmodule Fount.Persistence.JSONValue do
  @moduledoc false
  use Ecto.Type
  def type, do: :map
  def cast(value) when is_map(value) or is_list(value), do: {:ok, value}
  def cast(_), do: :error
  def load(value), do: cast(value)
  def dump(value), do: cast(value)
end
