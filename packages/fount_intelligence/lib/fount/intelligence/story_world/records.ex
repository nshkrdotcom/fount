defmodule Fount.Intelligence.StoryWorld.Records do
  @moduledoc "Pure validation of proposed story records against an explicit inspected evidence registry. No acquisition or truth promotion."
  alias Fount.Writing.Schema
  @kinds ~w(events propositions goals knowledge_access props commitments relationships timeline)
  @schema %{
    "type" => "object",
    "additionalProperties" => false,
    "required" => ["summary", "records"],
    "properties" => %{
      "summary" => %{"type" => "string"},
      "records" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ~w(id kind claim subjects evidence_ids uncertainty),
          "properties" => %{
            "id" => %{"type" => "string"},
            "kind" => %{"enum" => @kinds},
            "claim" => %{"type" => "string"},
            "subjects" => %{"type" => "array", "items" => %{"type" => "string"}},
            "evidence_ids" => %{
              "type" => "array",
              "minItems" => 1,
              "items" => %{"type" => "string"}
            },
            "uncertainty" => %{"type" => "string"}
          }
        }
      }
    }
  }

  def kinds, do: @kinds
  def schema, do: @schema

  def validate(object, units, kinds) do
    registry = Map.new(units, &{&1["evidence_id"], &1})

    with :ok <- Schema.validate(@schema, object),
         :ok <- validate_kinds(object["records"], kinds),
         :ok <- validate_evidence(object["records"], registry) do
      validate_ids(object["records"])
    end
  end

  defp validate_kinds(records, kinds) do
    invalid = records |> Enum.map(& &1["kind"]) |> Enum.reject(&(&1 in kinds)) |> Enum.uniq()
    if invalid == [], do: :ok, else: {:error, {:unrequested_extraction_kinds, invalid}}
  end

  defp validate_evidence(records, registry) do
    invalid =
      records
      |> Enum.flat_map(& &1["evidence_ids"])
      |> Enum.reject(&Map.has_key?(registry, &1))
      |> Enum.uniq()

    if invalid == [], do: :ok, else: {:error, {:uninspected_evidence_ids, invalid}}
  end

  defp validate_ids(records) do
    ids = Enum.map(records, & &1["id"])
    duplicates = ids -- Enum.uniq(ids)

    if duplicates == [],
      do: :ok,
      else: {:error, {:duplicate_extraction_ids, Enum.uniq(duplicates)}}
  end
end
