argv =
  case System.argv() do
    ["--" | rest] -> rest
    other -> other
  end

{opts, [], []} =
  OptionParser.parse(argv,
    strict: [mode: :string, out: :string, accept_demo: :boolean]
  )

mode = opts[:mode] || raise "--mode develop is required"
url = System.fetch_env!("FOUNT_DATABASE_URL")
out = Path.expand(opts[:out] || System.get_env("FOUNT_EXAMPLE_OUT") || "examples/output")
File.mkdir_p!(out)
{:ok, _} = Fount.Repo.start_link(url: url, pool_size: 2)

case mode do
  "sequence" ->
    key = "live-sequence-#{Fount.ID.v4()}"
    fixture = Application.app_dir(:fount, "priv/fixtures/last_light.fountain")

    root =
      fixture
      |> File.read!()
      |> Fount.parse!()
      |> Fount.Screenplay.from_document(cast_resolution: :literal_cues)

    {:ok, _} = Fount.Persistence.create(Fount.Repo, key, root)
    selected = Enum.take(root.ir.scenes, 5)
    ids = Enum.map(selected, & &1.id)

    client =
      Inference.Client.agent_session!(
        adapter: Inference.Adapters.ASM,
        provider: :codex,
        model: System.get_env("FOUNT_CODEX_MODEL"),
        adapter_opts: [query_opts: [stream_timeout_ms: 180_000]]
      )

    direction =
      "Compress these five scenes into three. Keep the ledger forgery confession, Mara's signature problem, Dan handing Mara the brass key, and the gate/ferry pressure. Make the choice to board feel earned; keep continuity with the following ferry queue scene."

    {:ok, result} =
      FountWorkshop.SequenceRebuild.run(Fount.Repo, key, ids, direction, client,
        target_scene_count: 3,
        required_texts: ["Take this. It opens the service gate on the ferry pier."]
      )

    candidate = result.candidate
    {:ok, reopened} = Fount.Persistence.candidate(Fount.Repo, candidate.id)
    {:ok, packet} = FountWorkshop.Review.packet(Fount.Repo, candidate.id)
    prefix = Path.join(out, candidate.id)
    File.write!(prefix <> ".fountain", packet["proposed_fountain"])

    File.write!(
      prefix <> ".review.json",
      Jason.encode!(
        %{
          candidate_id: candidate.id,
          source_diff: inspect(packet["source_diff"]),
          structural_diff: Fount.Screenplay.Model.plain(packet["structural_diff"])
        },
        pretty: true
      )
    )

    {:ok, baseline_pdf} =
      FountWorkshop.Export.PDF.export(
        root,
        Path.join(out, "baseline.pdf")
      )

    {:ok, candidate_pdf} =
      FountWorkshop.Export.PDF.export(
        reopened["screenplay"],
        prefix <> ".pdf"
      )

    {:ok, head} = Fount.Persistence.load(Fount.Repo, key)
    if head.revision.id != root.revision.id, do: raise("Sequence moved accepted head")

    File.write!(
      Path.join(out, "manifest.json"),
      Jason.encode!(
        %{
          mode: mode,
          screenplay_key: key,
          session_id: result.session.id,
          selected_scene_ids: ids,
          candidate_id: candidate.id,
          base_revision_id: root.revision.id,
          accepted_revision_id: head.revision.id,
          result_revision_id: reopened["screenplay"].revision.id,
          fountain: prefix <> ".fountain",
          baseline_pdf: baseline_pdf.path,
          candidate_pdf: candidate_pdf.path,
          baseline_pages: baseline_pdf.pages,
          candidate_pages: candidate_pdf.pages,
          page_delta: candidate_pdf.pages - baseline_pdf.pages
        },
        pretty: true
      )
    )

    IO.puts("Wrote a real rebuilt sequence and measured PDFs in #{out}")

  "rewrite" ->
    key = "live-rewrite-#{Fount.ID.v4()}"
    fixture = Application.app_dir(:fount, "priv/fixtures/last_light.fountain")

    root =
      fixture
      |> File.read!()
      |> Fount.parse!()
      |> Fount.Screenplay.from_document(cast_resolution: :literal_cues)

    {:ok, _} = Fount.Persistence.create(Fount.Repo, key, root)

    [target] =
      Enum.filter(
        root.ir.elements,
        &(&1.text == "We bill by the berth, not by altitude.")
      )

    client =
      Inference.Client.agent_session!(
        adapter: Inference.Adapters.ASM,
        provider: :codex,
        model: System.get_env("FOUNT_CODEX_MODEL"),
        adapter_opts: [query_opts: [stream_timeout_ms: 180_000]]
      )

    {:ok, result} =
      FountWorkshop.TargetedRewrite.run(
        Fount.Repo,
        key,
        [target.id],
        "Give Dan a sharper dry deflection that still means the marina bills by berth, not boat condition. Preserve his character voice and the next reply.",
        client
      )

    candidate = result.candidate
    {:ok, reopened} = Fount.Persistence.candidate(Fount.Repo, candidate.id)
    {:ok, packet} = FountWorkshop.Review.packet(Fount.Repo, candidate.id)
    prefix = Path.join(out, candidate.id)
    File.write!(prefix <> ".fountain", packet["proposed_fountain"])

    File.write!(
      prefix <> ".review.json",
      Jason.encode!(
        %{
          candidate_id: candidate.id,
          target_element_id: target.id,
          before: target.text,
          after: Fount.Query.node(reopened["screenplay"], target.id).text,
          source_diff: inspect(packet["source_diff"])
        },
        pretty: true
      )
    )

    {:ok, pdf} = FountWorkshop.Export.PDF.export(reopened["screenplay"], prefix <> ".pdf")
    {:ok, head} = Fount.Persistence.load(Fount.Repo, key)
    if head.revision.id != root.revision.id, do: raise("Rewrite moved accepted head")

    File.write!(
      Path.join(out, "manifest.json"),
      Jason.encode!(
        %{
          mode: mode,
          screenplay_key: key,
          session_id: result.session.id,
          candidate_id: candidate.id,
          target_element_id: target.id,
          base_revision_id: root.revision.id,
          accepted_revision_id: head.revision.id,
          result_revision_id: reopened["screenplay"].revision.id,
          fountain: prefix <> ".fountain",
          pdf: pdf.path,
          pages: pdf.pages,
          pdf_sha256: pdf.sha256
        },
        pretty: true
      )
    )

    IO.puts("Wrote a real exact-target rewrite and PDF in #{out}")

  "develop" ->
    key = "live-develop-#{Fount.ID.v4()}"
    root = Fount.Screenplay.new(title: [{"Title", "Last Ferry"}])
    {:ok, _} = Fount.Persistence.create(Fount.Repo, key, root)
    model = System.get_env("FOUNT_CODEX_MODEL")

    client =
      Inference.Client.agent_session!(
        adapter: Inference.Adapters.ASM,
        provider: :codex,
        model: model,
        adapter_opts: [query_opts: [stream_timeout_ms: 180_000]]
      )

    brief =
      "A marina bookkeeper must get her former partner onto the last ferry to face an accountant. They used to trust each other. Give me two different opening scenes, one built around a practical task and one around an attempted escape. Let behavior carry the resentment."

    case FountWorkshop.Develop.run(Fount.Repo, key, brief, client,
           approaches: [
             "A practical task exposes their history",
             "An attempted escape forces contact"
           ]
         ) do
      {:ok, result} ->
        exports =
          Enum.map(result.candidates, fn candidate ->
            prefix = Path.join(out, candidate.id)

            packet =
              case FountWorkshop.Review.packet(Fount.Repo, candidate.id) do
                {:ok, packet} -> packet
                error -> raise "Review packet failed: #{inspect(error)}"
              end

            File.write!(prefix <> ".fountain", packet["proposed_fountain"])

            File.write!(
              prefix <> ".review.json",
              Jason.encode!(
                %{
                  candidate_id: candidate.id,
                  base_revision_id: packet["base_revision_id"],
                  result_revision_id: packet["result_revision_id"],
                  content_hash: packet["content_hash"],
                  source_diff: inspect(packet["source_diff"]),
                  structural_diff: Fount.Screenplay.Model.plain(packet["structural_diff"]),
                  provenance: packet["provenance"]
                },
                pretty: true
              )
            )

            {:ok, pdf} = FountWorkshop.Export.PDF.export(candidate.screenplay, prefix <> ".pdf")

            %{
              candidate_id: candidate.id,
              fountain: prefix <> ".fountain",
              pdf: pdf.path,
              pages: pdf.pages,
              pdf_sha256: pdf.sha256
            }
          end)

        accepted =
          if opts[:accept_demo] do
            chosen = hd(result.candidates)

            review = %{
              "candidate_id" => chosen.id,
              "content_hash" => chosen.screenplay.revision.content_hash,
              "actor" => "live example writer",
              "report_ids" => [],
              "overrides" => []
            }

            {:ok, head} =
              FountWorkshop.Review.accept(Fount.Repo, chosen.id, root.revision.id, review)

            head.revision.id
          else
            {:ok, head} = Fount.Persistence.load(Fount.Repo, key)

            if head.revision.id != root.revision.id,
              do: raise("Accepted head moved without --accept-demo")

            head.revision.id
          end

        manifest = %{
          mode: mode,
          screenplay_key: key,
          screenplay_id: root.id,
          session_id: result.session.id,
          base_revision_id: root.revision.id,
          accepted_revision_id: accepted,
          candidates: exports,
          accepted_by_demo: !!opts[:accept_demo]
        }

        File.write!(Path.join(out, "manifest.json"), Jason.encode!(manifest, pretty: true))
        IO.puts("Generated #{length(exports)} real candidate drafts with PDFs in #{out}")

      {:partial, result, reason} ->
        exports =
          Enum.map(result.candidates, fn candidate ->
            prefix = Path.join(out, candidate.id)
            File.write!(prefix <> ".fountain", Fount.Screenplay.to_fountain(candidate.screenplay))
            {:ok, pdf} = FountWorkshop.Export.PDF.export(candidate.screenplay, prefix <> ".pdf")

            %{
              candidate_id: candidate.id,
              fountain: prefix <> ".fountain",
              pdf: pdf.path,
              pages: pdf.pages
            }
          end)

        File.write!(
          Path.join(out, "manifest.json"),
          Jason.encode!(
            %{
              mode: mode,
              status: "partial",
              screenplay_key: key,
              session_id: result.session.id,
              base_revision_id: root.revision.id,
              accepted_revision_id: root.revision.id,
              candidates: exports,
              reason: inspect(reason)
            },
            pretty: true
          )
        )

        raise "Develop mode partial: #{inspect(reason)}"

      {:error, reason} ->
        File.write!(
          Path.join(out, "failure.json"),
          Jason.encode!(
            %{
              mode: mode,
              screenplay_key: key,
              base_revision_id: root.revision.id,
              status: "failed_or_partial",
              reason: inspect(reason)
            },
            pretty: true
          )
        )

        raise "Develop mode failed or was partial: #{inspect(reason)}"
    end

  other ->
    raise "Unknown mode #{inspect(other)}"
end
