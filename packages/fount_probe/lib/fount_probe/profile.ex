defmodule FountProbe.Profile do
  @moduledoc "Versioned finite question assets, compiled through public SDK constructors."
  alias Fount.Writing.CanonicalJSON
  alias SystemOneSDK.Question.Choice
  alias SystemOneSDK.Question.Noul
  alias SystemOneSDK.Question.Score

  def load(id) when is_binary(id) do
    if Regex.match?(~r/\A[a-z][a-z0-9_]*\z/, id) do
      path = Application.app_dir(:fount_probe, "priv/profiles/#{id}.json")

      with {:ok, data} <- File.read(path),
           {:ok, profile} <- Jason.decode(data),
           %{"id" => ^id, "version" => version, "questions" => questions} <- profile,
           true <- is_integer(version) and version > 0 and is_list(questions),
           true <- valid_thresholds?(Map.get(profile, "thresholds", %{})) do
        {:ok, Map.put(profile, "sha256", CanonicalJSON.hash(profile))}
      else
        _ -> {:error, {:invalid_profile, id}}
      end
    else
      {:error, :invalid_profile_id}
    end
  end

  def load(_), do: {:error, :invalid_profile_id}

  def valid_thresholds?(thresholds) when is_map(thresholds) do
    allowed =
      ~w(support_probability unsupported_probability minimum_confidence minimum_margin pass_mass fail_mass)

    Map.keys(thresholds) -- allowed == [] and
      Enum.all?(thresholds, fn {_, value} -> is_number(value) and value >= 0 and value <= 1 end) and
      Map.get(thresholds, "support_probability", 0.8) >
        Map.get(thresholds, "unsupported_probability", 0.2) and
      Map.get(thresholds, "pass_mass", 0.8) > Map.get(thresholds, "fail_mass", 0.2)
  end

  def valid_thresholds?(_), do: false

  def compile(questions, nil), do: {:ok, questions, nil}

  def compile(questions, id) do
    with {:ok, profile} <- load(id) do
      overrides = Map.new(profile["questions"], &{&1["key"], &1})

      compiled = Enum.reduce_while(questions, {:ok, []}, &compile_question(&1, &2, overrides))

      case compiled do
        {:ok, compiled} ->
          {:ok, compiled, Map.take(profile, ~w(id version tool projection thresholds sha256))}

        error ->
          error
      end
    end
  end

  defp compile_question({key, question}, {:ok, acc}, overrides) do
    case Map.get(overrides, to_string(key)) do
      nil -> {:cont, {:ok, acc ++ [{key, question}]}}
      spec -> compile_override(key, question, spec, acc)
    end
  end

  defp compile_override(key, question, spec, acc) do
    case construct(question, spec) do
      {:ok, result} -> {:cont, {:ok, acc ++ [{key, result}]}}
      error -> {:halt, error}
    end
  end

  defp construct(%Noul{} = q, %{"type" => "noul", "instructions" => text})
       when is_binary(text),
       do: Noul.new(text, extra: q.extra)

  defp construct(
         %Choice{} = q,
         %{"type" => "choice", "instructions" => text} = spec
       )
       when is_binary(text),
       do: Choice.new(text, Map.get(spec, "criteria", q.criteria), extra: q.extra)

  defp construct(
         %Score{} = q,
         %{"type" => "score", "instructions" => text} = spec
       )
       when is_binary(text),
       do: Score.new(text, Map.get(spec, "levels", q.levels), extra: q.extra)

  defp construct(_, _), do: {:error, :question_profile_type_mismatch}
end
