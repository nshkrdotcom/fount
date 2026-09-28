defmodule FountWorkshop.Research do
  @moduledoc """
  Durable research dossier records for a writer session.

  Research material is session data, not screenplay canon. Source text is always
  recorded as untrusted content and never gains instruction authority merely by
  being quoted or retrieved. Fount records what is known about provenance and
  fiction status without pretending unavailable web access or missing evidence
  exists.
  """

  alias FountWorkshop.Store

  @claim_statuses ~w(sourced disputed unverified deliberately_fictionalized)
  @claim_origins ~w(source writer_memory invention)

  @doc "Records sources, factual claims, and unresolved research questions in session progress."
  def record(session_id, dossier, services, opts \\ [])

  def record(session_id, dossier, services, opts)
      when is_binary(session_id) and is_map(dossier) do
    with :ok <- validate_dossier(dossier),
         {:ok, session} <- Store.call(services[:store], :session, [session_id]),
         :ok <- validate_source_refs(session, dossier),
         {:ok, normalized} <- normalize_dossier(dossier, session, opts),
         :ok <- unique_ids(session, normalized) do
      research = research_state(session)

      next = %{
        "sources" => research["sources"] ++ normalized["sources"],
        "claims" => research["claims"] ++ normalized["claims"],
        "questions" => research["questions"] ++ normalized["questions"]
      }

      updated = put_in(session, ["progress", "research"], next)

      case Store.call(services[:store], :save_session, [updated]) do
        {:ok, _saved} -> {:ok, normalized}
        error -> error
      end
    end
  end

  def record(_, _, _, _), do: {:error, :invalid_research_dossier}

  @doc "Returns research state from a session, including disputed and unresolved material."
  def list(session) when is_map(session), do: research_state(session)

  @doc "Builds an explicit no-web research question without fabricating searches or references."
  def missing_web(question, user_citations \\ []) do
    cond do
      not valid_text?(question) ->
        {:error, :invalid_research_question}

      not is_list(user_citations) or Enum.any?(user_citations, &(not valid_text?(&1))) ->
        {:error, :invalid_user_citations}

      true ->
        {:ok,
         %{
           "id" => Fount.ID.v4(),
           "question" => question,
           "status" => "access_unavailable",
           "host_capability" => "web",
           "user_citations" => user_citations,
           "invented_references" => false,
           "instruction" =>
             "Use only supplied or later verified sources; do not invent searches, retrievals, or citations."
         }}
    end
  end

  defp validate_dossier(dossier) do
    sources = Map.get(dossier, "sources", [])
    claims = Map.get(dossier, "claims", [])
    questions = Map.get(dossier, "questions", [])

    cond do
      Map.keys(dossier) -- ~w(sources claims questions) != [] ->
        {:error, :unknown_research_field}

      not is_list(sources) or not Enum.all?(sources, &valid_source?/1) ->
        {:error, :invalid_research_source}

      not is_list(claims) or not Enum.all?(claims, &valid_claim?/1) ->
        {:error, :invalid_research_claim}

      not is_list(questions) or not Enum.all?(questions, &valid_question?/1) ->
        {:error, :invalid_research_question}

      true ->
        :ok
    end
  end

  defp valid_source?(source) when is_map(source) do
    allowed =
      ~w(id label location retrieved_at content rights_basis confidentiality provider_export_allowed)

    Map.keys(source) -- allowed == [] and valid_id?(source["id"]) and valid_text?(source["label"]) and
      Enum.all?(
        ~w(location retrieved_at content rights_basis confidentiality),
        &optional_text?(source[&1])
      ) and
      (is_nil(source["provider_export_allowed"]) or is_boolean(source["provider_export_allowed"]))
  end

  defp valid_source?(_), do: false

  defp valid_claim?(claim) when is_map(claim) do
    allowed = ~w(id text status origin source_id note)

    Map.keys(claim) -- allowed == [] and valid_id?(claim["id"]) and valid_text?(claim["text"]) and
      claim["status"] in @claim_statuses and claim["origin"] in @claim_origins and
      optional_id?(claim["source_id"]) and optional_text?(claim["note"])
  end

  defp valid_claim?(_), do: false

  defp validate_source_refs(session, dossier) do
    existing = research_state(session)["sources"]
    incoming = Map.get(dossier, "sources", [])
    source_ids = MapSet.new(existing ++ incoming, & &1["id"])

    if Enum.all?(Map.get(dossier, "claims", []), &valid_claim_source?(&1, source_ids)),
      do: :ok,
      else: {:error, :unknown_research_source}
  end

  defp valid_claim_source?(claim, source_ids) do
    source_id = claim["source_id"]

    case claim["origin"] do
      "source" -> is_binary(source_id) and MapSet.member?(source_ids, source_id)
      _ -> is_nil(source_id) or MapSet.member?(source_ids, source_id)
    end
  end

  defp valid_question?(question) when is_map(question) do
    allowed =
      ~w(id question status host_capability user_citations invented_references instruction)

    citations = question["user_citations"] || []

    Map.keys(question) -- allowed == [] and valid_id?(question["id"]) and
      valid_text?(question["question"]) and question["status"] == "access_unavailable" and
      question["host_capability"] == "web" and is_list(citations) and
      Enum.all?(citations, &valid_text?/1) and question["invented_references"] == false
  end

  defp valid_question?(_), do: false

  defp normalize_dossier(dossier, session, opts) do
    actor = Keyword.get(opts, :actor, "writer")
    recorded_at = timestamp()

    sources =
      Enum.map(Map.get(dossier, "sources", []), fn source ->
        source
        |> Map.put("trust", "untrusted_content")
        |> Map.put("instruction_authority", "none")
        |> Map.put("recorded_by", actor)
        |> Map.put("recorded_at", recorded_at)
        |> Map.update("provider_export_allowed", false, fn value -> value == true end)
      end)

    claims =
      Enum.map(Map.get(dossier, "claims", []), fn claim ->
        claim
        |> Map.put("screenplay_id", session["screenplay_id"])
        |> Map.put("base_revision_id", session["base_revision_id"])
        |> Map.put("recorded_by", actor)
        |> Map.put("recorded_at", recorded_at)
        |> Map.put("source_supported", claim["status"] == "sourced")
      end)

    questions =
      Enum.map(Map.get(dossier, "questions", []), fn question ->
        question
        |> Map.put("recorded_by", actor)
        |> Map.put("recorded_at", recorded_at)
      end)

    {:ok, %{"sources" => sources, "claims" => claims, "questions" => questions}}
  end

  defp unique_ids(session, normalized) do
    existing = research_state(session)

    ids =
      for collection <- ["sources", "claims", "questions"],
          item <- existing[collection] ++ normalized[collection],
          do: item["id"]

    if length(ids) == MapSet.size(MapSet.new(ids)),
      do: :ok,
      else: {:error, :duplicate_research_id}
  end

  defp research_state(session) do
    get_in(session, ["progress", "research"]) ||
      %{"sources" => [], "claims" => [], "questions" => []}
  end

  defp valid_id?(value), do: is_binary(value) and String.trim(value) != ""
  defp optional_id?(nil), do: true
  defp optional_id?(value), do: valid_id?(value)
  defp valid_text?(value), do: is_binary(value) and String.trim(value) != ""
  defp optional_text?(nil), do: true
  defp optional_text?(value), do: valid_text?(value)
  defp timestamp, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
