defmodule Fount.Store do
  @moduledoc "Persistence behavior and dispatch facade."

  alias Fount.Document

  @callback save(struct(), String.t(), Document.t(), keyword()) :: :ok | {:error, term()}
  @callback load(struct(), String.t(), keyword()) :: {:ok, Document.t()} | {:error, term()}
  @callback list(struct(), keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback delete(struct(), String.t(), keyword()) :: :ok | {:error, term()}

  def save(store, key, doc, opts \\ []), do: adapter(store).save(store, key, doc, opts)
  def load(store, key, opts \\ []), do: adapter(store).load(store, key, opts)
  def list(store, opts \\ []), do: adapter(store).list(store, opts)
  def delete(store, key, opts \\ []), do: adapter(store).delete(store, key, opts)

  defp adapter(%module{}), do: module
end
