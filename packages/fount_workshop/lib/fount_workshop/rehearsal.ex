defmodule FountWorkshop.Rehearsal do
  @moduledoc "Noncanonical rehearsal exercises whose inventions stay out of generation context until explicit adoption."

  alias FountWorkshop.Store

  @kinds ~w(change_tactic reverse_status remove_participant shared_side private_conversation invented_backstory free)

  @doc "Records a rehearsal exercise in session progress only; it never changes screenplay canon."
  def add(session_id, exercise, services, opts \\ []) when is_binary(session_id) and is_map(exercise) do
    with :ok <- validate_exercise(exercise),
         {:ok, session} <- Store.call(services[:store], :session, [session_id]) do
      record = %{
        "id" => Fount.ID.v4(),
        "kind" => exercise["kind"],
        "prompt" => exercise["prompt"],
        "invented_claims" => Map.get(exercise, "invented_claims", []),
        "status" => "active",
        "canonical" => false,
        "created_by" => Keyword.get(opts, :actor, "writer"),
        "provenance" => %{
          "session_id" => session_id,
          "base_revision_id" => session["base_revision_id"],
          "source" => "rehearsal_exercise"
        }
      }

      update_records(session, services, fn records -> records ++ [record] end, record)
    end
  end

  def add(_, _, _, _), do: {:error, :invalid_rehearsal}

  @doc "Explicitly adopts one rehearsal as traceable project material eligible for later generation context."
  def adopt(session_id, rehearsal_id, services, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    note = Keyword.get(opts, :note, "Explicitly adopted from rehearsal")

    with :ok <- actor(actor),
         :ok <- text(note, :invalid_adoption_note),
         {:ok, session} <- Store.call(services[:store], :session, [session_id]),
         {:ok, updated, record} <- transition(session, rehearsal_id, "adopted", actor, note) do
      save_transition(updated, record, services)
    end
  end

  @doc "Rejects a rehearsal and keeps it outside canon and later generation context."
  def reject(session_id, rehearsal_id, services, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    note = Keyword.get(opts, :note, "Rejected rehearsal")

    with :ok <- actor(actor),
         :ok <- text(note, :invalid_rejection_note),
         {:ok, session} <- Store.call(services[:store], :session, [session_id]),
         {:ok, updated, record} <- transition(session, rehearsal_id, "rejected", actor, note) do
      save_transition(updated, record, services)
    end
  end

  @doc "Returns all recorded rehearsals, including rejected/adopted history."
  def list(session) when is_map(session), do: get_in(session, ["progress", "rehearsals"]) || []

  @doc "Returns only explicitly adopted rehearsal material for provider prompts."
  def generation_context(session) when is_map(session) do
    session
    |> list()
    |> Enum.filter(&(&1["status"] == "adopted"))
    |> Enum.map(fn record ->
      %{
        "id" => record["id"],
        "kind" => record["kind"],
        "prompt" => record["prompt"],
        "invented_claims" => record["invented_claims"],
        "adoption" => record["adoption"],
        "source" => "explicitly_adopted_rehearsal",
        "canonical" => false,
        "rule" => "Project material may inform exploration, but it is not a StoryWorld fact until separately established by canonical/source evidence."
      }
    end)
  end

  defp update_records(session, services, fun, record) do
    records = list(session)
    updated = put_in(session, ["progress", "rehearsals"], fun.(records))

    case Store.call(services[:store], :save_session, [updated]) do
      {:ok, _saved} -> {:ok, record}
      error -> error
    end
  end

  defp transition(session, id, status, actor, note) do
    records = list(session)

    case Enum.find_index(records, &(&1["id"] == id)) do
      nil ->
        {:error, :unknown_rehearsal}

      index ->
        current = Enum.at(records, index)

        if current["status"] != "active" do
          {:error, :rehearsal_already_decided}
        else
          decision = %{"actor" => actor, "note" => note, "status" => status}

          record =
            current
            |> Map.put("status", status)
            |> Map.put(if(status == "adopted", do: "adoption", else: "rejection"), decision)

          {:ok, put_in(session, ["progress", "rehearsals"], List.replace_at(records, index, record)), record}
        end
    end
  end

  defp save_transition(session, record, services) do
    case Store.call(services[:store], :save_session, [session]) do
      {:ok, _saved} -> {:ok, record}
      error -> error
    end
  end

  defp validate_exercise(exercise) do
    claims = Map.get(exercise, "invented_claims", [])

    cond do
      Map.keys(exercise) -- ~w(kind prompt invented_claims) != [] -> {:error, :unknown_rehearsal_field}
      exercise["kind"] not in @kinds -> {:error, :invalid_rehearsal_kind}
      not is_binary(exercise["prompt"]) or String.trim(exercise["prompt"]) == "" -> {:error, :invalid_rehearsal_prompt}
      not is_list(claims) or Enum.any?(claims, &(not is_binary(&1) or String.trim(&1) == "")) -> {:error, :invalid_rehearsal_claims}
      true -> :ok
    end
  end

  defp actor(value), do: text(value, :missing_actor)
  defp text(value, error) when is_binary(value) do
    if String.trim(value) == "", do: {:error, error}, else: :ok
  end

  defp text(_, error), do: {:error, error}
end
