defmodule FountProbe.Jev do
  @moduledoc "Typed public SDK execution with exact association and explicit missing answers."
  alias FountProbe.Writing.{Executor, DecisionPolicy}
  alias Fount.Writing.CanonicalJSON

  def evaluate(client, inputs, questions, opts \\ []) do
    with {:ok, questions, profile} <-
           FountProbe.Profile.compile(questions, Keyword.get(opts, :profile_id)) do
      evaluate_compiled(client, inputs, questions, profile, opts)
    end
  end

  defp evaluate_compiled(client, inputs, questions, profile, opts) do
    limit = Keyword.get(opts, :max_states, 500)
    max_bytes = Keyword.get(opts, :max_context_bytes, 100_000)
    {scheduled, pending} = Enum.split(inputs, max(limit, 0))

    {eligible, oversize} =
      Enum.split_with(scheduled, &(byte_size(CanonicalJSON.encode!(&1["state"])) <= max_bytes))

    rejected =
      Enum.map(pending, &error(&1["id"], "state_limit")) ++
        Enum.map(oversize, &error(&1["id"], "context_limit"))

    count = FountProbe.Budget.take(Keyword.get(opts, :budget), :jev_states, length(eligible))
    {eligible, budget_pending} = Enum.split(eligible, count)
    rejected = rejected ++ Enum.map(budget_pending, &error(&1["id"], "session_jev_limit"))

    requests =
      Enum.map(eligible, &%{"id" => &1["id"], "state" => CanonicalJSON.encode!(&1["state"])})

    result =
      cond do
        requests == [] ->
          {:ok, %{"entries" => [], "errors" => [], "status" => "complete"}}

        is_nil(client) ->
          {:error, :missing_system_one_client}

        true ->
          Executor.evaluate(
            client,
            requests,
            questions,
            Keyword.take(opts, [
              :max_concurrency,
              :max_pending,
              :task_timeout_ms,
              :attempt_timeout_ms
            ])
          )
      end

    case result do
      {:error, reason} ->
        {:error, reason}

      {:ok, batch} ->
        entries = Enum.map(batch["entries"], &decode_entry(&1, questions)) ++ rejected
        by_id = Map.new(entries, &{&1["input_id"], &1})
        ordered = Enum.map(inputs, &Map.get(by_id, &1["id"], error(&1["id"], "missing_response")))

        {:ok,
         %{
           "entries" => ordered,
           "status" =>
             if(Enum.all?(ordered, &(&1["status"] == "complete")),
               do: "complete",
               else: "partial"
             ),
           "errors" => batch["errors"] || [],
           "requested" => length(inputs),
           "scheduled" => length(eligible),
           "prepared_fingerprint" => batch["prepared_fingerprint"],
           "elapsed_ms" => batch["elapsed_ms"],
           "question_profile_sha256" => CanonicalJSON.hash(question_profile(questions)),
           "question_profile" => question_profile(questions),
           "profile_asset" => profile,
           "state_hashes" => Map.new(inputs, &{&1["id"], CanonicalJSON.hash(&1["state"])})
         }}
    end
  end

  def question_profile(questions) do
    Enum.map(questions, fn {key, question} ->
      %{"key" => to_string(key), "definition" => Fount.Screenplay.Model.plain(question)}
    end)
  end

  defp decode_entry(%{"input_id" => id, "result" => {:ok, response}}, questions) do
    answers = Map.get(response, :answers) || %{}

    decoded =
      Map.new(questions, fn {key, _} ->
        answer = Map.get(answers, key, Map.get(answers, to_string(key)))
        {to_string(key), answer(answer)}
      end)

    valid = Enum.all?(decoded, fn {_, result} -> result["status"] != "error" end)

    %{
      "input_id" => id,
      "status" => if(valid, do: "complete", else: "partial"),
      "answers" => decoded,
      "provenance" =>
        Fount.Screenplay.Model.plain(
          Map.take(response, [:model, :usage, :request_id, :prepared_fingerprint])
        )
    }
  end

  defp decode_entry(%{"input_id" => id, "result" => {:error, reason}}, _),
    do: error(id, safe_reason(reason))

  defp decode_entry(entry, _), do: error(entry["input_id"], "missing_response")

  def answer(%SystemOneSDK.NoulAnswer{noul: p}) do
    case DecisionPolicy.noul(p) do
      {:ok, policy} -> Map.merge(policy, %{"type" => "noul"})
      _ -> %{"status" => "error", "reason" => "invalid_noul"}
    end
  end

  def answer(%SystemOneSDK.ChoiceAnswer{} = a) do
    probabilities = Map.new(a.probabilities, fn {key, p} -> {to_string(key), p} end)
    order = Enum.map(a.option_order, &to_string/1)

    case DecisionPolicy.choice(probabilities, order, a.confidence) do
      {:ok, policy} -> Map.merge(policy, %{"type" => "choice"})
      _ -> %{"status" => "error", "reason" => "invalid_choice"}
    end
  end

  def answer(%SystemOneSDK.ScoreAnswer{} = a) do
    probabilities = Map.new(a.probabilities, fn {key, p} -> {to_string(key), p} end)

    with true <- is_number(a.score),
         {:ok, _} <-
           DecisionPolicy.semantic_distribution(
             probabilities,
             Map.keys(probabilities),
             a.confidence
           ),
         true <- abs(Enum.sum(Map.values(probabilities)) - 1.0) <= 0.02 do
      %{
        "type" => "score",
        "score" => a.score,
        "probabilities" => probabilities,
        "confidence" => a.confidence,
        "status" => "complete",
        "rubric" => Fount.Screenplay.Model.plain(a.rubric)
      }
    else
      _ -> %{"status" => "error", "reason" => "invalid_score_distribution"}
    end
  end

  def answer(_), do: %{"status" => "error", "reason" => "missing_or_unknown_answer"}

  defp error(id, reason),
    do: %{"input_id" => id, "status" => "error", "error" => reason, "answers" => %{}}

  defp safe_reason(%{__struct__: module}), do: inspect(module)
  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason(_), do: "provider_error"
end
