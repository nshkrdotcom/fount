defmodule FountWorkshop.Discovery do
  @moduledoc """
  Writer-owned discovery material stored with a durable Workshop session.

  Discovery state is deliberately noncanonical. Brief changes, fragments, reverse outlines,
  card reorder proposals and writer decisions live in session progress until the writer
  explicitly turns material into a candidate and accepts that candidate through the normal
  review boundary.
  """

  alias Fount.Screenplay.Model
  alias FountWorkshop.Acceptance
  alias FountWorkshop.Store

  @brief_fields ~w(desired_experience current_question audience_context formal_constraints protected_strengths permission_to_depart)
  @fragment_kinds ~w(image line action relationship research_question ending fragment)
  @classifications ~w(wanted connective)
  @modes ~w(draft explore inspect revise)

  @doc false
  def initial(request) do
    opts = request["options"] || %{}
    supplied_brief = if is_map(opts["brief"]), do: opts["brief"], else: %{}
    protected = opts["protected_strengths"] || supplied_brief["protected_strengths"] || []
    pending = opts["pending_question"] || supplied_brief["current_question"]

    %{
      "current_mode" => public_mode(request["mode"]),
      "mode_history" => [
        %{"mode" => public_mode(request["mode"]), "source" => "request", "at" => timestamp()}
      ],
      "brief" => %{
        "desired_experience" => opts["intended_effect"] || supplied_brief["desired_experience"],
        "current_question" => pending,
        "audience_context" => supplied_brief["audience_context"],
        "formal_constraints" => supplied_brief["formal_constraints"] || [],
        "protected_strengths" => protected,
        "permission_to_depart" =>
          Map.get(
            supplied_brief,
            "permission_to_depart",
            Map.get(opts, "allow_brief_departure", false)
          )
      },
      "brief_history" => [],
      "fragments" => [],
      "card_reorders" => [],
      "decisions" => [],
      "pending_question" => pending,
      "selected_candidate_id" => nil
    }
  end

  @doc "Returns the noncanonical discovery state saved with a session."
  def get(session_id, services) do
    with :ok <- store_service(services),
         {:ok, session} <- Store.call(services[:store], :session, [session_id]) do
      {:ok, state(session)}
    end
  end

  @doc "Explicitly changes the current writer mode without mutating the immutable request."
  def switch_mode(session_id, mode, services, opts \\ [])

  def switch_mode(session_id, mode, services, opts) when mode in @modes do
    update(session_id, services, fn discovery ->
      if discovery["current_mode"] == mode do
        {:ok, discovery}
      else
        actor = Keyword.get(opts, :actor, "writer")

        {:ok,
         discovery
         |> Map.put("current_mode", mode)
         |> Map.update!("mode_history", fn history ->
           history ++ [%{"mode" => mode, "source" => actor, "at" => timestamp()}]
         end)}
      end
    end)
  end

  def switch_mode(_session_id, _mode, _services, _opts), do: {:error, :invalid_session_mode}

  @doc "Updates only declared evolving-brief fields and retains the prior values in history."
  def update_brief(session_id, patch, services, opts \\ [])

  def update_brief(session_id, patch, services, opts) when is_map(patch) do
    with :ok <- validate_brief_patch(patch),
         :ok <- store_service(services),
         {:ok, session} <- Store.call(services[:store], :session, [session_id]) do
      old = state(session)["brief"] || %{}
      next = Map.merge(old, patch)

      save_discovery(session, services, &put_brief(&1, old, next, patch, opts), next)
    end
  end

  def update_brief(_session_id, _patch, _services, _opts), do: {:error, :invalid_brief_patch}

  defp put_brief(discovery, old, next, patch, opts) do
    history = %{
      "at" => timestamp(),
      "actor" => Keyword.get(opts, :actor, "writer"),
      "before" => Map.take(old, Map.keys(patch)),
      "after" => Map.take(next, Map.keys(patch))
    }

    discovery =
      discovery
      |> Map.put("brief", next)
      |> Map.update("brief_history", [history], &(&1 ++ [history]))

    if Map.has_key?(patch, "current_question"),
      do: Map.put(discovery, "pending_question", patch["current_question"]),
      else: discovery
  end

  @doc "Captures wanted material before its screenplay placement is known."
  def add_fragment(session_id, attrs, services, opts \\ [])

  def add_fragment(session_id, attrs, services, opts) when is_map(attrs) do
    with {:ok, fragment} <- fragment(attrs, opts),
         :ok <- validate_fragment_scene(session_id, fragment["scene_id"], services),
         :ok <- store_service(services),
         {:ok, session} <- Store.call(services[:store], :session, [session_id]) do
      save_discovery(
        session,
        services,
        fn discovery ->
          Map.update(discovery, "fragments", [fragment], &(&1 ++ [fragment]))
        end,
        fragment
      )
    end
  end

  def add_fragment(_session_id, _attrs, _services, _opts), do: {:error, :invalid_fragment}

  @doc "Links an existing fragment to a canonical scene identity without changing screenplay pages."
  def link_fragment(session_id, fragment_id, scene_id, services, opts \\ []) do
    mutate_fragment(session_id, fragment_id, services, fn session, fragment ->
      with {:ok, model} <- base_model(session, services),
           true <- not is_nil(Fount.Query.scene(model, scene_id)) or {:error, :unknown_scene},
           true <- fragment["status"] != "retired" or {:error, :fragment_retired} do
        {:ok,
         fragment
         |> Map.put("scene_id", scene_id)
         |> Map.put("status", if(fragment["status"] == "adopted", do: "adopted", else: "linked"))
         |> history("linked", opts, %{"scene_id" => scene_id})}
      end
    end)
  end

  @doc "Changes whether a fragment is wanted material or connective material without losing history."
  def classify_fragment(session_id, fragment_id, classification, services, opts \\ [])

  def classify_fragment(session_id, fragment_id, classification, services, opts)
      when classification in @classifications do
    mutate_fragment(session_id, fragment_id, services, fn _session, fragment ->
      {:ok,
       fragment
       |> Map.put("classification", classification)
       |> history("classified", opts, %{"classification" => classification})}
    end)
  end

  def classify_fragment(_session_id, _fragment_id, _classification, _services, _opts),
    do: {:error, :invalid_fragment_classification}

  @doc "Retires a fragment while retaining it and its full history."
  def retire_fragment(session_id, fragment_id, services, opts \\ []) do
    mutate_fragment(session_id, fragment_id, services, fn _session, fragment ->
      {:ok,
       fragment
       |> Map.put("status", "retired")
       |> history("retired", opts, %{})}
    end)
  end

  @doc "Records explicit adoption into an existing candidate; it does not accept that candidate."
  def adopt_fragment(session_id, fragment_id, candidate_id, services, opts \\ []) do
    mutate_fragment(session_id, fragment_id, services, fn _session, fragment ->
      with {:ok, candidate} <- Store.call(services[:store], :candidate, [candidate_id]),
           true <- candidate["session_id"] == session_id or {:error, :candidate_session_mismatch},
           true <- fragment["status"] != "retired" or {:error, :fragment_retired} do
        {:ok,
         fragment
         |> Map.put("status", "adopted")
         |> Map.put("adopted_candidate_id", candidate_id)
         |> Map.put("adopted_revision_id", candidate["screenplay"].revision.id)
         |> history("adopted", opts, %{"candidate_id" => candidate_id})}
      end
    end)
  end

  @doc "Returns a source-identity reverse outline; inferred functions remain labeled interpretations."
  def reverse_outline(session_id, services, interpretations \\ %{})
      when is_map(interpretations) do
    with :ok <- store_service(services),
         {:ok, session} <- Store.call(services[:store], :session, [session_id]),
         {:ok, model} <- base_model(session, services) do
      cards =
        model.ir.scenes
        |> Enum.with_index(1)
        |> Enum.map(fn {scene, ordinal} ->
          heading = Fount.Query.node(model, scene.heading_id)
          interpretation = Map.get(interpretations, scene.id)

          %{
            "scene_id" => scene.id,
            "ordinal" => ordinal,
            "heading_element_id" => scene.heading_id,
            "heading" => heading && heading.text,
            "element_ids" => scene.element_ids,
            "function" => interpretation,
            "function_status" => if(is_nil(interpretation), do: "unknown", else: "interpretation")
          }
        end)

      {:ok,
       %{
         "screenplay_id" => model.id,
         "revision_id" => model.revision.id,
         "cards" => cards,
         "changes_canon" => false
       }}
    end
  end

  @doc "Persists a proposed scene-card order as a branch plan; canonical order is unchanged."
  def propose_reorder(session_id, scene_ids, services, opts \\ [])

  def propose_reorder(session_id, scene_ids, services, opts) when is_list(scene_ids) do
    with :ok <- store_service(services),
         {:ok, session} <- Store.call(services[:store], :session, [session_id]),
         {:ok, model} <- base_model(session, services),
         :ok <- exact_scene_permutation(model, scene_ids) do
      proposal = %{
        "id" => Fount.ID.v4(),
        "base_revision_id" => model.revision.id,
        "scene_ids" => scene_ids,
        "status" => "proposed",
        "actor" => Keyword.get(opts, :actor, "writer"),
        "created_at" => timestamp(),
        "changes_canon" => false
      }

      save_discovery(
        session,
        services,
        fn discovery ->
          Map.update(discovery, "card_reorders", [proposal], &(&1 ++ [proposal]))
        end,
        proposal
      )
    end
  end

  def propose_reorder(_session_id, _scene_ids, _services, _opts),
    do: {:error, :invalid_scene_order}

  @doc "Stores one unresolved question for the next invocation without triggering analysis."
  def set_pending_question(session_id, question, services, opts \\ [])
      when is_binary(question) or is_nil(question) do
    if is_binary(question) and String.trim(question) == "" do
      {:error, :invalid_pending_question}
    else
      update(session_id, services, fn discovery ->
        decision = %{
          "action" => "pending_question",
          "value" => question,
          "actor" => Keyword.get(opts, :actor, "writer"),
          "at" => timestamp()
        }

        brief = Map.put(discovery["brief"] || %{}, "current_question", question)

        {:ok,
         discovery
         |> Map.put("brief", brief)
         |> Map.put("pending_question", question)
         |> Map.update("decisions", [decision], &(&1 ++ [decision]))}
      end)
    end
  end

  @doc "Keeps multiple candidates alive as an explicit writer decision; no candidate becomes canon."
  def keep_both(session_id, candidate_ids, services, opts \\ [])

  def keep_both(session_id, candidate_ids, services, opts)
      when is_list(candidate_ids) and length(candidate_ids) >= 2 do
    with {:ok, _} <- session_candidates(session_id, candidate_ids, services) do
      record_decision(session_id, "keep_both", candidate_ids, services, opts)
    end
  end

  def keep_both(_session_id, _candidate_ids, _services, _opts),
    do: {:error, :keep_both_requires_candidates}

  @doc "Rejects each supplied candidate explicitly and records the aggregate none-of-these decision."
  def reject_all(session_id, candidate_ids, actor, services, opts \\ [])

  def reject_all(session_id, candidate_ids, actor, services, opts)
      when is_list(candidate_ids) and candidate_ids != [] and is_binary(actor) do
    with true <- String.trim(actor) != "" or {:error, :missing_actor},
         {:ok, _} <- session_candidates(session_id, candidate_ids, services),
         :ok <- reject_each(candidate_ids, actor, services) do
      record_decision(
        session_id,
        "reject_all",
        candidate_ids,
        services,
        Keyword.put(opts, :actor, actor)
      )
    end
  end

  def reject_all(_session_id, _candidate_ids, _actor, _services, _opts),
    do: {:error, :invalid_reject_all}

  @doc "Records the candidate selected by an explicit acceptance action for resume presentation."
  def record_acceptance(session_id, candidate_id, services, opts \\ []) do
    with {:ok, [candidate]} <- session_candidates(session_id, [candidate_id], services),
         true <-
           candidate["decision"] in ["accepted", :accepted] or {:error, :candidate_not_accepted} do
      update(session_id, services, fn discovery ->
        decision = %{
          "action" => "accepted",
          "candidate_ids" => [candidate_id],
          "actor" => Keyword.get(opts, :actor, "writer"),
          "at" => timestamp()
        }

        {:ok,
         discovery
         |> Map.put("selected_candidate_id", candidate_id)
         |> Map.update("decisions", [decision], &(&1 ++ [decision]))}
      end)
    end
  end

  defp record_decision(session_id, action, candidate_ids, services, opts) do
    update(session_id, services, fn discovery ->
      decision = %{
        "action" => action,
        "candidate_ids" => candidate_ids,
        "actor" => Keyword.get(opts, :actor, "writer"),
        "at" => timestamp()
      }

      {:ok, Map.update(discovery, "decisions", [decision], &(&1 ++ [decision]))}
    end)
  end

  defp reject_each(candidate_ids, actor, services) do
    Enum.reduce_while(candidate_ids, :ok, fn id, :ok ->
      case Acceptance.reject(id, actor, services) do
        {:ok, _} -> {:cont, :ok}
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp session_candidates(session_id, candidate_ids, services) do
    with :ok <- store_service(services) do
      Enum.reduce_while(candidate_ids, {:ok, []}, fn id, {:ok, acc} ->
        session_candidate(id, session_id, services, acc)
      end)
    end
  end

  defp session_candidate(id, session_id, services, acc) do
    case Store.call(services[:store], :candidate, [id]) do
      {:ok, %{"session_id" => ^session_id} = candidate} -> {:cont, {:ok, acc ++ [candidate]}}
      {:ok, _} -> {:halt, {:error, :candidate_session_mismatch}}
      error -> {:halt, error}
    end
  end

  defp mutate_fragment(session_id, fragment_id, services, fun) do
    with :ok <- store_service(services),
         {:ok, session} <- Store.call(services[:store], :session, [session_id]) do
      discovery = state(session)
      fragments = discovery["fragments"] || []

      index = Enum.find_index(fragments, &(&1["id"] == fragment_id))
      replace_fragment(index, fragments, discovery, session, services, fun)
    end
  end

  defp replace_fragment(nil, _fragments, _discovery, _session, _services, _fun),
    do: {:error, :unknown_fragment}

  defp replace_fragment(index, fragments, discovery, session, services, fun) do
    with {:ok, next_fragment} <- fun.(session, Enum.at(fragments, index)) do
      next = Map.put(discovery, "fragments", List.replace_at(fragments, index, next_fragment))
      save_discovery(session, services, fn _ -> next end, next_fragment)
    end
  end

  defp update(session_id, services, fun) do
    with :ok <- store_service(services),
         {:ok, session} <- Store.call(services[:store], :session, [session_id]),
         {:ok, next} <- fun.(state(session)) do
      save_discovery(session, services, fn _ -> next end, next)
    end
  end

  defp save_discovery(session, services, fun, result) do
    discovery = fun.(state(session))
    updated = put_in(session, ["progress", "discovery"], discovery)

    case Store.call(services[:store], :save_session, [updated]) do
      {:ok, _saved} -> {:ok, result}
      error -> error
    end
  end

  defp state(session) do
    get_in(session, ["progress", "discovery"]) || initial(session["request"] || %{})
  end

  defp fragment(attrs, opts) do
    kind = attrs["kind"]
    content = attrs["content"]
    scene_id = attrs["scene_id"]
    classification = Map.get(attrs, "classification", "wanted")

    with :ok <- validate_fragment_kind(kind),
         :ok <- validate_fragment_content(content),
         :ok <- validate_fragment_scene_id(scene_id),
         :ok <- validate_fragment_classification(classification),
         :ok <- validate_fragment_fields(attrs) do
      id = Fount.ID.v4()
      status = if(scene_id, do: "linked", else: "unattached")

      {:ok,
       %{
         "id" => id,
         "kind" => kind,
         "content" => Model.plain(content),
         "scene_id" => scene_id,
         "classification" => classification,
         "status" => status,
         "history" => [
           %{
             "action" => "captured",
             "actor" => Keyword.get(opts, :actor, "writer"),
             "at" => timestamp()
           }
         ]
       }}
    end
  end

  defp validate_fragment_kind(kind),
    do: if(kind in @fragment_kinds, do: :ok, else: {:error, :invalid_fragment_kind})

  defp validate_fragment_content(nil), do: {:error, :missing_fragment_content}

  defp validate_fragment_content(content) when is_binary(content),
    do: if(String.trim(content) == "", do: {:error, :missing_fragment_content}, else: :ok)

  defp validate_fragment_content(_), do: :ok

  defp validate_fragment_scene_id(scene_id),
    do:
      if(is_nil(scene_id) or is_binary(scene_id),
        do: :ok,
        else: {:error, :invalid_fragment_scene}
      )

  defp validate_fragment_classification(classification),
    do:
      if(classification in @classifications,
        do: :ok,
        else: {:error, :invalid_fragment_classification}
      )

  defp validate_fragment_fields(attrs),
    do:
      if(Map.keys(attrs) -- ~w(kind content scene_id classification) == [],
        do: :ok,
        else: {:error, :unknown_fragment_field}
      )

  defp history(fragment, action, opts, detail) do
    event =
      detail
      |> Map.merge(%{
        "action" => action,
        "actor" => Keyword.get(opts, :actor, "writer"),
        "at" => timestamp()
      })

    Map.update(fragment, "history", [event], &(&1 ++ [event]))
  end

  defp validate_brief_patch(patch) do
    with :ok <- validate_brief_fields(patch),
         :ok <- validate_brief_permission(patch),
         :ok <- validate_brief_lists(patch) do
      validate_brief_text(patch)
    end
  end

  defp validate_brief_fields(patch),
    do: if(Map.keys(patch) -- @brief_fields == [], do: :ok, else: {:error, :unknown_brief_field})

  defp validate_brief_permission(patch) do
    value = patch["permission_to_depart"]

    if Map.has_key?(patch, "permission_to_depart") and not (is_boolean(value) or is_nil(value)),
      do: {:error, :invalid_permission_to_depart},
      else: :ok
  end

  defp validate_brief_lists(patch) do
    invalid? =
      Enum.any?(~w(formal_constraints protected_strengths), fn key ->
        Map.has_key?(patch, key) and
          (not is_list(patch[key]) or Enum.any?(patch[key], &(not is_binary(&1))))
      end)

    if invalid?, do: {:error, :invalid_brief_list}, else: :ok
  end

  defp validate_brief_text(patch) do
    invalid? =
      Enum.any?(~w(desired_experience current_question audience_context), fn key ->
        Map.has_key?(patch, key) and not is_nil(patch[key]) and not is_binary(patch[key])
      end)

    if invalid?, do: {:error, :invalid_brief_text}, else: :ok
  end

  defp exact_scene_permutation(model, scene_ids) do
    canonical = Enum.map(model.ir.scenes, & &1.id)

    if length(scene_ids) == length(canonical) and Enum.sort(scene_ids) == Enum.sort(canonical),
      do: :ok,
      else: {:error, :scene_order_must_be_exact_permutation}
  end

  defp validate_fragment_scene(_session_id, nil, services), do: store_service(services)

  defp validate_fragment_scene(session_id, scene_id, services) when is_binary(scene_id) do
    with :ok <- store_service(services),
         {:ok, session} <- Store.call(services[:store], :session, [session_id]),
         {:ok, model} <- base_model(session, services),
         true <- not is_nil(Fount.Query.scene(model, scene_id)) or {:error, :unknown_scene} do
      :ok
    end
  end

  defp validate_fragment_scene(_session_id, _scene_id, _services),
    do: {:error, :invalid_fragment_scene}

  defp base_model(session, services),
    do:
      Store.call(services[:store], :load_revision, [
        session["screenplay_id"],
        session["base_revision_id"]
      ])

  defp store_service(%{store: %Store{}}), do: :ok
  defp store_service(_), do: {:error, :explicit_store_required}

  defp public_mode("diagnose"), do: "inspect"
  defp public_mode(mode) when mode in @modes, do: mode
  defp public_mode(_), do: "revise"

  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
