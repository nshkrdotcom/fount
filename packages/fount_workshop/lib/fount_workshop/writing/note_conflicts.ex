defmodule FountWorkshop.Writing.NoteConflicts do
  @moduledoc false
  alias FountProbe.Projection

  def detect(model, notes) do
    for {a, i} <- Enum.with_index(notes),
        {b, j} <- Enum.with_index(notes),
        i < j,
        overlapping?(model, a["target"], b["target"]) do
      %{
        "note_ids" => [a["id"], b["id"]],
        "status" => "potential_conflict",
        "instructions" => [a["value"], b["value"]]
      }
    end
  end

  defp overlapping?(_, nil, _), do: false
  defp overlapping?(_, _, nil), do: false

  defp overlapping?(model, a, b) do
    with {:ok, left} <- Projection.target_ids(model, a),
         {:ok, right} <- Projection.target_ids(model, b) do
      MapSet.disjoint?(MapSet.new(left), MapSet.new(right)) == false
    else
      _ -> a == b
    end
  end
end
