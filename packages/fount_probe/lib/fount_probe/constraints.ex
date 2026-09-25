defmodule FountProbe.Constraints do
  @moduledoc "Writer constraints: exact protection is mechanical; semantic uncertainty is reviewable, never silently passed."
  alias FountProbe.{Projection, Jev, Report}
  alias Fount.Writing.UTF8Span

  @kinds ~w(pin_text retain_ids remove_ids relative_order word_limit scene_count page_goal semantic invention_policy)
  @semantic_keys ~w(proposition question_type question profile_id projection point at character_id expected allowed criteria levels probability_range selection)

  def resolve(model, constraints) when is_list(constraints) do
    Enum.reduce_while(constraints, {:ok, []}, fn value, {:ok, acc} ->
      c =
        if is_binary(value),
          do: model.authored_items[value] && model.authored_items[value]["value"],
          else: value

      case validate(c) do
        :ok -> {:cont, {:ok, acc ++ [adopt(c)]}}
        error -> {:halt, error}
      end
    end)
  end

  def resolve(_, _), do: {:error, :invalid_constraints}

  def validate(
        %{"id" => id, "kind" => kind, "target" => target, "spec" => spec, "severity" => severity} =
          c
      )
      when is_binary(id) and id != "" and is_map(target) and is_map(spec) and kind in @kinds and
             severity in ["required", "advisory"] do
    unknown = Map.keys(c) -- ~w(id kind target spec severity source)

    valid =
      case kind do
        "pin_text" ->
          is_binary(spec["text"]) and spec["text"] != ""

        k when k in ["retain_ids", "remove_ids"] ->
          is_list(spec["ids"]) and spec["ids"] != [] and
            Enum.all?(spec["ids"], &(is_binary(&1) or valid_target?(&1)))

        "relative_order" ->
          (valid_target?(spec["before"]) and valid_target?(spec["after"])) or
            (is_list(spec["ids"]) and length(spec["ids"]) > 1)

        k when k in ["word_limit", "scene_count", "page_goal"] ->
          Enum.any?(
            ~w(minimum maximum reduce_by min max exact reduction),
            &(is_number(spec[&1]) and spec[&1] >= 0)
          )

        "invention_policy" ->
          is_list(Map.get(spec, "allowed_categories", Map.get(spec, "allowed", []))) and
            is_list(Map.get(spec, "prohibited_facts", []))

        "semantic" ->
          semantic_valid?(spec)
      end

    if unknown == [] and valid, do: :ok, else: {:error, {:invalid_constraint, id}}
  end

  def validate(_), do: {:error, :invalid_constraint}

  defp valid_target?(%{"kind" => kind, "id" => id}) when is_binary(kind) and is_binary(id),
    do: true

  defp valid_target?(_), do: false
  defp adopt(%{"source" => "suggested"} = c), do: Map.put(c, "severity", "advisory")
  defp adopt(c), do: c

  defp normalize(c) do
    s = c["spec"]

    s =
      Enum.reduce(
        [{"minimum", "min"}, {"maximum", "max"}, {"reduce_by", "reduction"}, {"at", "point"}],
        s,
        fn {from, to}, acc ->
          if Map.has_key?(acc, from), do: Map.put(acc, to, acc[from]), else: acc
        end
      )

    s =
      if (c["kind"] == "relative_order" and s["before"]) && s["after"],
        do: Map.put(s, "ids", [s["before"], s["after"]]),
        else: s

    s =
      if is_list(s["ids"]),
        do: Map.update!(s, "ids", &Enum.map(&1, fn v -> if is_map(v), do: v["id"], else: v end)),
        else: s

    c |> adopt() |> Map.put("spec", s)
  end

  defp semantic_valid?(s) do
    type = Map.get(s, "question_type", "noul")

    region =
      case type do
        "noul" ->
          is_boolean(Map.get(s, "expected", true))

        "choice" ->
          is_map(s["criteria"]) and map_size(s["criteria"]) >= 2 and is_list(s["allowed"]) and
            s["allowed"] != [] and Enum.all?(s["allowed"], &Map.has_key?(s["criteria"], &1))

        "score" ->
          is_list(s["levels"]) and length(s["levels"]) in 2..10 and is_list(s["allowed"]) and
            s["allowed"] != [] and
            Enum.all?(s["allowed"], &(is_integer(&1) and &1 >= 0 and &1 < length(s["levels"])))

        _ ->
          false
      end

    region and is_binary(s["proposition"]) and String.trim(s["proposition"]) != "" and
      Map.get(s, "projection", "page_reader") in ~w(page_reader audience_estimate character_access) and
      Map.keys(s) -- @semantic_keys == []
  end

  def deterministic(base, model, constraints, opts \\ []) do
    Enum.map(constraints, fn original ->
      c = normalize(original)

      result =
        try do
          deterministic_one(base, model, c, opts)
        rescue
          _ -> %{"status" => "unresolved", "reason" => "invalid_or_missing_target"}
        end

      Map.merge(
        %{
          "constraint_id" => c["id"],
          "kind" => c["kind"],
          "severity" => c["severity"],
          "evaluation" =>
            if(c["kind"] == "semantic",
              do: "semantic",
              else: if(c["kind"] == "page_goal", do: "external", else: "deterministic")
            )
        },
        result
      )
    end)
  end

  defp deterministic_one(base, model, %{"kind" => "pin_text", "target" => target, "spec" => s}, _) do
    with {:ok, before} <- Fount.Target.resolve(base, target),
         true <- is_binary(Map.get(before, :text)),
         :ok <- verify_pin_base(before.text, target["span"], s["text"]),
         {:ok, after_value} <- Fount.Target.resolve(model, target),
         true <- is_binary(Map.get(after_value, :text)),
         {:ok, {first, last}} <- UTF8Span.relocate(after_value.text, s["text"]) do
      %{
        "status" => "pass",
        "measurements" => %{"candidate_span" => %{"byte_start" => first, "byte_end" => last}}
      }
    else
      error -> %{"status" => "fail", "reason" => inspect(error)}
    end
  end

  defp deterministic_one(_, model, %{"kind" => kind, "spec" => %{"ids" => ids}}, _)
       when kind in ["retain_ids", "remove_ids"] do
    all = ids(model)

    ok =
      if kind == "retain_ids",
        do: Enum.all?(ids, &MapSet.member?(all, &1)),
        else: Enum.all?(ids, &(not MapSet.member?(all, &1)))

    status(ok, %{"ids" => ids})
  end

  defp deterministic_one(_, model, %{"kind" => "relative_order", "spec" => %{"ids" => ids}}, _) do
    order = Enum.flat_map(model.ir.scenes, fn s -> [s.id | s.element_ids] end)
    positions = Enum.map(ids, fn sought -> Enum.find_index(order, fn id -> id == sought end) end)

    status(
      not Enum.any?(positions, &is_nil/1) and positions == Enum.sort(positions) and
        length(Enum.uniq(positions)) == length(positions),
      %{"positions" => positions}
    )
  end

  defp deterministic_one(
         _,
         model,
         %{"kind" => "word_limit", "target" => target, "spec" => spec},
         _
       ) do
    case Projection.select(model, %{"targets" => [target]}) do
      {:ok, units} ->
        types =
          case spec["scope"] do
            "dialogue" -> ["dialogue", "lyric"]
            "action" -> ["action"]
            _ -> ["action", "dialogue", "parenthetical", "lyric"]
          end

        count =
          units
          |> Enum.filter(&(&1["type"] in types))
          |> Enum.map(&words(&1["text"]))
          |> Enum.sum()

        status(in_range?(count, spec), %{
          "words" => count,
          "scope" => spec["scope"] || "performed"
        })

      _ ->
        %{"status" => "unresolved"}
    end
  end

  defp deterministic_one(_, model, %{"kind" => "scene_count", "spec" => spec}, opts) do
    ids = Keyword.get(opts, :scene_ids)
    count = Enum.count(model.ir.scenes, &(not &1.omitted? and (is_nil(ids) or &1.id in ids)))
    status(in_range?(count, spec), %{"scene_count" => count})
  end

  defp deterministic_one(_, _, %{"kind" => "page_goal", "spec" => spec}, opts) do
    case Keyword.get(opts, :layout) do
      %{"base_pages" => before, "candidate_pages" => after_pages, "same_settings" => true}
      when is_integer(before) and is_integer(after_pages) ->
        ok =
          if spec["reduction"],
            do: before - after_pages >= spec["reduction"],
            else: in_range?(after_pages, spec)

        status(ok, %{
          "base_pages" => before,
          "candidate_pages" => after_pages,
          "saved_pages" => before - after_pages
        })

      _ ->
        %{"status" => "unknown", "reason" => "measured_pdf_pages_unavailable"}
    end
  end

  defp deterministic_one(_, _, %{"kind" => "invention_policy", "spec" => spec}, opts) do
    inventions = Keyword.get(opts, :inventions, [])
    allowed = Map.get(spec, "allowed_categories", Map.get(spec, "allowed", []))
    forbidden = Map.get(spec, "forbidden", [])

    invalid =
      Enum.filter(inventions, fn i ->
        i["category"] in forbidden or (allowed != [] and i["category"] not in allowed) or
          spec["policy"] == "none"
      end)

    # This verifies declared inventions only; undisclosed invention is a semantic inspection.
    status(invalid == [], %{"declared_inventions_only" => true, "violations" => invalid})
  end

  defp deterministic_one(_, _, %{"kind" => "semantic"}, _),
    do: %{"status" => "unknown", "reason" => "not_evaluated"}

  def run(model, params, clients, opts \\ []) do
    base = Keyword.get(opts, :base_model, model)

    with {:ok, constraints} <- resolve(base, params["constraints"]) do
      initial = deterministic(base, model, constraints, opts)
      semantic = Enum.filter(constraints, &(&1["kind"] == "semantic"))

      {evaluated, evidence, errors, traces} =
        Enum.reduce(semantic, {[], [], [], []}, fn c, {checks, evidence, errors, traces} ->
          case evaluate_one(model, c, clients[:system_one], opts) do
            {:ok, result, ev, trace} ->
              {[result | checks], ev ++ evidence, errors, [trace | traces]}

            {:error, reason} ->
              {[
                 %{
                   "constraint_id" => c["id"],
                   "kind" => "semantic",
                   "severity" => c["severity"],
                   "evaluation" => "semantic",
                   "status" => "unknown",
                   "reason" => inspect(reason)
                 }
                 | checks
               ], evidence,
               [%{"input_id" => c["id"], "code" => "semantic_check_failed"} | errors], traces}
          end
        end)

      by_id = Map.new(evaluated, &{&1["constraint_id"], &1})
      checks = Enum.map(initial, &Map.get(by_id, &1["constraint_id"], &1))

      {:ok,
       Report.new(model, "check_constraints", params, %{
         status: if(errors == [], do: "complete", else: "partial"),
         data: %{"checks" => checks},
         evidence: Enum.uniq_by(evidence, & &1["evidence_id"]),
         errors: errors,
         provenance: %{"evaluations" => Enum.reverse(traces)},
         coverage: %{"constraint_ids" => Enum.map(constraints, & &1["id"])}
       })}
    end
  end

  defp evaluate_one(model, c, client, opts) do
    c = normalize(c)
    spec = c["spec"]
    projection = Map.get(spec, "projection", "page_reader")

    state_result =
      if spec["point"] do
        with {:ok, point} <- Projection.resolve_point(model, spec["point"]) do
          Projection.at(
            model,
            point,
            projection,
            Keyword.put(opts, :character_id, spec["character_id"])
          )
        end
      else
        case Projection.select(model, Map.get(spec, "selection", %{"targets" => [c["target"]]})) do
          {:ok, units} when projection == "page_reader" ->
            {:ok,
             %{
               "projection" => projection,
               "material" => Projection.compact(units),
               "complete_context" => true
             }, Projection.evidence(units)}

          {:ok, _} ->
            {:error, :perspective_requires_point}

          error ->
            error
        end
      end

    with {:ok, state, evidence} <- state_result do
      state = Map.put(state, "proposition", spec["proposition"])

      question =
        case Map.get(spec, "question_type", "noul") do
          "noul" ->
            SystemOneSDK.noul(
              "Does the supplied material support the proposition? Assess the positive proposition, not the desired answer. Distinguish claims from facts."
            )

          "choice" ->
            SystemOneSDK.choice(
              "Classify the supplied material relative to the proposition.",
              spec["criteria"]
            )

          "score" ->
            SystemOneSDK.score(
              "Describe the supplied material on this specific rubric, not overall quality.",
              spec["levels"]
            )
        end

      with {:ok, result} <-
             Jev.evaluate(client, [%{"id" => c["id"], "state" => state}], [q: question], opts),
           [%{"status" => "complete", "answers" => %{"q" => answer}}] <- result["entries"] do
        interpreted = interpret(c, answer)

        interpreted =
          if state["complete_context"] == false and interpreted["status"] == "fail",
            do:
              Map.merge(interpreted, %{"status" => "uncertain", "reason" => "incomplete_access"}),
            else: interpreted

        {:ok,
         Map.merge(
           %{
             "constraint_id" => c["id"],
             "kind" => "semantic",
             "severity" => c["severity"],
             "evaluation" => "semantic"
           },
           interpreted
         ), evidence, result}
      else
        {:error, _} = error -> error
        _ -> {:error, :missing_semantic_answer}
      end
    end
  end

  def interpret(c, %{"type" => "noul", "probability" => p} = answer) when is_number(p) do
    spec = c["spec"]

    result =
      case spec["probability_range"] do
        [low, high] when is_number(low) and is_number(high) ->
          status(p >= low and p <= high, %{"probability" => p})

        _ ->
          {:ok, policy} =
            FountProbe.Writing.DecisionPolicy.semantic_noul(p, Map.get(spec, "expected", true))

          policy
      end

    Map.merge(answer, result)
  end

  def interpret(c, %{"probabilities" => probabilities, "confidence" => confidence} = answer) do
    allowed = Enum.map(c["spec"]["allowed"] || [], &to_string/1)

    case FountProbe.Writing.DecisionPolicy.semantic_distribution(
           probabilities,
           allowed,
           confidence
         ) do
      {:ok, policy} -> Map.merge(answer, policy)
      _ -> %{"status" => "unknown", "reason" => "invalid_allowed_region"}
    end
  end

  def interpret(_, _), do: %{"status" => "unknown", "reason" => "missing_answer"}

  defp verify_pin_base(text, nil, pin) do
    case UTF8Span.relocate(text, pin) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp verify_pin_base(text, span, pin), do: UTF8Span.verify(text, span, pin)

  defp in_range?(value, s),
    do:
      (is_nil(s["min"]) or value >= s["min"]) and (is_nil(s["max"]) or value <= s["max"]) and
        (is_nil(s["exact"]) or value == s["exact"])

  defp status(ok, measurements),
    do: %{"status" => if(ok, do: "pass", else: "fail"), "measurements" => measurements}

  defp words(text), do: length(Regex.scan(~r/[\p{L}\p{N}]+(?:['\x{2019}-][\p{L}\p{N}]+)*/u, text))

  defp ids(model),
    do:
      MapSet.new(
        Enum.map(model.ir.elements ++ model.ir.scenes ++ model.ir.dialogue_blocks, & &1.id) ++
          Map.keys(model.cast) ++ Map.keys(model.authored_items)
      )
end
