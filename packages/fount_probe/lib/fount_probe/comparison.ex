defmodule FountProbe.Comparison do
  @moduledoc "Comparison and removal experiments return actual immutable model values, not accepted changes."
  alias Fount.Screenplay.Model
  alias FountProbe.Constraints
  alias FountProbe.KnowledgeTrace
  alias FountProbe.Projection
  alias FountProbe.Report

  def compare(model, params, clients, opts \\ []) do
    with {:ok, before} <- read(model, params["before_revision_id"], opts),
         {:ok, after_model} <- read(model, params["after_revision_id"], opts),
         {:ok, check} <-
           Constraints.run(
             after_model,
             %{"constraints" => params["constraints"]},
             clients,
             Keyword.put(opts, :base_model, before)
           ),
         {:ok, a} <- Projection.select(before, %{"whole_screenplay" => true}),
         {:ok, b} <- Projection.select(after_model, %{"whole_screenplay" => true}) do
      {:ok,
       Report.new(after_model, "compare", params, %{
         status: check.status,
         source_revision_ids: Enum.uniq([before.revision.id, after_model.revision.id]),
         data: %{
           "before_revision_id" => before.revision.id,
           "after_revision_id" => after_model.revision.id,
           "structural_diff" => Model.plain(Fount.Screenplay.diff(before, after_model)),
           "source_diff" =>
             Model.plain(
               String.myers_difference(
                 Fount.Screenplay.to_fountain(before),
                 Fount.Screenplay.to_fountain(after_model)
               )
             ),
           "checks" => check.data["checks"],
           "page_savings" => nil
         },
         evidence:
           Enum.uniq_by(Projection.evidence(a ++ b) ++ check.evidence, & &1["evidence_id"]),
         provenance: check.provenance,
         errors: check.errors
       })}
    end
  end

  def scene_lift(model, params, clients, opts \\ []) do
    ops =
      Enum.map(
        params["scene_ids"],
        &%{"kind" => "delete_scene", "target" => %{"kind" => "scene", "id" => &1}}
      )

    with {:ok, experimental, _} <- Fount.Screenplay.apply(model, ops, []),
         {:ok, result} <-
           compare(
             model,
             %{
               "before_revision_id" => model.revision.id,
               "after_revision_id" => experimental.revision.id,
               "constraints" => params["constraints"]
             },
             clients,
             Keyword.put(opts, :models, [model, experimental])
           ) do
      {:ok,
       %{
         result
         | tool: "scene_lift",
           request: params,
           transient_models: [experimental],
           data:
             Map.merge(result.data, %{
               "removed_scene_ids" => params["scene_ids"],
               "experiment_only" => true
             })
       }}
    end
  end

  def ablate(model, params, clients, opts \\ []) do
    subject =
      case params["projection"] do
        "page_reader" -> %{"kind" => "reader"}
        "audience_estimate" -> %{"kind" => "audience"}
        "character_access" -> %{"kind" => "character", "character_id" => params["character_id"]}
      end

    query = %{
      "proposition" => params["proposition"],
      "points" => [params["point"]],
      "subjects" => [subject]
    }

    with {:ok, baseline} <- KnowledgeTrace.run(model, query, clients, opts) do
      runs = Enum.map(params["groups"], &ablation_run(model, &1, params, query, clients, opts))

      {:ok, ablation_report(model, params, baseline, runs)}
    end
  end

  defp ablation_report(model, params, baseline, runs) do
    reports = [
      baseline | Enum.flat_map(runs, fn x -> if x.report, do: [x.report], else: [] end)
    ]

    models = Enum.flat_map(runs, fn x -> if x.model, do: [x.model], else: [] end)

    rows =
      Enum.map(runs, fn x ->
        %{
          "group_id" => x.id,
          "status" => if(x.report, do: x.report.status, else: "unresolved"),
          "revision_id" => x.model && x.model.revision.id,
          "before" => baseline.data,
          "after" => x.report && x.report.data,
          "error" => x.error
        }
      end)

    Report.new(model, "ablate", params, %{
      status:
        if(Enum.all?(runs, &(&1.report && &1.report.status == "complete")),
          do: "complete",
          else: "partial"
        ),
      source_revision_ids: [model.revision.id | Enum.map(models, & &1.revision.id)],
      transient_models: models,
      data: %{"experiments" => rows, "causal_proof" => false},
      evidence: reports |> Enum.flat_map(& &1.evidence) |> Enum.uniq_by(& &1["evidence_id"]),
      provenance: %{"experiments" => Enum.map(reports, & &1.provenance)}
    })
  end

  defp ablation_run(model, group, params, query, clients, opts) do
    with {:ok, ops} <- deletion_ops(group["targets"]),
         {:ok, changed, _} <- Fount.Screenplay.apply(model, ops, []),
         {:ok, _} <- Projection.cutoff(changed, params["point"]),
         {:ok, report} <- KnowledgeTrace.run(changed, query, clients, opts) do
      %{id: group["id"], model: changed, report: report, error: nil}
    else
      reason -> %{id: group["id"], model: nil, report: nil, error: inspect(reason, limit: 20)}
    end
  end

  defp deletion_ops(targets) when is_list(targets) and targets != [] do
    Enum.reduce_while(targets, {:ok, []}, fn t, {:ok, ops} ->
      case t do
        %{"kind" => "scene", "id" => _} ->
          {:cont, {:ok, ops ++ [%{"kind" => "delete_scene", "target" => t}]}}

        %{"kind" => "element", "id" => id} when not is_map_key(t, "span") ->
          {:cont, {:ok, ops ++ [%{"kind" => "delete_elements", "value" => %{"ids" => [id]}}]}}

        _ ->
          {:halt, {:error, :ablation_requires_whole_scene_or_element}}
      end
    end)
  end

  defp deletion_ops(_), do: {:error, :empty_ablation_group}

  defp read(model, id, opts) do
    case Enum.find(
           [model | Keyword.get(opts, :models, [])],
           &(&1.id == model.id and &1.revision.id == id)
         ) do
      nil ->
        case Keyword.get(opts, :history_reader) do
          reader when is_function(reader, 2) -> reader.(model.id, id)
          _ -> {:error, {:unavailable_revision, id}}
        end

      found ->
        {:ok, found}
    end
  end
end
