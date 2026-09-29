defmodule FountWeb.DemoAdapter do
  @moduledoc "Deterministic, credential-free completion adapter used only by Phase 06 demo/browser acceptance."
  @behaviour Inference.Adapter

  @impl true
  def provider_kind, do: :local_model_endpoint
  @impl true
  def credential_mode, do: :explicit
  @impl true
  def capabilities(_client), do: []

  @impl true
  def complete(_client, request) do
    prompt = Inference.Request.user_prompt(request)

    value =
      cond do
        String.starts_with?(prompt, "Investigate this writer's specific creative question") -> investigation_plan()
        String.starts_with?(prompt, "Answer the creative question using the actual reports") -> investigation_explanation()
        String.starts_with?(prompt, "Extract existing screenplay evidence") -> %{"summary" => "The inspected scene establishes the protected beat.", "records" => []}
        String.starts_with?(prompt, "You are developing choices for a professional spec screenplay") -> repair_strategies()
        String.contains?(prompt, "Write actual complete screenplay pages as canonical typed edits") -> proposal(prompt)
        true -> %{"summary" => "Deterministic demo has no response contract for this prompt."}
      end

    {:ok,
     Inference.Response.new(
       provider: :fount_demo,
       model: "fount-phase06-demo-v1",
       text: Jason.encode!(value),
       finish_reason: :stop,
       usage: %{"input_tokens" => 0, "output_tokens" => 0},
       cost: nil,
       metadata: %{"deterministic" => true, "credential" => "none"}
     )}
  end

  defp investigation_plan do
    %{
      "hypotheses" => [
        %{"id" => "h1", "claim" => "The requested change should create an immediate visible consequence.", "reason" => "The brief asks for causal page work.", "request_ids" => ["search-1"]}
      ],
      "requests" => [
        %{"id" => "search-1", "playbook" => "search", "params" => %{"query" => "choice", "selection" => %{"whole_screenplay" => true}}}
      ]
    }
  end

  defp investigation_explanation do
    %{
      "answer" => "The change should preserve declared material while making the requested turn visible on the page.",
      "revised_hypotheses" => [
        %{"id" => "h1", "claim" => "Make the turn causal and visible.", "reason" => "The inspected material supports a consequence after the existing beat.", "status" => "supported", "evidence_ids" => []}
      ],
      "uncertainties" => ["Uninspected material remains unknown."],
      "evidence_ids" => [],
      "strategies" => [
        %{"id" => "route-a", "title" => "Commit now", "dramatic_mechanism" => "The choice closes an easy exit.", "beats" => ["Choice", "Reveal", "Consequence"], "evidence_ids" => []},
        %{"id" => "route-b", "title" => "Delay", "dramatic_mechanism" => "Suspicion grows before confirmation.", "beats" => ["Suspicion", "Delay", "Reveal"], "evidence_ids" => []},
        %{"id" => "route-c", "title" => "Reverse leverage", "dramatic_mechanism" => "The target weaponizes the reveal.", "beats" => ["Reveal", "Countermove", "Cost"], "evidence_ids" => []}
      ],
      "follow_up_requests" => []
    }
  end

  defp repair_strategies do
    %{"strategies" => [strategy("route-a", "Preserve then answer"), strategy("route-b", "Delay then answer"), strategy("route-c", "Reverse then answer")]}
  end

  defp strategy(id, title) do
    %{
      "id" => id,
      "title" => title,
      "premise_of_change" => "Preserve existing protected material and add a consequence afterward.",
      "dramatic_mechanism" => "Consequence rather than replacement",
      "entry_state" => "The existing beat is intact",
      "exit_state" => "The beat now creates a cost",
      "beats" => ["Preserve", "Consequence"],
      "preserves" => ["protected material"],
      "changes" => ["aftermath"],
      "inventions" => [],
      "consequences" => ["the choice narrows options"],
      "evidence_ids" => [],
      "open_questions" => []
    }
  end

  defp proposal(prompt) do
    base = capture(prompt, ~r/"base_revision_id":"([0-9a-f-]{36})"/) || Fount.ID.v4()
    strategy = capture(prompt, ~r/"strategy":\{[^}]*"id":"([^"]+)"/) || "route-a"
    journey = capture(prompt, ~r/JOURNEY:([a-z_]+)/) || "opening"
    repair? = String.contains?(prompt, ~s("repair_feedback":{))

    operations =
      case journey do
        "dialogue" -> dialogue_ops(prompt)
        "reveal" -> reveal_ops(prompt, repair?)
        _ -> opening_ops()
      end

    %{
      "version" => 1,
      "base_revision_id" => base,
      "strategy_id" => strategy,
      "summary" => "Deterministic Phase 06 demo page change.",
      "inventions" => [],
      "unresolved_questions" => [],
      "groups" => [
        %{"id" => "demo-change", "title" => "Demo change", "reason" => "Exercise the real Run/Workshop integration.", "depends_on" => [], "addresses_notes" => [], "evidence_ids" => [], "origin" => "generated_text", "operations" => operations}
      ]
    }
  end

  defp opening_ops do
    [%{"kind" => "insert_scene", "value" => %{"after_scene_id" => nil, "scene" => %{"local_id" => "new:opening", "heading" => "INT. LOCKED ROOM - NIGHT", "elements" => [%{"local_id" => "new:opening-action", "type" => "action", "text" => "Mara turns the deadbolt before the footsteps reach the hall.", "attrs" => %{}}]}}}]
  end

  defp dialogue_ops(prompt) do
    id = capture(prompt, ~r/TARGET_DIALOGUE:([0-9a-f-]{36})/)
    if id, do: [%{"kind" => "replace_text", "target" => %{"kind" => "element", "id" => id}, "value" => "If you missed it, you were meant to."}], else: opening_ops()
  end

  defp reveal_ops(prompt, repair?) do
    protected = capture(prompt, ~r/TARGET_PROTECTED:([0-9a-f-]{36})/)
    scene = capture(prompt, ~r/AFTER_SCENE:([0-9a-f-]{36})/)
    consequence = %{"kind" => "insert_scene", "value" => %{"after_scene_id" => scene, "scene" => %{"local_id" => "new:consequence", "heading" => "INT. STATION OFFICE - NIGHT", "elements" => [%{"local_id" => "new:consequence-action", "type" => "action", "text" => "The stationmaster locks the evidence cabinet.", "attrs" => %{}}]}}}

    cond do
      repair? -> [consequence]
      protected -> [%{"kind" => "replace_text", "target" => %{"kind" => "element", "id" => protected}, "value" => "Nora abandons the platform before the protected beat can land."}, consequence]
      true -> [consequence]
    end
  end

  defp capture(text, regex) do
    case Regex.run(regex, text, capture: :all_but_first) do
      [value] -> value
      _ -> nil
    end
  end
end
