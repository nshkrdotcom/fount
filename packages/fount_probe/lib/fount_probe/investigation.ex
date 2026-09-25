defmodule FountProbe.Investigation do
  @moduledoc "Finite, screenplay-specific investigation plans and evidence-backed hypothesis revision. Does not execute model-supplied code."
  alias FountProbe.{Report, Projection, Catalog, Completion}

  def plan(model, concern, clients, opts \\ []) do
    with true <- (is_binary(concern) and String.trim(concern) != "") or {:error, :empty_concern},
         {:ok, units} <-
           Projection.select(model, Keyword.get(opts, :selection, %{"whole_screenplay" => true})) do
      schema = %{
        "type" => "object",
        "properties" => %{
          "hypotheses" => strings(),
          "requests" => %{
            "type" => "array",
            "minItems" => 1,
            "maxItems" => 6,
            "items" => %{
              "type" => "object",
              "properties" => %{
                "id" => %{"type" => "string"},
                "tool" => %{"enum" => Catalog.names()},
                "params" => %{"type" => "object"}
              },
              "required" => ~w(id tool params),
              "additionalProperties" => false
            }
          }
        },
        "required" => ~w(hypotheses requests),
        "additionalProperties" => false
      }

      validate = fn object ->
        with :ok <- Fount.Writing.Schema.validate(schema, object),
             true <-
               length(Enum.uniq_by(object["requests"], & &1["id"])) == length(object["requests"]) or
                 {:error, :duplicate_request_id} do
          Enum.reduce_while(object["requests"], :ok, fn request, :ok ->
            case Catalog.validate(model, request["tool"], request["params"]) do
              :ok -> {:cont, :ok}
              error -> {:halt, error}
            end
          end)
        end
      end

      prompt =
        "Investigate this writer's specific creative question, not whether every scene follows a formula. Form tentative competing hypotheses and choose only needed catalog tools. Requests are inspections, never edits. Exact IDs below are authoritative.\n" <>
          Jason.encode!(%{
            "concern" => concern,
            "material" => units,
            "tools" => Catalog.tools(),
            "cast" => Fount.Screenplay.Model.plain(Map.values(model.cast))
          })

      with {:ok, value, traces} <-
             Completion.complete(clients[:inference], prompt, schema, validate, opts) do
        {:ok,
         Report.new(model, "investigation_plan", %{"concern" => concern}, %{
           data: value,
           evidence: Projection.evidence(units),
           provenance: %{"completions" => traces}
         })}
      end
    end
  end

  def explain(model, concern, reports, clients, opts \\ []) do
    evidence = reports |> Enum.flat_map(& &1.evidence) |> Enum.uniq_by(& &1["evidence_id"])
    ids = Enum.map(evidence, & &1["evidence_id"])

    schema = %{
      "type" => "object",
      "properties" => %{
        "answer" => %{"type" => "string"},
        "revised_hypotheses" => strings(),
        "uncertainties" => strings(),
        "evidence_ids" => strings(),
        "strategies" => %{
          "type" => "array",
          "minItems" => 3,
          "maxItems" => 3,
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "title" => %{"type" => "string"},
              "dramatic_mechanism" => %{"type" => "string"},
              "beats" => strings(),
              "evidence_ids" => strings()
            },
            "required" => ~w(id title dramatic_mechanism beats evidence_ids),
            "additionalProperties" => false
          }
        }
      },
      "required" => ~w(answer revised_hypotheses uncertainties evidence_ids strategies),
      "additionalProperties" => false
    }

    validate = fn object ->
      with :ok <- Fount.Writing.Schema.validate(schema, object),
           true <-
             length(Enum.uniq_by(object["strategies"], & &1["id"])) == 3 or
               {:error, :duplicate_strategy_id},
           true <-
             Enum.all?(
               object["evidence_ids"] ++ Enum.flat_map(object["strategies"], & &1["evidence_ids"]),
               &(&1 in ids)
             ) or {:error, :uninspected_evidence} do
        :ok
      end
    end

    payload = %{
      "concern" => concern,
      "initial_hypotheses" => Keyword.get(opts, :hypotheses, []),
      "reports" => Enum.map(reports, &Report.to_map/1)
    }

    prompt =
      "Answer the creative question using the actual reports. Revise hypotheses that the evidence contradicts. Missing results are unknown. Cite exact registry IDs; distinguish model interpretation from established text. Offer exactly three genuinely contrasting writing remedies with causal beats, no ranking or universal quality score. Do not claim any pages have been rewritten yet.\n" <>
        Jason.encode!(payload)

    with {:ok, value, traces} <-
           Completion.complete(clients[:inference], prompt, schema, validate, opts) do
      {:ok,
       Report.new(model, "investigation_explanation", %{"concern" => concern}, %{
         status:
           if(Enum.all?(reports, &(&1.status == "complete")), do: "complete", else: "partial"),
         data: value,
         evidence: evidence,
         provenance: %{"completions" => traces},
         source_revision_ids: reports |> Enum.flat_map(& &1.source_revision_ids) |> Enum.uniq()
       })}
    end
  end

  defp strings, do: %{"type" => "array", "items" => %{"type" => "string"}}
end
