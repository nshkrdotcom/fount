defmodule Fount.Intelligence.Acquisition.DiagnosticMeasurements do
  @moduledoc "Closed Phase-5 logical measurement registry. Data selects IDs, never executable modules."

  alias Fount.Observe.Question

  @base "diagnosis.concern_relevance"
  @support "diagnosis.evidence_support"

  def ids, do: [@base, @support]

  def base do
    %{
      "id" => @base,
      "lens_id" => @base,
      "questions" => [relevant: Question.noul("Does this evidence bear on the writer concern?")]
    }
  end

  def support do
    %{
      "id" => @support,
      "lens_id" => @support,
      "questions" => [
        support: Question.noul("Does the supplied screenplay evidence support the hypothesis?"),
        counterevidence:
          Question.noul(
            "Does the supplied screenplay evidence materially contradict the hypothesis?"
          )
      ]
    }
  end

  def fetch(@base), do: {:ok, base()}
  def fetch(@support), do: {:ok, support()}
  def fetch(_), do: {:error, :unknown_diagnostic_measurement}
end
