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
  new_mode when new_mode in ["bridge", "alternatives", "propagate", "sequence_routes", "character_workspace", "grouped_notes", "pass_all", "recover_scene", "investigate"] ->
    FountWorkshop.LiveExample.run(new_mode, out, accept_demo: opts[:accept_demo] || false) |> Fount.LiveArtifacts.require!()

  "recover" ->
    key = "live-recover-#{Fount.ID.v4()}"
    fixture = Application.app_dir(:fount, "priv/fixtures/last_light.fountain")

    root =
      fixture
      |> File.read!()
      |> Fount.parse!()
      |> Fount.Screenplay.from_document(cast_resolution: :literal_cues)

    {:ok, _} = Fount.Persistence.create(Fount.Repo, key, root)

    [lost] =
      Enum.filter(
        root.ir.elements,
        &(&1.text ==
            "Dan unlocks a tin cashbox. One brass key lies on a float shaped like a fish.")
      )

    {:ok, cut, _} =
      Fount.Screenplay.apply(root, [
        %{
          "kind" => "delete_elements",
          "value" => %{"ids" => [lost.id]}
        }
      ])

    {:ok, _} =
      Fount.Persistence.save_edit(Fount.Repo, key, cut, expected_revision: root.revision.id)

    {:ok, result} = FountWorkshop.Recover.run(Fount.Repo, key, root.revision.id, lost.id)
    candidate = result.candidate
    {:ok, reopened} = Fount.Persistence.candidate(Fount.Repo, candidate.id)
    {:ok, packet} = FountWorkshop.Review.packet(Fount.Repo, candidate.id)
    restored = Fount.Query.node(reopened["screenplay"], lost.id)
    if restored == nil or restored.text != lost.text, do: raise("Historical beat not restored")
    prefix = Path.join(out, candidate.id)
    File.write!(prefix <> ".fountain", packet["proposed_fountain"])

    File.write!(
      prefix <> ".review.json",
      Jason.encode!(
        %{
          candidate_id: candidate.id,
          source_revision_id: root.revision.id,
          source_element_id: lost.id,
          source_text: lost.text,
          current_text: nil,
          proposed_text: restored.text,
          source_diff: inspect(packet["source_diff"])
        },
        pretty: true
      )
    )

    {:ok, pdf} = FountWorkshop.Export.PDF.export(reopened["screenplay"], prefix <> ".pdf")
    {:ok, head} = Fount.Persistence.load(Fount.Repo, key)
    if head.revision.id != cut.revision.id, do: raise("Recover moved accepted head")

    File.write!(
      Path.join(out, "manifest.json"),
      Jason.encode!(
        %{
          mode: mode,
          screenplay_key: key,
          session_id: result.session.id,
          candidate_id: candidate.id,
          source_revision_id: root.revision.id,
          base_revision_id: cut.revision.id,
          accepted_revision_id: head.revision.id,
          result_revision_id: reopened["screenplay"].revision.id,
          restored_element_id: lost.id,
          fountain: prefix <> ".fountain",
          pdf: pdf.path,
          pages: pdf.pages,
          pdf_sha256: pdf.sha256
        },
        pretty: true
      )
    )

    IO.puts("Wrote a real historical recovery candidate and PDF in #{out}")

  "speech" ->
    fixture = Application.app_dir(:fount, "priv/fixtures/last_light.fountain")

    model =
      fixture
      |> File.read!()
      |> Fount.parse!()
      |> Fount.Screenplay.from_document(cast_resolution: :literal_cues)

    scene = hd(model.ir.scenes)
    {:ok, turns} = Fount.Writer.table_read(model, scene.id)

    executable =
      System.get_env("FOUNT_ESPEAK_BIN") ||
        System.find_executable("espeak-ng") || System.find_executable("espeak") ||
        raise "Real eSpeak executable is required for speech mode"

    clips =
      turns
      |> Enum.with_index()
      |> Enum.map(fn {turn, index} ->
        path =
          Path.join(out, "turn-#{String.pad_leading(Integer.to_string(index + 1), 3, "0")}.wav")

        {:ok, audio} =
          FountWorkshop.Speech.Espeak.render(turn.dialogue, "en", path, executable: executable)

        %{
          block_id: turn.id,
          cue: turn.cue,
          path: audio.path,
          bytes: audio.bytes,
          sha256: audio.sha256
        }
      end)

    File.write!(
      Path.join(out, "manifest.json"),
      Jason.encode!(
        %{
          mode: mode,
          screenplay_id: model.id,
          revision_id: model.revision.id,
          scene_id: scene.id,
          clips: clips
        },
        pretty: true
      )
    )

    IO.puts("Wrote #{length(clips)} real speech WAV files in #{out}")

  "table_read" ->
    fixture = Application.app_dir(:fount, "priv/fixtures/last_light.fountain")

    model =
      fixture
      |> File.read!()
      |> Fount.parse!()
      |> Fount.Screenplay.from_document(cast_resolution: :literal_cues)

    {:ok, json} = FountWorkshop.TableRead.export(model, Path.join(out, "table_read.json"), :json)
    {:ok, html} = FountWorkshop.TableRead.export(model, Path.join(out, "table_read.html"), :html)
    {:ok, pdf} = FountWorkshop.Export.PDF.export(model, Path.join(out, "screenplay.pdf"))

    File.write!(
      Path.join(out, "manifest.json"),
      Jason.encode!(
        %{
          mode: mode,
          screenplay_id: model.id,
          revision_id: model.revision.id,
          turn_count: json.turn_count,
          json: json.path,
          html: html.path,
          pdf: pdf.path,
          pages: pdf.pages,
          pdf_sha256: pdf.sha256
        },
        pretty: true
      )
    )

    IO.puts("Wrote real table-read JSON/HTML and screenplay PDF in #{out}")

  "character" ->
    key = "live-character-#{Fount.ID.v4()}"
    fixture = Application.app_dir(:fount, "priv/fixtures/last_light.fountain")

    root =
      fixture
      |> File.read!()
      |> Fount.parse!()
      |> Fount.Screenplay.from_document(cast_resolution: :literal_cues)

    {:ok, _} = Fount.Persistence.create(Fount.Repo, key, root)
    [dan] = Enum.filter(Fount.Query.characters(root), &(&1.display_name == "DAN"))
    scene_ids = root.ir.scenes |> Enum.take(3) |> Enum.map(& &1.id)

    client =
      Inference.Client.agent_session!(
        adapter: Inference.Adapters.ASM,
        provider: :codex,
        model: System.get_env("FOUNT_CODEX_MODEL"),
        adapter_opts: [query_opts: [stream_timeout_ms: 180_000]]
      )

    {:ok, result} =
      FountWorkshop.CharacterRewrite.run(
        Fount.Repo,
        key,
        dan.id,
        scene_ids,
        "Across these three scenes, Dan moves from dry evasions to giving up control of the ledger. Let Mara answer his changing behavior rather than just exchanging information. Preserve the key handoff and the fact that the accountant has the original across the water.",
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
          character_id: dan.id,
          selected_scene_ids: scene_ids,
          source_diff: inspect(packet["source_diff"]),
          structural_diff: Fount.Screenplay.Model.plain(packet["structural_diff"])
        },
        pretty: true
      )
    )

    {:ok, pdf} = FountWorkshop.Export.PDF.export(reopened["screenplay"], prefix <> ".pdf")
    {:ok, head} = Fount.Persistence.load(Fount.Repo, key)
    if head.revision.id != root.revision.id, do: raise("Character rewrite moved accepted head")

    File.write!(
      Path.join(out, "manifest.json"),
      Jason.encode!(
        %{
          mode: mode,
          screenplay_key: key,
          session_id: result.session.id,
          candidate_id: candidate.id,
          character_id: dan.id,
          selected_scene_ids: scene_ids,
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

    IO.puts("Wrote a real three-scene character rewrite and PDF in #{out}")

  "pass" ->
    key = "live-pass-#{Fount.ID.v4()}"
    fixture = Application.app_dir(:fount, "priv/fixtures/last_light.fountain")

    root =
      fixture
      |> File.read!()
      |> Fount.parse!()
      |> Fount.Screenplay.from_document(cast_resolution: :literal_cues)

    {:ok, _} = Fount.Persistence.create(Fount.Repo, key, root)
    first = hd(root.ir.scenes)
    profile_id = "dialogue_subtext"

    client =
      Inference.Client.agent_session!(
        adapter: Inference.Adapters.ASM,
        provider: :codex,
        model: System.get_env("FOUNT_CODEX_MODEL"),
        adapter_opts: [query_opts: [stream_timeout_ms: 180_000]]
      )

    {:ok, result} =
      FountWorkshop.Pass.run(
        Fount.Repo,
        key,
        profile_id,
        [first.id],
        "Make Mara and Dan's first exchange more responsive, without changing who has the original ledger or how the accountant is referred to later.",
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
          profile_id: profile_id,
          source_diff: inspect(packet["source_diff"]),
          structural_diff: Fount.Screenplay.Model.plain(packet["structural_diff"])
        },
        pretty: true
      )
    )

    {:ok, pdf} = FountWorkshop.Export.PDF.export(reopened["screenplay"], prefix <> ".pdf")
    {:ok, head} = Fount.Persistence.load(Fount.Repo, key)
    if head.revision.id != root.revision.id, do: raise("Pass moved accepted head")

    File.write!(
      Path.join(out, "manifest.json"),
      Jason.encode!(
        %{
          mode: mode,
          profile_id: profile_id,
          screenplay_key: key,
          session_id: result.session.id,
          candidate_id: candidate.id,
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

    IO.puts("Wrote a real dialogue pass and PDF in #{out}")

  "notes" ->
    key = "live-notes-#{Fount.ID.v4()}"
    fixture = Application.app_dir(:fount, "priv/fixtures/last_light.fountain")

    root =
      fixture
      |> File.read!()
      |> Fount.parse!()
      |> Fount.Screenplay.from_document(cast_resolution: :literal_cues)

    {:ok, _} = Fount.Persistence.create(Fount.Repo, key, root)

    [note] =
      Enum.filter(
        root.ir.elements,
        &(&1.type == :note and String.contains?(&1.text, "costs him something"))
      )

    [target] =
      Enum.filter(
        root.ir.elements,
        &(&1.text == "The original is with the accountant across the water.")
      )

    other_note_ids =
      root.ir.elements
      |> Enum.filter(&(&1.type == :note and &1.id != note.id))
      |> Enum.map(& &1.id)

    client =
      Inference.Client.agent_session!(
        adapter: Inference.Adapters.ASM,
        provider: :codex,
        model: System.get_env("FOUNT_CODEX_MODEL"),
        adapter_opts: [query_opts: [stream_timeout_ms: 180_000]]
      )

    {:ok, result} = FountWorkshop.NoteResponse.run(Fount.Repo, key, note.id, [target.id], client)
    candidate = result.candidate
    {:ok, reopened} = Fount.Persistence.candidate(Fount.Repo, candidate.id)
    {:ok, packet} = FountWorkshop.Review.packet(Fount.Repo, candidate.id)

    if Fount.Query.node(reopened["screenplay"], note.id),
      do: raise("Addressed note still present")

    if Enum.any?(
         other_note_ids,
         &(Fount.Query.node(reopened["screenplay"], &1) == nil)
       ),
       do: raise("Unrelated note was removed")

    prefix = Path.join(out, candidate.id)
    File.write!(prefix <> ".fountain", packet["proposed_fountain"])

    File.write!(
      prefix <> ".review.json",
      Jason.encode!(
        %{
          candidate_id: candidate.id,
          addressed_note_id: note.id,
          retained_note_ids: other_note_ids,
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
    if head.revision.id != root.revision.id, do: raise("Note response moved accepted head")

    File.write!(
      Path.join(out, "manifest.json"),
      Jason.encode!(
        %{
          mode: mode,
          screenplay_key: key,
          session_id: result.session.id,
          candidate_id: candidate.id,
          addressed_note_id: note.id,
          retained_note_ids: other_note_ids,
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

    IO.puts("Wrote a real note response and PDF in #{out}")

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
