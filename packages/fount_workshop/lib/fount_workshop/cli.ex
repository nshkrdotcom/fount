defmodule FountWorkshop.CLI do
  @moduledoc "Writer commands. Review and acceptance are distinct operations; no generation command advances the accepted draft."
  alias Fount.CLI.Support, as: S
  alias FountWorkshop.{Store, Session, Candidate, Strategy, Acceptance}
  @flags [key: :string, request: :string, output: :string, revision: :string, id: :string, resume: :boolean,
    session: :string, strategies: :string, candidate: :string, groups: :string, actor: :string,
    expected_revision: :string, review: :string, pdf: :boolean, speech: :boolean, new: :boolean]
  @required %{"write" => [:key, :request, :output], "session" => [:id, :output],
    "materialize" => [:session, :strategies, :output], "select" => [:candidate, :groups, :output],
    "combine" => [:request, :output], "rebase" => [:candidate, :request, :output],
    "audition" => [:candidate, :output], "accept" => [:candidate, :expected_revision, :actor],
    "reject" => [:candidate, :actor], "render" => [:key, :output], "read" => [:key, :output]}

  def run(command, argv) do
    with {:ok, opts, []} <- S.parse(argv, @flags), true <- Map.has_key?(@required, command) or {:error, :unknown_workshop_command} do
      if opts[:help] do
        {:ok, %{"usage" => help(command), "required" => @required[command]}}
      else
        with :ok <- S.required(opts, @required[command]), {:ok, repo} <- S.connect(),
             {:ok, services} <- services(command, opts, repo) do
          dispatch(command, opts, services)
        end
      end
    else
      {:ok, _, _} -> {:error, :unexpected_positional_arguments}
      error -> error
    end
  end

  def services(command, opts, repo) do
    paid = command in ~w(write materialize combine rebase) or (command == "session" and opts[:resume])
    with {:ok, clients} <- FountProbe.Launcher.clients(inference: paid, jev: paid),
         {:ok, voices} <- FountProbe.Launcher.voices() do
      {:ok, %{store: Store.new(repo), inference: clients.inference, jev: clients.system_one,
        renderer: FountWorkshop.Export.PDF, voices: voices}}
    end
  end

  defp dispatch("write", opts, services) do
    with {:ok, request} <- S.json_file(opts[:request]), {:ok, model, request} <- base(opts, request, services) do
      Session.start(model, request, services, runtime_opts(opts)) |> export_result(opts[:output], services, runtime_opts(opts))
    end
  end
  defp dispatch("session", opts, services) do
    result = if opts[:resume], do: Session.resume(opts[:id], services, runtime_opts(opts)), else: Session.get(opts[:id], services)
    export_result(result, opts[:output], services, runtime_opts(opts))
  end
  defp dispatch("materialize", opts, services) do
    with {:ok, ids} <- S.ids(opts[:strategies]) do
      Strategy.materialize(opts[:session], ids, services, runtime_opts(opts)) |> export_result(opts[:output], services, runtime_opts(opts))
    end
  end
  defp dispatch("select", opts, services) do
    with {:ok, ids} <- S.ids(opts[:groups]), {:ok, c} <- Candidate.select(opts[:candidate], ids, services, runtime_opts(opts)) do
      candidate_result(c, opts, services)
    end
  end
  defp dispatch("combine", opts, services) do
    with {:ok, request} <- S.json_file(opts[:request]),
         true <- is_map(request) and (Map.keys(request) -- ~w(candidate_ids selection)) == [] or {:error, :invalid_combination_request},
         {:ok, c} <- Candidate.combine(request["candidate_ids"], request["selection"], services, runtime_opts(opts)) do
      candidate_result(c, opts, services)
    end
  end
  defp dispatch("rebase", opts, services) do
    with {:ok, request} <- S.json_file(opts[:request]),
         true <- is_map(request) and is_binary(request["current_revision_id"]) or {:error, :current_revision_required},
         {:ok, candidate} <- Store.call(services.store, :candidate, [opts[:candidate]]),
         {:ok, current} <- Store.call(services.store, :load_revision, [candidate["screenplay_id"], request["current_revision_id"]]),
         {:ok, c} <- Candidate.rebase(opts[:candidate], current, Map.delete(request, "current_revision_id"), services) do
      if is_map(c) and c["session_id"], do: candidate_result(c, opts, services), else: S.write_json(Path.join(opts[:output], "rebase.json"), c)
    end
  end
  defp dispatch("audition", opts, services), do: FountWorkshop.Audition.build(opts[:candidate], %{"whole_screenplay" => true}, services, runtime_opts(opts))
  defp dispatch("accept", opts, services) do
    with {:ok, candidate} <- Store.call(services.store, :candidate, [opts[:candidate]]),
         {:ok, review} <- review(opts, candidate),
         {:ok, model} <- Acceptance.accept(opts[:candidate], opts[:expected_revision], review, services) do
      {:ok, Fount.CLI.summary(model)}
    end
  end
  defp dispatch("reject", opts, services), do: Acceptance.reject(opts[:candidate], opts[:actor], services)
  defp dispatch("render", opts, services) do
    with {:ok, model} <- S.load(services.store.repo, opts) do
      FountWorkshop.Export.PDF.export(model, opts[:output])
    end
  end
  defp dispatch("read", opts, services) do
    with {:ok, model} <- S.load(services.store.repo, opts),
         {:ok, json} <- FountWorkshop.TableRead.export(model, Path.join(opts[:output], "table-read.json"), :json),
         {:ok, html} <- FountWorkshop.TableRead.export(model, Path.join(opts[:output], "table-read.html"), :html) do
      if opts[:speech] do
        with {:ok, audio} <- FountWorkshop.TableRead.render_audio(model, Path.join(opts[:output], "audio"), services.voices) do
          {:ok, %{json: json, html: html, audio: audio}}
        end
      else {:ok, %{json: json, html: html}} end
    end
  end

  defp base(opts, request, services) do
    if opts[:new] do
      with true <- request["workflow"] == "develop" and is_nil(request["base_revision_id"]) or {:error, :new_requires_develop_and_null_base},
           true <- is_nil(get_in(request, ["options", "brief_item_id"])) or {:error, :new_cannot_reference_existing_brief} do
        root = Fount.Screenplay.new()
        brief = get_in(request, ["options", "brief"])
        root = if is_map(brief) do
          id = Fount.ID.v4()
          item = %{"id" => id, "kind" => "brief", "target" => %{"kind" => "screenplay", "id" => root.id}, "namespace" => "writer", "value" => brief, "dependencies" => [], "status" => "active", "provenance" => %{"source" => "writer"}}
          Fount.Screenplay.Model.refresh(%{root | authored_items: Map.put(root.authored_items, id, item)})
        else root end
        anchored = Map.put(request, "base_revision_id", root.revision.id)
        with {:ok, validated} <- FountWorkshop.Request.validate(root, anchored),
             {:ok, saved} <- Store.call(services.store, :create, [opts[:key], root, [actor: opts[:actor] || "writer"]]) do
          {:ok, saved, validated}
        end
      end
    else
      with {:ok, model} <- S.load(services.store.repo, opts), do: {:ok, model, request}
    end
  end
  defp review(opts, candidate) do
    if opts[:review] do
      with {:ok, review} <- S.json_file(opts[:review]),
           true <- review["actor"] == opts[:actor] or {:error, :review_actor_mismatch} do {:ok, review} end
    else
      # Running fount.accept with explicit actor is the decision, not an automatic action by generation.
      {:ok, %{"candidate_id" => candidate["id"], "content_hash" => candidate["screenplay"].revision.content_hash,
        "actor" => opts[:actor], "report_ids" => candidate["provenance"]["report_ids"] || [], "overrides" => []}}
    end
  end
  defp candidate_result(c, opts, services) do
    with {:ok, packet} <- FountWorkshop.Review.export(c["session_id"], opts[:output], services, runtime_opts(opts)) do
      {:ok, %{"candidate_id" => c["id"], "review" => packet}}
    end
  end
  def export_result({:ok, session}, output, services, opts), do: FountWorkshop.Review.export(session["id"], output, services, opts)
  def export_result({:error, reason, session}, output, services, opts) do
    _ = FountWorkshop.Review.export(session["id"], output, services, opts)
    {:error, reason, session}
  end
  def export_result(error, _, _, _), do: error
  def runtime_opts(opts), do: [output_dir: opts[:output], render: opts[:pdf] || false, pdf: opts[:pdf] || false, speech: opts[:speech] || false, actor: opts[:actor]]
  defp help(command), do: "mix fount.#{command}; required: " <> Enum.map_join(@required[command], " ", &("--" <> (Atom.to_string(&1) |> String.replace("_", "-")) <> " VALUE")) <> "; see guides/creative-workflows.md for request examples"
end
