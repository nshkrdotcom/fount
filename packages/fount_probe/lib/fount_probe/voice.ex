defmodule FountProbe.Voice do
  @moduledoc "Held-out blind voice attribution. Matrices describe recognizability, not writing quality."
  alias FountProbe.{Projection, Jev, Report}
  @labels ~w(voice_a voice_b voice_c voice_d voice_e voice_f voice_g voice_h)

  def prepare(model, params) do
    ids = params["character_ids"]
    if not is_list(ids) or length(ids) not in 2..8 or length(Enum.uniq(ids)) != length(ids) or Enum.any?(ids, &(not Map.has_key?(model.cast, &1))) do
      {:error, :voice_requires_two_to_eight_known_characters}
    else
      with {:ok, units} <- Projection.select(model, params["selection"]) do
        names = Enum.flat_map(Fount.Query.characters(model), fn c -> [c.display_name | Enum.map(c.aliases, &alias_name/1)] end)
        normalize = &normalize(&1, names)
        all = Enum.flat_map(ids, fn id ->
          Fount.Query.character_dialogue(model, id) |> Enum.map(fn b ->
            selected = Enum.filter(units, &(&1["target"]["id"] in b.body_ids and &1["type"] == "dialogue"))
            text = selected |> Enum.map(& &1["text"]) |> Enum.join(" ") |> normalize.()
            %{id: b.id, cast: id, text: text, evidence: Projection.evidence(selected)}
          end)
        end) |> Enum.filter(&(length(String.split(&1.text)) >= 6)) |> Enum.uniq_by(& &1.text)
        given = params["profiles"] || %{}
        mapping = ids |> Enum.zip(@labels) |> Map.new()
        by_cast = Enum.group_by(all, & &1.cast)
        profiles = Map.new(ids, fn id ->
          samples = Map.get(by_cast, id, [])
          supplied = given[id]
          explicit = if is_binary(supplied) and String.trim(supplied) != "", do: supplied
          selected = if is_list(params["training_targets"]), do: Enum.filter(samples, fn t -> t.id in Enum.map(params["training_targets"], & &1["id"]) end), else: evenly(samples, min(8, max(length(samples) - 3, 0)))
          chosen = if is_binary(explicit) and String.trim(explicit) != "", do: [], else: selected
          {mapping[id], %{description: if(is_binary(explicit), do: normalize.(explicit), else: nil), samples: Enum.map(chosen, & &1.text), ids: Enum.map(chosen, & &1.id), evidence: Enum.flat_map(chosen, & &1.evidence)}}
        end)
        training = Enum.flat_map(profiles, fn {_, p} -> p.samples end) |> MapSet.new()
        tests = Enum.flat_map(ids, fn id ->
          Map.get(by_cast, id, []) |> Enum.reject(&MapSet.member?(training, &1.text)) |> evenly(20) |> Enum.map(&Map.merge(&1, %{actual: mapping[id], state: %{"utterance" => &1.text}}))
        end)
        insufficient = Enum.flat_map(ids, fn id ->
          p = profiles[mapping[id]]; count = Enum.count(tests, &(&1.cast == id))
          if (is_nil(p.description) and length(p.samples) < 3) or count < 3, do: [%{"character_id" => id, "training_count" => length(p.samples), "test_count" => count, "description_supplied" => not is_nil(p.description)}], else: []
        end)
        {:ok, %{profiles: profiles, tests: tests, labels: Enum.take(@labels, length(ids)), mapping: mapping, insufficient: insufficient}}
      end
    end
  end

  def run(model, params, clients, opts \\ []) do
    with {:ok, prepared} <- prepare(model, params) do
      if prepared.insufficient != [] do
        {:ok, Report.new(model, "voice", params, %{status: "partial", data: %{"status" => "insufficient_samples", "samples" => prepared.insufficient}, coverage: %{"no_padded_samples" => true}})}
      else
        criteria = Enum.map(prepared.labels, fn label -> p = prepared.profiles[label]; {label, p.description || Enum.join(p.samples, "\n")} end)
        question = SystemOneSDK.choice("Which anonymous voice profile best matches the unlabelled utterance? Use voice, not story identity.", criteria)
        inputs = Enum.map(prepared.tests, &%{"id" => &1.id, "state" => &1.state})
        with {:ok, result} <- Jev.evaluate(clients[:system_one], inputs, [voice: question], Keyword.put_new(opts, :profile_id, "voice")) do
          stats = aggregate(prepared.tests, result["entries"], prepared.labels)
          groups = Map.new(params["comparison_groups"] || [], fn group ->
            {:ok, group_units} = Projection.select(model, group["selection"])
            group_ids = MapSet.new(group_units, & &1["target"]["id"])
            chosen = Enum.filter(prepared.tests, fn test ->
              Enum.any?(test.evidence, &MapSet.member?(group_ids, &1["target"]["id"]))
            end)
            {group["id"], aggregate(chosen, result["entries"], prepared.labels)}
          end)
          {:ok, Report.new(model, "voice", params, %{status: result["status"], data: Map.merge(stats, %{"mapping" => prepared.mapping,
            "groups" => groups, "profiles" => Fount.Screenplay.Model.plain(prepared.profiles), "test_ids" => Enum.map(prepared.tests, & &1.id)}),
            evidence: Enum.uniq_by(Enum.flat_map(prepared.tests, & &1.evidence) ++ Enum.flat_map(prepared.profiles, fn {_, p} -> p.evidence end), & &1["evidence_id"]), provenance: result,
            coverage: %{"training_ids" => Enum.flat_map(prepared.profiles, fn {_, p} -> p.ids end), "test_count" => length(prepared.tests), "names_neutralized" => true}})}
        end
      end
    end
  end

  def aggregate(tests, entries, labels) do
    by_id = Map.new(entries, &{&1["input_id"], &1})
    rows = Map.new(labels, fn label ->
      actual = Enum.filter(tests, &(&1.actual == label))
      answers = Enum.flat_map(actual, fn t -> case get_in(by_id, [t.id, "answers", "voice"]) do %{"probabilities" => p} = a when is_map(p) -> [a]; _ -> [] end end)
      n = length(answers)
      soft = Map.new(labels, fn target -> {target, if(n == 0, do: nil, else: Enum.sum(Enum.map(answers, & &1["probabilities"][target])) / n)} end)
      hard = Map.new(labels, fn target -> {target, Enum.count(answers, fn a -> Enum.max_by(labels, &a["probabilities"][&1]) == target end)} end)
      counts = %{"eligible" => length(actual), "evaluated" => n, "missing" => length(actual) - n, "uncertain" => Enum.count(answers, &(&1["status"] == "uncertain"))}
      {label, %{soft: soft, hard: hard, counts: counts}}
    end)
    %{"soft" => Map.new(rows, fn {k, r} -> {k, r.soft} end), "hard" => Map.new(rows, fn {k, r} -> {k, r.hard} end), "counts" => Map.new(rows, fn {k, r} -> {k, r.counts} end)}
  end
  defp alias_name(name) when is_binary(name), do: name
  defp alias_name(name) when is_map(name), do: Map.get(name, :alias) || Map.get(name, "alias")
  defp alias_name(_), do: nil
  defp normalize(text, names) do
    names |> Enum.reject(&is_nil/1) |> Enum.sort_by(&(-String.length(&1))) |> Enum.reduce(text, fn name, value ->
      Regex.replace(Regex.compile!("(?<![\\p{L}\\p{N}])" <> Regex.escape(name) <> "(?![\\p{L}\\p{N}])", "iu"), value, "[name]")
    end) |> String.downcase() |> String.replace(~r/\s+/u, " ") |> String.trim()
  end
  defp evenly([], _), do: []
  defp evenly(_, n) when n <= 0, do: []
  defp evenly(list, n) when length(list) <= n, do: list
  defp evenly(list, 1), do: [hd(list)]
  defp evenly(list, n), do: Enum.map(0..(n - 1), &Enum.at(list, round(&1 * (length(list) - 1) / (n - 1))))
end
