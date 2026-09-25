defmodule Fount.Interchange do
  @moduledoc "Explicit interchange fidelity. Only Fount canonical JSON carries revision-scoped authoring identity."
  def read(bytes, format, opts \\ [])
  def read(bytes, "fountain", opts) do
    with {:ok, doc} <- Fount.parse(bytes, opts) do
      {:ok, Fount.Screenplay.from_document(doc, Keyword.take(opts, [:cast_resolution])), []}
    end
  end
  def read(bytes, "fdx", opts), do: Fount.Screenplay.from_fdx(bytes, opts)
  def read(bytes, "json", _opts) do
    with {:ok, model} <- Fount.Adapter.JSON.decode_model(bytes), do: {:ok, model, []}
  end
  def read(_, _, _), do: {:error, :unsupported_import_format}
  def write(model, format, opts \\ [])
  def write(model, "json", opts), do: Fount.Adapter.JSON.export(model, opts)
  def write(model, "fountain", opts) do
    with {:ok, result} <- Fount.Screenplay.export_fountain(model, opts) do
      {:ok, %{result | losses: Enum.uniq(result.losses ++ identity_losses(model)), metadata: %{fidelity: "screenplay_text_not_authoring_database"}}}
    end
  end
  def write(model, "fdx", _opts) do
    with {:ok, result} <- Fount.Screenplay.to_fdx(model) do
      {:ok, %{result | losses: Enum.uniq(result.losses ++ identity_losses(model)), metadata: %{fidelity: "supported_final_draft_subset"}}}
    end
  end
  def write(_, _, _), do: {:error, :unsupported_export_format}
  def matrix do
    %{"fountain" => %{"unchanged_import_bytes" => "preserved", "edited_text" => "canonical_regeneration", "stable_ids" => false, "authored_items" => false, "revision_history" => false},
      "fdx" => %{"unchanged_import_bytes" => "preserved", "edited_text" => "supported_subset_with_losses", "stable_ids" => false, "authored_items" => false, "production_roundtrip" => "not_claimed"},
      "json" => %{"schema" => "fount.screenplay.v2", "stable_ids" => true, "cast_mentions" => true, "authored_items" => true, "revision_snapshot" => true, "full_history" => false, "source_bytes" => "opt_in"}}
  end
  defp identity_losses(model) do
    ["Fount UUIDs, revision lineage and exact evidence identities are not encoded in this text format"] ++
      if(map_size(model.authored_items) > 0, do: ["Writer-authored items remain in PostgreSQL or canonical JSON; they are not flattened into screenplay pages"], else: []) ++
      if(map_size(model.cast) > 0, do: ["Confirmed cast and mention identities become literal screenplay text"], else: [])
  end
end
