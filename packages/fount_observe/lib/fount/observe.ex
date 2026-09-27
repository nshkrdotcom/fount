defmodule Fount.Observe do
  @moduledoc "Atomic, source-bound screenplay measurements. Interpretations and creative changes belong to higher layers."
  alias Fount.Observe.{Batch, DeclarativeLens, Error, Provider, Question, Request, Resources}
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

  @doc "Validates a data-only project/studio lens declaration without registering executable code."
  def validate_declarative_lens(declaration), do: DeclarativeLens.validate(declaration)

  @doc "Previews the exact generic Observe question/lens contract produced by a declarative lens."
  def preview_declarative_lens(declaration), do: DeclarativeLens.preview(declaration)

  @doc "Compiles a validated declaration to normal Observe questions plus a caller-supplied lens asset."
  def compile_declarative_lens(declaration), do: DeclarativeLens.compile(declaration)

  @doc "Returns an empty caller-owned declarative-lens catalog; installation never enables assets implicitly."
  def new_declarative_lens_catalog, do: %{}

  def install_declarative_lens(catalog, declaration),
    do: DeclarativeLens.install(catalog, declaration)

  def enable_declarative_lens(catalog, id), do: DeclarativeLens.enable(catalog, id)
  def disable_declarative_lens(catalog, id), do: DeclarativeLens.disable(catalog, id)
  def fetch_declarative_lens(catalog, id), do: DeclarativeLens.fetch(catalog, id)
end
