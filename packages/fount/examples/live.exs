argv = case System.argv() do ["--" | rest] -> rest; other -> other end
{opts, [], []} = OptionParser.parse(argv, strict: [mode: :string, out: :string])
mode = opts[:mode] || raise "--mode roundtrip or database is required"
out = Path.expand(opts[:out] || System.get_env("FOUNT_EXAMPLE_OUT") || "examples/output")
File.mkdir_p!(out)

fixture = Application.app_dir(:fount, "priv/fixtures/last_light.fountain")
raw = File.read!(fixture)
doc = Fount.parse!(raw)
model = Fount.Screenplay.from_document(doc, cast_resolution: :literal_cues)
if Fount.Screenplay.to_fountain(model) != raw, do: raise "Fountain import changed source bytes"

case mode do
  "interchange" ->
    Fount.LiveArtifacts.run("interchange", out, fn directory ->
      reports = Enum.map(["fountain", "fdx", "json"], fn format ->
        result = Fount.Interchange.write(model, format, include_source: true) |> Fount.LiveArtifacts.require!()
        File.write!(Path.join(directory, "last_light." <> format), result.data)
        {reopened, diagnostics} = case Fount.Interchange.read(result.data, format) do
          {:ok, value, messages} -> {value, messages}
          error -> Fount.LiveArtifacts.require!(error)
        end
        if format == "json" and reopened.revision.content_hash != model.revision.content_hash, do: raise("Canonical JSON content hash changed")
        if format == "fountain" and result.data != raw, do: raise("Unchanged Fountain bytes changed")
        %{"format" => format, "losses" => result.losses, "diagnostics" => diagnostics, "reopened_scenes" => length(reopened.ir.scenes)}
      end)
      Fount.LiveArtifacts.write!(directory, "fidelity.json", Fount.Interchange.matrix())
      %{"formats" => reports, "source_sha256" => Fount.ID.hash(raw)}
    end) |> Fount.LiveArtifacts.require!()

  "roundtrip" ->
    File.write!(Path.join(out, "last_light.fountain"), Fount.Screenplay.to_fountain(model))
    {:ok, fdx} = Fount.Screenplay.to_fdx(model)
    File.write!(Path.join(out, "last_light.fdx"), fdx.data)
    {:ok, json} = Fount.Adapter.JSON.export(model, include_source: true)
    File.write!(Path.join(out, "last_light.json"), json.data)
    File.write!(Path.join(out, "manifest.json"), Jason.encode!(%{
      mode: mode, source_sha256: Fount.ID.hash(raw), scene_count: length(model.ir.scenes),
      cast_count: map_size(model.cast), revision_id: model.revision.id
    }, pretty: true))
    IO.puts("Roundtrip exported #{length(model.ir.scenes)} scenes to #{out}")

  "database" ->
    url = System.fetch_env!("FOUNT_DATABASE_URL")
    {:ok, _} = Fount.Repo.start_link(url: url, pool_size: 2)
    key = "live-#{Fount.ID.v4()}"
    {:ok, _} = Fount.Persistence.create(Fount.Repo, key, model)
    {:ok, loaded} = Fount.Persistence.load(Fount.Repo, key)
    if Fount.Screenplay.to_fountain(loaded) != raw, do: raise "database changed imported source"
    line = Enum.find(loaded.ir.elements, &(&1.type == :action and String.contains?(&1.text, "key in her hand"))) || raise "fixture key transfer missing"
    op = %{"kind" => "replace_text", "target" => %{"kind" => "element", "id" => line.id},
      "value" => String.replace(line.text, "She pockets it.", "She drops it, then snatches it back.")}
    {:ok, edited, changes} = Fount.Screenplay.apply(loaded, [op], [])
    {:ok, _} = Fount.Persistence.save_edit(Fount.Repo, key, edited,
      expected_revision: loaded.revision.id, actor: "live example", operations: changes.operations)
    {:ok, current} = Fount.Persistence.load(Fount.Repo, key)
    {:ok, previous} = Fount.Persistence.load_revision(Fount.Repo, model.id, model.revision.id)
    if Fount.Query.node(previous, line.id).text != line.text, do: raise "historical revision changed"
    File.write!(Path.join(out, "accepted.fountain"), Fount.Screenplay.to_fountain(current))
    File.write!(Path.join(out, "original.fountain"), Fount.Screenplay.to_fountain(previous))
    File.write!(Path.join(out, "fixture_bindings.json"), Jason.encode!(%{
      key: key, screenplay_id: model.id, original_revision_id: model.revision.id,
      accepted_revision_id: current.revision.id, key_transfer_element_id: line.id
    }, pretty: true))
    IO.puts("Saved and reopened two PostgreSQL revisions for #{key}; output #{out}")

  other -> raise "Unknown mode #{inspect(other)}"
end
