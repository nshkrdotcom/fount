defmodule FountWorkshop.Writing.VoiceProtection do
  @moduledoc "Writer-selected voice exemplars and exact text protection for Workshop generation."

  alias Fount.Intelligence.Playbooks.Constraints

  @protection_prefix "voice-protection:"

  @doc "Validates writer-owned voice guidance against the current screenplay without provider calls."
  def validate(model, request) when is_map(request) do
    options = request["options"] || %{}

    with :ok <-
           validate_text_list(
             Map.get(options, "style_preferences", []),
             :invalid_style_preferences
           ),
         :ok <- validate_targets(model, exemplar_targets(request)) do
      validate_passages(model, Map.get(options, "protected_text", []))
    end
  end

  def validate(_, _), do: {:error, :invalid_voice_protection}

  @doc "Adds exact writer pins to the ordinary constraint list and resolves the combined set."
  def resolve_constraints(model, request) when is_map(request) do
    constraints = request["constraints"] || []
    pins = pin_constraints(request)

    with {:ok, resolved} <- Constraints.resolve(model, constraints),
         {:ok, resolved_pins} <- Constraints.resolve(model, pins),
         new_pins = Enum.reject(resolved_pins, &(&1 in resolved)),
         :ok <- unique_constraint_ids(resolved ++ new_pins) do
      {:ok, resolved ++ new_pins}
    end
  end

  @doc "Builds source-backed voice context. Subjective voice fit remains a writer/human judgment."
  def context(model, request) when is_map(request) do
    targets = exemplar_targets(request)
    options = request["options"] || %{}
    passages = Map.get(options, "protected_text", [])
    preferences = Map.get(options, "style_preferences", [])

    with {:ok, exemplars} <- select_exemplars(model, targets) do
      if targets == [] and passages == [] and preferences == [] do
        {:ok, nil}
      else
        {:ok,
         %{
           "exemplars" => exemplars,
           "protected_text" => passages,
           "style_preferences" => preferences,
           "rules" => [
             "Exact protected text is a deterministic hard constraint, not a style suggestion.",
             "Do not silently translate or normalize multilingual text, dialect, deliberate fragments, strategic awkwardness, or repetition.",
             "Use exemplars as project-specific evidence of voice, not as permission to imitate unrelated material."
           ],
           "limitations" => [
             "Voice similarity is not an objective quality score.",
             "Fount does not certify language or cultural authenticity; uncertain multilingual or dialect changes require writer/human review."
           ]
         }}
      end
    end
  end

  defp exemplar_targets(%{"options" => options, "workflow" => workflow}) when is_map(options) do
    common = Map.get(options, "voice_exemplars", [])
    character = if workflow == "character", do: Map.get(options, "exemplar_targets", []), else: []

    if is_list(common) and is_list(character),
      do: Enum.uniq(common ++ character),
      else: :invalid
  end

  defp exemplar_targets(_), do: []

  defp validate_targets(_model, []), do: :ok

  defp validate_targets(model, targets) when is_list(targets) do
    case Fount.Selection.select(model, %{"targets" => targets}) do
      {:ok, units} when units != [] -> :ok
      _ -> {:error, :invalid_voice_exemplars}
    end
  end

  defp validate_targets(_, _), do: {:error, :invalid_voice_exemplars}

  defp select_exemplars(_model, []), do: {:ok, []}

  defp select_exemplars(model, targets) do
    case Fount.Selection.select(model, %{"targets" => targets}) do
      {:ok, units} ->
        {:ok,
         Enum.map(units, fn unit ->
           Map.take(unit, ~w(evidence_id ordinal scene_id target text type))
         end)}

      _ ->
        {:error, :invalid_voice_exemplars}
    end
  end

  defp validate_passages(_model, []), do: :ok

  defp validate_passages(model, passages) when is_list(passages) and passages != [] do
    with true <- Enum.all?(passages, &valid_passage_shape?/1) or {:error, :invalid_protected_text},
         true <- unique_ids?(passages) or {:error, :duplicate_protected_text_id} do
      verify_exact_passages(model, passages)
    end
  end

  defp validate_passages(_, _), do: {:error, :invalid_protected_text}

  defp verify_exact_passages(model, passages) do
    checks = Constraints.deterministic(model, model, Enum.map(passages, &pin_constraint/1))

    if Enum.all?(checks, &(&1["status"] == "pass")),
      do: :ok,
      else: {:error, :protected_text_not_exactly_located}
  end

  defp valid_passage_shape?(passage) when is_map(passage) do
    Map.keys(passage) -- ~w(id target text) == [] and
      valid_text?(passage["id"]) and is_map(passage["target"]) and valid_text?(passage["text"])
  end

  defp valid_passage_shape?(_), do: false

  defp pin_constraints(%{"options" => options}) when is_map(options) do
    options |> Map.get("protected_text", []) |> Enum.map(&pin_constraint/1)
  end

  defp pin_constraints(_), do: []

  defp pin_constraint(passage) do
    %{
      "id" => @protection_prefix <> passage["id"],
      "target" => passage["target"],
      "kind" => "pin_text",
      "spec" => %{"text" => passage["text"]},
      "severity" => "required",
      "source" => "writer"
    }
  end

  defp unique_constraint_ids(constraints) do
    ids = Enum.map(constraints, & &1["id"])

    if Enum.all?(ids, &valid_text?/1) and length(ids) == length(Enum.uniq(ids)),
      do: :ok,
      else: {:error, :duplicate_constraint_id}
  end

  defp unique_ids?(values) do
    ids = Enum.map(values, & &1["id"])
    length(ids) == length(Enum.uniq(ids))
  end

  defp validate_text_list(values, _error) when values == [], do: :ok

  defp validate_text_list(values, error) when is_list(values) do
    if Enum.all?(values, &valid_text?/1), do: :ok, else: {:error, error}
  end

  defp validate_text_list(_, error), do: {:error, error}
  defp valid_text?(value), do: is_binary(value) and String.trim(value) != ""
end
