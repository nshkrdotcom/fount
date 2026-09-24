argv =
  case System.argv() do
    ["--" | rest] -> rest
    other -> other
  end

{opts, [], []} = OptionParser.parse(argv, strict: [mode: :string, out: :string])
mode = opts[:mode] || raise "--mode knowledge is required"
out = Path.expand(opts[:out] || System.get_env("FOUNT_EXAMPLE_OUT") || "examples/output")
File.mkdir_p!(out)

case mode do
  "knowledge" ->
    key = System.fetch_env!("SYSTEM_ONE_API_KEY")
    fixture = Application.app_dir(:fount, "priv/fixtures/last_light.fountain")

    model =
      fixture
      |> File.read!()
      |> Fount.parse!()
      |> Fount.Screenplay.from_document(cast_resolution: :literal_cues)

    headings =
      Enum.filter(model.ir.scenes, fn scene ->
        Fount.Query.node(model, scene.heading_id).text == "EXT. BOAT RAMP - NIGHT"
      end)

    [boundary] = headings
    [mara] = Enum.filter(Fount.Query.characters(model), &(&1.display_name == "MARA"))
    [dan] = Enum.filter(Fount.Query.characters(model), &(&1.display_name == "DAN"))
    client = SystemOneSDK.new_client(api_key: key)

    {:ok, report} =
      FountProbe.Knowledge.trace(
        model,
        "Dan has explicitly confessed to manipulating the marina accounts",
        boundary.id,
        [mara.id, dan.id],
        client
      )

    assessments =
      Map.new(report.assessments, fn {name, result} ->
        {name,
         Map.take(result, [
           :status,
           :probability,
           :scene_ids,
           :evidence_ids,
           :model,
           :prepared_fingerprint
         ])}
      end)

    File.write!(
      Path.join(out, "knowledge.json"),
      Jason.encode!(
        %{
          mode: mode,
          status: report.status,
          screenplay_id: model.id,
          revision_id: model.revision.id,
          boundary_scene_id: boundary.id,
          character_ids: %{mara: mara.id, dan: dan.id},
          assessments: assessments
        },
        pretty: true
      )
    )

    if report.status != :complete,
      do: raise("Jev knowledge mode partial; inspect #{out}/knowledge.json")

    IO.puts("Live Jev evaluated #{map_size(assessments)} perspectives; output #{out}")

  other ->
    raise "Unknown mode #{inspect(other)}"
end
