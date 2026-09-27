defmodule Fount.Observe do
  @moduledoc "Atomic, source-bound screenplay measurements. Interpretations and creative changes belong to higher layers."
  alias Fount.Observe.{Batch, Error, Provider, Question, Request}
  @spec evaluate(Provider.t() | nil, [Request.t()], [{atom() | String.t(), Question.t()}], keyword()) :: {:ok, Batch.t()} | {:error, Error.t()}
  def evaluate(provider, requests, questions, opts \\ []), do: Fount.Observe.Executor.evaluate(provider, requests, questions, opts)
  def provider(opts \\ []), do: Fount.Observe.Providers.SystemOne.new(opts)
end
