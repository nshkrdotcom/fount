defmodule FountWorkshop.StrategyPromptSizeTest do
  alias FountWorkshop.Writing.Context
  use ExUnit.Case, async: true

  test "duplicate dialogue metadata cannot exhaust the strategy prompt" do
    strategy = %{
      "id" => "choice-1",
      "title" => "Act on the clue",
      "premise_of_change" => "Mara acts",
      "dramatic_mechanism" => "Choice",
      "entry_state" => "Uncertain",
      "exit_state" => "Committed",
      "beats" => [],
      "preserves" => [],
      "changes" => [],
      "inventions" => [],
      "consequences" => [],
      "evidence_ids" => [],
      "open_questions" => []
    }

    client =
      Inference.Client.new!(
        adapter: Inference.Adapters.Mock,
        provider: :mock,
        adapter_opts: [response_text: Jason.encode!(%{"strategies" => [strategy]})]
      )

    dialogue_blocks =
      Enum.map(1..900, fn n ->
        %{
          "id" => "block-#{n}",
          "cue_id" => "cue-#{n}",
          "body_ids" => ["body-#{n}"],
          "scene_id" => "scene-#{n}",
          "side" => nil
        }
      end) ++
        [
          %{
            "id" => "dual-block",
            "cue_id" => "dual-cue",
            "body_ids" => ["dual-body"],
            "scene_id" => "scene-1",
            "side" => "right",
            "dual_with" => "other-block"
          }
        ]

    context = %{
      data: %{
        "selected_pages" => [%{"text" => "MARA holds the invoice.", "scene_id" => "scene-1"}],
        "dialogue_blocks" => dialogue_blocks,
        "confirmed_mentions" => [
          %{"role" => "speaker_cue", "element_id" => "cue-1", "character_id" => "cast-1"}
        ],
        "inspections" => [%{"id" => "report-1", "data" => %{"records" => Enum.to_list(1..20)}}]
      },
      evidence: []
    }

    prompt_data = Context.prompt_data(context.data)
    assert Enum.map(prompt_data["dialogue_blocks"], & &1["id"]) == ["dual-block"]

    assert prompt_data["confirmed_mentions"] == [
             %{"element_id" => "cue-1", "character_id" => "cast-1"}
           ]

    assert get_in(
             Context.prompt_data(context.data,
               inspection_sample_limit: 4
             ),
             ["inspections", Access.at(0), "data", "records"]
           ) ==
             %{"total" => 20, "sample" => [1, 2, 3, 4]}

    assert {:ok, [^strategy], [_]} =
             FountWorkshop.Strategy.generate(
               nil,
               %{"alternatives" => 1},
               context,
               %{inference: client},
               force_json_text: true,
               max_context_bytes: 20_000
             )
  end
end
