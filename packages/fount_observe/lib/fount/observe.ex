defmodule Fount.Observe do
  @moduledoc "Atomic, source-bound screenplay measurements. Interpretations and creative changes belong to higher layers."
  alias Fount.Observe.{Batch, Error, Provider, Question, Request, Resources}
  alias Fount.Observe.Executor
  alias Fount.Observe.Providers.SystemOne

  @spec evaluate(
          Provider.t() | nil,
          [Request.t()],
          [{atom() | String.t(), Question.t()}],
          keyword()
        ) :: {:ok, Batch.t()} | {:error, Error.t()}
  def evaluate(provider, requests, questions, opts \\ []),
    do: Executor.evaluate(provider, requests, questions, opts)

  @doc "Estimates semantic work without calling a provider, cache or budget."
  def preflight(requests, questions, opts \\ []),
    do: Resources.preflight(requests, questions, opts)

  def provider(opts \\ []), do: SystemOne.new(opts)
end
