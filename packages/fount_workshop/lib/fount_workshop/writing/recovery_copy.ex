defmodule FountWorkshop.Writing.RecoveryCopy do
  @moduledoc false
  alias FountWorkshop.{Candidate, Writing.Context}

  def propose(base, request, strategy, context, opts) do
    source = context.data["historical_source"]
    specs = source["scene_specs"] || []
    targets = request["options"]["source_targets"]

    with true <-
           (specs != [] and length(specs) == length(targets)) or
             {:error, :exact_recovery_requires_complete_scene_targets},
         true <-
           Enum.all?(specs, &is_nil(Fount.Query.scene(base, &1["id"]))) or
             {:error, :historical_identity_already_present},
         {:ok, operations} <- place(specs, request["options"]["destination"]) do
      group = %{
        "id" => "historical-copy",
        "title" => "Restore selected historical scenes",
        "reason" => "Explicit writer request for exact historical text, without adaptation",
        "depends_on" => [],
        "addresses_notes" => [],
        "evidence_ids" => Enum.map(context.evidence, & &1["evidence_id"]),
        "operations" => operations,
        "origin" => "writer_edit"
      }

      proposal = %{
        "version" => 1,
        "base_revision_id" => base.revision.id,
        "strategy_id" => strategy["id"],
        "summary" => strategy["title"],
        "groups" => [group],
        "inventions" => [],
        "unresolved_questions" => []
      }

      options =
        Context.compile_options(base, request, context, opts)
        |> Keyword.put(:writer_edit, true)
        |> Keyword.put(:strategy, strategy)
        |> Keyword.put(:lineage, [
          %{
            "operation" => "historical_copy",
            "source_revision_id" => source["revision_id"],
            "source_targets" => targets
          }
        ])

      with {:ok, candidate} <- Candidate.compile(base, proposal, options) do
        {:ok,
         put_in(candidate, ["provenance", "recovery"], %{
           "mode" => "exact_copy",
           "source_revision_id" => source["revision_id"],
           "generated_text" => false
         })}
      end
    end
  end

  defp place(scenes, %{"kind" => "replace_range", "scene_ids" => ids}) do
    {:ok, [%{"kind" => "replace_sequence", "value" => %{"scene_ids" => ids, "scenes" => scenes}}]}
  end

  defp place(scenes, %{"kind" => kind} = destination)
       when kind in ["start", "after_scene", "between_scenes"] do
    {ops, _} =
      Enum.map_reduce(scenes, destination["after_scene_id"], fn scene, after_id ->
        {%{
           "kind" => "insert_scene",
           "value" => %{"after_scene_id" => after_id, "scene" => scene}
         }, scene["id"]}
      end)

    {:ok, ops}
  end

  defp place(_, _), do: {:error, :exact_scene_recovery_requires_scene_destination}
end
