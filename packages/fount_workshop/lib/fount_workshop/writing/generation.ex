defmodule FountWorkshop.Writing.Generation do
  @moduledoc false
  alias FountWorkshop.{Candidate, Writing.Context}
  def propose(base, request, strategy, context, services, opts \\ [])

  def propose(
        base,
        %{"workflow" => "recover", "options" => %{"adapt" => false}} = request,
        strategy,
        context,
        _services,
        opts
      ),
      do: FountWorkshop.Writing.RecoveryCopy.propose(base, request, strategy, context, opts)

  def propose(base, request, strategy, context, services, opts) do
    schema = Fount.Writing.Schema.inline("proposal.schema.json")

    compile_opts =
      Context.compile_options(base, request, context, opts)
      |> Keyword.put(:strategy, strategy)
      |> Keyword.put(:label, strategy["title"])

    validate = fn proposal ->
      with true <- proposal["strategy_id"] == strategy["id"] or {:error, :wrong_strategy_id},
           :ok <- workflow_shape(request, proposal),
           {:ok, _} <- Candidate.compile(base, proposal, compile_opts) do
        :ok
      end
    end

    prompt =
      "Write actual complete screenplay pages as canonical typed edits for this chosen dramatic approach. The JSON proposal is the only output. Produce dialogue/action, not instructions to a future writer, placeholders or summaries. Preserve every unchanged element's exact text and identity using keep references. Use local_id new:<label> only for new identities. Link new cues to confirmed character IDs in attrs.character_id or create an explicitly disclosed cast entry first. Declare groups with causal depends_on links; a group must be independently meaningful with its dependencies. Never claim writer_edit or mixed origin. Quote only inspected evidence IDs. Do not mark notes resolved or change constraints/facts to make a check pass. IDs, constraints and placement are authoritative.\n" <>
        direction(request) <>
        "\n" <>
        Jason.encode!(%{
          "strategy" => strategy,
          "context" => context.data,
          "repair_feedback" => Keyword.get(opts, :repair_feedback),
          "source_candidate" => Keyword.get(opts, :source_candidate)
        })

    with {:ok, proposal, traces} <-
           FountProbe.Completion.complete(
             services[:inference],
             prompt,
             schema,
             validate,
             Keyword.put(opts, :name, "fount_candidate")
           ),
         {:ok, candidate} <- Candidate.compile(base, proposal, compile_opts) do
      provenance =
        candidate["provenance"]
        |> Map.put("completions", traces)
        |> Map.put("context_sha256", Fount.Writing.CanonicalJSON.hash(context.data))

      {:ok, Map.put(candidate, "provenance", provenance)}
    end
  end

  defp workflow_shape(%{"workflow" => "propagate"}, proposal) do
    groups = proposal["groups"] || []

    if length(groups) >= 2 and Enum.any?(groups, &(Map.get(&1, "depends_on", []) != [])),
      do: :ok,
      else: {:error, :story_change_requires_primary_and_dependent_repair_groups}
  end

  defp workflow_shape(%{"workflow" => "notes", "options" => opts}, proposal) do
    known = Map.get(opts, "note_ids", [])
    ids = Enum.flat_map(proposal["groups"] || [], &Map.get(&1, "addresses_notes", []))

    if known == [] or Enum.any?(ids, &(&1 in known)),
      do: :ok,
      else: {:error, :note_response_must_address_requested_notes}
  end

  defp workflow_shape(_, _), do: :ok

  defp direction(%{"workflow" => "develop"}),
    do:
      "DEVELOP: honor the exact placement. A bridge adds connective action between the retained neighboring scenes without rewriting either. Develop an empty project into a playable opening, not an outline."

  defp direction(%{"workflow" => "alternatives"}),
    do:
      "ALTERNATIVES: materialize this route as actual pages in continuous scene context. Preserve alternatives for writer audition; do not select a winner."

  defp direction(%{"workflow" => "propagate"}),
    do:
      "PROPAGATE: implement the primary story decision and write every justified consequence repair in the authorized repair scope. A delayed revelation must change earlier accusations or behavior that presuppose it, while retaining independent motivations and later setup/payoff obligations. Group repairs and cite their dependencies; do not replace specific repairs with a warning list."

  defp direction(%{"workflow" => "sequence"}),
    do:
      "SEQUENCE: replace exactly the selected contiguous sequence with the requested scene count, preserving specified entry/exit conditions and pins. Rebuild causality and playable beats. No claimed page savings until a real same-settings PDF comparison."

  defp direction(%{"workflow" => "character"}),
    do:
      "CHARACTER: revise the character across the whole authorized workspace, including physical choice, tactic and partner response. Do not rewrite only isolated lines or add generic verbal tics. Preserve outcomes and secrets unless expressly authorized."

  defp direction(%{"workflow" => "notes"}),
    do:
      "NOTES: make selectable coordinated groups for local and sequence notes. Annotate addresses_notes exactly. Keep unresolved conflicts visible. Do not delete a Fountain note except through an explicit operation when requested."

  defp direction(%{"workflow" => "pass"}),
    do:
      "PASS: apply the actual named profile and writer direction; return useful selective screenplay changes. Brevity is not universally better. Do not flatten every exchange or delete expressive long turns automatically."

  defp direction(%{"workflow" => "recover"}),
    do:
      "RECOVER: use the inspected historical source and exact destination. Adapt source material to the current story only as requested. Current draft facts and speaker IDs take precedence for adaptation; exact historical recovery uses verified historical IDs. Preserve source/current/proposed distinctions."

  defp direction(%{"workflow" => "investigate"}),
    do:
      "INVESTIGATE: now write one actual screenplay remedy for this evidence-backed strategy. Distinguish it materially from the other remedies. The investigation report is not a substitute for pages."
end
