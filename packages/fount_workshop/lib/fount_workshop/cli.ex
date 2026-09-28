defmodule FountWorkshop.CLI do
  @moduledoc "Writer commands. Review and acceptance are distinct operations; no generation command advances the accepted draft."
  alias Fount.CLI.Support, as: S
  alias Fount.Screenplay.Model
  alias FountWorkshop.Acceptance
  alias FountWorkshop.Candidate
  alias FountWorkshop.Discovery
  alias FountWorkshop.Export.PDF
  alias FountWorkshop.Session
  alias FountWorkshop.Share
  alias FountWorkshop.Store
  alias FountWorkshop.Strategy

  @flags [
    key: :string,
    request: :string,
    output: :string,
    revision: :string,
    id: :string,
    resume: :boolean,
    reinspect: :boolean,
    session: :string,
    strategies: :string,
    candidate: :string,
    groups: :string,
    actor: :string,
    expected_revision: :string,
    review: :string,
    pdf: :boolean,
    speech: :boolean,
    new: :boolean
  ]
  @required %{
    "write" => [:key, :request, :output],
    "open" => [:key, :request, :output],
    "session" => [:id, :output],
    "fragment" => [:session, :request, :output],
    "brief" => [:session, :request, :output],
    "mode" => [:session, :request, :output],
    "outline" => [:session, :output],
    "reorder" => [:session, :request, :output],
    "manual" => [:session, :request, :output, :actor],
    "edit" => [:candidate, :request, :output, :actor],
    "decide" => [:session, :request, :output, :actor],
    "materialize" => [:session, :strategies, :output],
    "select" => [:candidate, :groups, :output],
    "combine" => [:request, :output],
    "rebase" => [:candidate, :request, :output],
    "audition" => [:candidate, :output],
    "accept" => [:candidate, :expected_revision, :actor],
    "reject" => [:candidate, :actor],
    "render" => [:key, :output],
    "read" => [:key, :output]
  }

  def run(command, argv) do
    with {:ok, opts, []} <- S.parse(argv, @flags),
         true <- Map.has_key?(@required, command) or {:error, :unknown_workshop_command} do
      if opts[:help] do
        {:ok, %{"usage" => help(command), "required" => @required[command]}}
      else
        run_command(command, opts)
      end
    else
      {:ok, _, _} -> {:error, :unexpected_positional_arguments}
      error -> error
    end
  end

  defp run_command(command, opts) do
    with :ok <- S.required(opts, @required[command]),
         {:ok, repo} <- S.connect(),
         {:ok, services} <- services(command, opts, repo) do
      dispatch(command, opts, services)
    end
  end

  def services(command, opts, repo) do
    paid =
      command in ~w(write materialize combine rebase) or (command == "session" and opts[:resume])

    with {:ok, clients} <- FountWorkshop.Launcher.clients(inference: paid, observe: paid),
         {:ok, voices} <- FountWorkshop.Launcher.voices() do
      {:ok,
       %{
         store: Store.new(repo),
         inference: clients.inference,
         observe: clients.observe,
         renderer: PDF,
         voices: voices
       }}
    end
  end

  defp dispatch("write", opts, services) do
    with {:ok, request} <- S.json_file(opts[:request]),
         {:ok, model, request} <- base(opts, request, services) do
      Session.start(model, request, services, runtime_opts(opts))
      |> export_result(opts[:output], services, runtime_opts(opts))
    end
  end

  defp dispatch("open", opts, services) do
    with {:ok, request} <- S.json_file(opts[:request]),
         {:ok, model, request} <- base(opts, request, services),
         {:ok, session} <- Session.open(model, request, services, runtime_opts(opts)) do
      phase12_result(opts[:output], "session.json", session)
    end
  end

  defp dispatch("fragment", opts, services) do
    with {:ok, request} <- S.json_file(opts[:request]) do
      result = fragment_action(request["action"], request, opts, services)

      case result do
        {:ok, saved} -> phase12_result(opts[:output], "fragment.json", saved)
        error -> error
      end
    end
  end

  defp dispatch("brief", opts, services) do
    with {:ok, patch} <- S.json_file(opts[:request]),
         {:ok, saved} <-
           Discovery.update_brief(opts[:session], patch, services,
             actor: opts[:actor] || "writer"
           ) do
      phase12_result(opts[:output], "brief.json", saved)
    end
  end

  defp dispatch("mode", opts, services) do
    with {:ok, request} <- S.json_file(opts[:request]),
         mode when is_binary(mode) <- request["mode"],
         {:ok, saved} <-
           Discovery.switch_mode(opts[:session], mode, services, actor: opts[:actor] || "writer") do
      phase12_result(opts[:output], "mode.json", saved)
    else
      nil -> {:error, :mode_required}
      error -> error
    end
  end

  defp dispatch("outline", opts, services) do
    with {:ok, outline} <- Discovery.reverse_outline(opts[:session], services) do
      phase12_result(opts[:output], "reverse-outline.json", outline)
    end
  end

  defp dispatch("reorder", opts, services) do
    with {:ok, request} <- S.json_file(opts[:request]),
         scene_ids when is_list(scene_ids) <- request["scene_ids"],
         {:ok, proposal} <-
           Discovery.propose_reorder(opts[:session], scene_ids, services,
             actor: opts[:actor] || "writer"
           ) do
      phase12_result(opts[:output], "card-reorder.json", proposal)
    else
      nil -> {:error, :scene_ids_required}
      error -> error
    end
  end

  defp dispatch("manual", opts, services) do
    with {:ok, request} <- S.json_file(opts[:request]),
         operations when is_list(operations) <- request["operations"],
         {:ok, candidate} <-
           Candidate.manual(
             opts[:session],
             operations,
             services,
             actor: opts[:actor],
             label: request["label"] || "Writer fragment",
             summary: request["summary"] || "Writer-authored candidate"
           ) do
      phase12_candidate_result(candidate, opts, services)
    else
      nil -> {:error, :operations_required}
      error -> error
    end
  end

  defp dispatch("edit", opts, services) do
    with {:ok, request} <- S.json_file(opts[:request]),
         operations when is_list(operations) <- request["operations"],
         {:ok, candidate} <-
           Candidate.edit(opts[:candidate], operations, services, actor: opts[:actor]) do
      phase12_candidate_result(candidate, opts, services)
    else
      nil -> {:error, :operations_required}
      error -> error
    end
  end

  defp dispatch("decide", opts, services) do
    with {:ok, request} <- S.json_file(opts[:request]),
         candidate_ids when is_list(candidate_ids) <- request["candidate_ids"] do
      result =
        case request["action"] do
          "keep_both" ->
            Discovery.keep_both(opts[:session], candidate_ids, services, actor: opts[:actor])

          "reject_all" ->
            Discovery.reject_all(opts[:session], candidate_ids, opts[:actor], services)

          _ ->
            {:error, :unknown_phase12_decision}
        end

      case result do
        {:ok, value} -> phase12_result(opts[:output], "decision.json", value)
        error -> error
      end
    else
      nil -> {:error, :candidate_ids_required}
      error -> error
    end
  end

  defp dispatch("session", opts, services) do
    result =
      if opts[:resume],
        do: Session.resume(opts[:id], services, runtime_opts(opts)),
        else: Session.resume_view(opts[:id], services)

    export_result(result, opts[:output], services, runtime_opts(opts))
  end

  defp dispatch("materialize", opts, services) do
    with {:ok, ids} <- S.ids(opts[:strategies]) do
      Strategy.materialize(opts[:session], ids, services, runtime_opts(opts))
      |> export_result(opts[:output], services, runtime_opts(opts))
    end
  end

  defp dispatch("select", opts, services) do
    with {:ok, ids} <- S.ids(opts[:groups]),
         {:ok, c} <- Candidate.select(opts[:candidate], ids, services, runtime_opts(opts)) do
      candidate_result(c, opts, services)
    end
  end

  defp dispatch("combine", opts, services) do
    with {:ok, request} <- S.json_file(opts[:request]),
         true <-
           (is_map(request) and Map.keys(request) -- ~w(candidate_ids selection) == []) or
             {:error, :invalid_combination_request},
         {:ok, c} <-
           Candidate.combine(
             request["candidate_ids"],
             request["selection"],
             services,
             runtime_opts(opts)
           ) do
      candidate_result(c, opts, services)
    end
  end

  defp dispatch("rebase", opts, services) do
    with {:ok, request} <- S.json_file(opts[:request]),
         true <-
           (is_map(request) and is_binary(request["current_revision_id"])) or
             {:error, :current_revision_required},
         {:ok, candidate} <- Store.call(services.store, :candidate, [opts[:candidate]]),
         {:ok, current} <-
           Store.call(services.store, :load_revision, [
             candidate["screenplay_id"],
             request["current_revision_id"]
           ]),
         {:ok, c} <-
           Candidate.rebase(
             opts[:candidate],
             current,
             Map.delete(request, "current_revision_id"),
             services
           ) do
      if is_map(c) and c["session_id"],
        do: candidate_result(c, opts, services),
        else: S.write_json(Path.join(opts[:output], "rebase.json"), c)
    end
  end

  defp dispatch("audition", opts, services),
    do:
      FountWorkshop.Audition.build(
        opts[:candidate],
        %{"whole_screenplay" => true},
        services,
        runtime_opts(opts)
      )

  defp dispatch("accept", opts, services) do
    with {:ok, candidate} <- Store.call(services.store, :candidate, [opts[:candidate]]),
         {:ok, review} <- review(opts, candidate),
         {:ok, model} <-
           Acceptance.accept(opts[:candidate], opts[:expected_revision], review, services),
         {:ok, _} <-
           Discovery.record_acceptance(candidate["session_id"], opts[:candidate], services,
             actor: opts[:actor]
           ) do
      {:ok, Fount.CLI.summary(model)}
    end
  end

  defp dispatch("reject", opts, services),
    do: Acceptance.reject(opts[:candidate], opts[:actor], services)

  defp dispatch("render", opts, services) do
    with {:ok, model} <- S.load(services.store.repo, opts) do
      PDF.export(model, opts[:output])
    end
  end

  defp dispatch("read", opts, services) do
    selection = %{"whole_screenplay" => true}

    with {:ok, model} <- S.load(services.store.repo, opts),
         {:ok, json} <-
           FountWorkshop.TableRead.export(
             model,
             Path.join(opts[:output], "table-read.json"),
             :json
           ),
         {:ok, html} <-
           FountWorkshop.TableRead.export(
             model,
             Path.join(opts[:output], "table-read.html"),
             :html
           ),
         {:ok, packet} <-
           FountWorkshop.TableRead.export_packet(
             model,
             Path.join(opts[:output], "table-read.packet.json"),
             selection
           ),
         {:ok, share} <- Share.export(model, selection, Path.join(opts[:output], "share")) do
      read_result(model, opts, services, json, html, packet, share)
    end
  end

  defp read_result(model, opts, services, json, html, packet, share) do
    base = %{json: json, html: html, packet: packet, share: share}

    if opts[:speech] do
      with {:ok, audio} <-
             FountWorkshop.TableRead.render_audio(
               model,
               Path.join(opts[:output], "audio"),
               services.voices
             ) do
        {:ok, Map.put(base, :audio, audio)}
      end
    else
      {:ok, base}
    end
  end

  defp fragment_action(action, request, opts, services) when action in [nil, "capture"] do
    attrs = Map.delete(request, "action")
    Discovery.add_fragment(opts[:session], attrs, services, actor: opts[:actor] || "writer")
  end

  defp fragment_action("link", request, opts, services) do
    Discovery.link_fragment(opts[:session], request["fragment_id"], request["scene_id"], services,
      actor: opts[:actor] || "writer"
    )
  end

  defp fragment_action("classify", request, opts, services) do
    Discovery.classify_fragment(
      opts[:session],
      request["fragment_id"],
      request["classification"],
      services,
      actor: opts[:actor] || "writer"
    )
  end

  defp fragment_action("retire", request, opts, services) do
    Discovery.retire_fragment(opts[:session], request["fragment_id"], services,
      actor: opts[:actor] || "writer"
    )
  end

  defp fragment_action("adopt", request, opts, services) do
    Discovery.adopt_fragment(
      opts[:session],
      request["fragment_id"],
      request["candidate_id"],
      services,
      actor: opts[:actor] || "writer"
    )
  end

  defp fragment_action(_, _request, _opts, _services), do: {:error, :unknown_fragment_action}

  defp base(opts, request, services) do
    if opts[:new] do
      with true <-
             (request["workflow"] == "develop" and is_nil(request["base_revision_id"])) or
               {:error, :new_requires_develop_and_null_base},
           true <-
             is_nil(get_in(request, ["options", "brief_item_id"])) or
               {:error, :new_cannot_reference_existing_brief} do
        root = Fount.Screenplay.new()
        brief = get_in(request, ["options", "brief"])

        root = add_brief(root, brief)

        anchored = Map.put(request, "base_revision_id", root.revision.id)

        create_base(root, anchored, opts, services)
      end
    else
      with {:ok, model} <- S.load(services.store.repo, opts), do: {:ok, model, request}
    end
  end

  defp add_brief(root, brief) when is_map(brief) do
    id = Fount.ID.v4()

    item = %{
      "id" => id,
      "kind" => "brief",
      "target" => %{"kind" => "screenplay", "id" => root.id},
      "namespace" => "writer",
      "value" => brief,
      "dependencies" => [],
      "status" => "active",
      "provenance" => %{"source" => "writer"}
    }

    Model.refresh(%{root | authored_items: Map.put(root.authored_items, id, item)})
  end

  defp add_brief(root, _), do: root

  defp create_base(root, request, opts, services) do
    with {:ok, validated} <- FountWorkshop.Request.validate(root, request),
         {:ok, saved} <-
           Store.call(services.store, :create, [
             opts[:key],
             root,
             [actor: opts[:actor] || "writer"]
           ]) do
      {:ok, saved, validated}
    end
  end

  defp review(opts, candidate) do
    if opts[:review] do
      with {:ok, review} <- S.json_file(opts[:review]),
           true <- review["actor"] == opts[:actor] or {:error, :review_actor_mismatch} do
        {:ok, review}
      end
    else
      # Running fount.accept with explicit actor is the decision, not an automatic action by generation.
      {:ok,
       %{
         "candidate_id" => candidate["id"],
         "content_hash" => candidate["screenplay"].revision.content_hash,
         "actor" => opts[:actor],
         "report_ids" => candidate["provenance"]["report_ids"] || [],
         "overrides" => []
       }}
    end
  end

  defp phase12_candidate_result(candidate, opts, services) do
    with {:ok, _} <-
           phase12_result(opts[:output], "candidate.json", %{
             "candidate_id" => candidate["id"],
             "base_revision_id" => candidate["base_revision_id"],
             "result_revision_id" => candidate["result_revision_id"]
           }) do
      candidate_result(candidate, opts, services)
    end
  end

  defp candidate_result(c, opts, services) do
    with {:ok, packet} <-
           FountWorkshop.Review.export(
             c["session_id"],
             opts[:output],
             services,
             runtime_opts(opts)
           ) do
      {:ok, %{"candidate_id" => c["id"], "review" => packet}}
    end
  end

  defp phase12_result(output, name, value), do: S.write_json(Path.join(output, name), value)

  def export_result({:ok, session}, output, services, opts),
    do: FountWorkshop.Review.export(session["id"], output, services, opts)

  def export_result({:error, reason, session}, output, services, opts) do
    _ = FountWorkshop.Review.export(session["id"], output, services, opts)
    {:error, reason, session}
  end

  def export_result(error, _, _, _), do: error

  def runtime_opts(opts),
    do: [
      output_dir: opts[:output],
      render: opts[:pdf] || false,
      pdf: opts[:pdf] || false,
      speech: opts[:speech] || false,
      actor: opts[:actor],
      reinspect: opts[:reinspect] || false
    ]

  defp help(command),
    do:
      "mix fount.#{command}; required: " <>
        Enum.map_join(
          @required[command],
          " ",
          &("--" <> (Atom.to_string(&1) |> String.replace("_", "-")) <> " VALUE")
        ) <> "; see guides/creative-workflows.md for request examples"
end
