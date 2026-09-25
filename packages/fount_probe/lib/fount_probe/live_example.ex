defmodule FountProbe.LiveExample do
  @moduledoc false
  alias Fount.LiveArtifacts, as: A

  def run(mode, output) do
    A.run(mode, output, fn directory ->
      repo = Fount.CLI.Support.connect() |> A.require!()
      {model, _} = A.fixture()
      key = "probe-#{mode}-#{Fount.ID.v4()}"
      Fount.Persistence.create(repo, key, model) |> A.require!()
      clients = FountProbe.Launcher.clients() |> A.require!()
      requests = requests(mode, model)

      FountProbe.CLI.validate_requests(model, requests)
      |> case do
        :ok -> :ok
        error -> A.require!(error)
      end

      budget = FountProbe.Budget.new(max_inference_calls: 40, max_jev_states: 1500)

      reports =
        FountProbe.execute(model, requests, clients,
          budget: budget,
          max_inference_calls: 40,
          max_jev_states: 1500,
          history_reader: fn sid, rid -> Fount.Persistence.load_revision(repo, sid, rid) end
        )
        |> A.require!()

      written = FountProbe.CLI.save(reports, repo, directory) |> A.require!()
      head = Fount.Persistence.load(repo, key) |> A.require!()

      if head.revision.id != model.revision.id,
        do: raise("An inspection changed the accepted screenplay")

      result = %{
        "key" => key,
        "screenplay_id" => model.id,
        "revision_id" => model.revision.id,
        "reports" => written,
        "spent" => FountProbe.Budget.snapshot(budget)
      }

      if Enum.any?(reports, &(&1.status != "complete")), do: throw({:live_failure, result})
      result
    end)
  end

  def requests("voice", model) do
    cast = [cast(model, "MARA"), cast(model, "DAN")]

    [
      %{
        "id" => "voice",
        "tool" => "voice",
        "params" => %{"character_ids" => cast, "selection" => whole()}
      }
    ]
  end

  def requests("knowledge_access", model) do
    records = Enum.at(model.ir.scenes, 2)
    queue = Enum.at(model.ir.scenes, 5)
    points = [end_point(model, records.id), end_point(model, queue.id)]

    [
      %{
        "id" => "knowledge",
        "tool" => "knowledge_trace",
        "params" => %{
          "proposition" => "Dan has confessed that he forged the ledger.",
          "subjects" => [
            %{"kind" => "reader"},
            %{"kind" => "audience"},
            %{"kind" => "character", "character_id" => cast(model, "MARA")}
          ],
          "points" => points,
          "access_mode" => "evidence",
          "suspicion" => true
        }
      },
      %{
        "id" => "reveal",
        "tool" => "locate_boundary",
        "params" => %{
          "scene_id" => records.id,
          "proposition" => "Dan has explicitly confessed to forging the ledger.",
          "projection" => "page_reader",
          "threshold" => 0.8
        }
      }
    ]
  end

  def requests("consequences", model) do
    transfer =
      Enum.find(model.ir.elements, &String.contains?(&1.text, "He puts the key in her hand."))

    [
      %{
        "id" => "dependencies",
        "tool" => "dependencies",
        "params" => %{
          "selection" => whole(),
          "targets" => [%{"kind" => "element", "id" => transfer.id}],
          "include_alternative_support" => true
        }
      },
      %{
        "id" => "continuity",
        "tool" => "continuity",
        "params" => %{"selection" => whole(), "subjects" => ["brass key", "ledger"]}
      }
    ]
  end

  def requests("tools", model) do
    first = hd(model.ir.scenes)
    selection = %{"targets" => [%{"kind" => "scene", "id" => first.id}]}

    [
      %{
        "id" => "inventory",
        "tool" => "inventory",
        "params" => %{"selection" => whole(), "include_summaries" => true}
      },
      %{
        "id" => "search",
        "tool" => "search",
        "params" => %{
          "query" => "a character avoids the accusation by doing a task",
          "selection" => whole(),
          "mode" => "inspect_all"
        }
      },
      %{
        "id" => "mechanics",
        "tool" => "scene_mechanics",
        "params" => %{"selection" => selection, "include_tactics" => true}
      },
      %{
        "id" => "dialogue",
        "tool" => "dialogue",
        "params" => %{"selection" => selection, "lenses" => ~w(subtext repetition responsiveness)}
      },
      %{"id" => "action", "tool" => "action", "params" => %{"selection" => selection}}
    ]
  end

  def requests(_, _), do: raise(ArgumentError, "Unknown real Probe mode")

  def end_point(model, id) do
    model |> FountProbe.Projection.points(id) |> A.require!() |> List.last()
  end

  defp cast(model, name),
    do:
      Enum.find_value(model.cast, fn {id, c} -> if c.display_name == name, do: id end) ||
        raise("Fixture cast not found")

  defp whole, do: %{"whole_screenplay" => true}
end
