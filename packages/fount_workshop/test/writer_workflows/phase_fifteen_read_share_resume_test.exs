Code.require_file("../../support/continuation_store.ex", __DIR__)

defmodule FountWorkshop.PhaseFifteenReadShareResumeTest do
  use ExUnit.Case, async: true

  alias Fount.Screenplay
  alias FountWorkshop.{Acceptance, Candidate, Session, Share, Store, TableRead}
  alias FountWorkshop.TestSupport.ContinuationStore

  @source """
  Title: Café at Midnight
  Author: Test Writer

  # PRIVATE OUTLINE
  = Do not put this development synopsis in a reader copy.

  INT. DINER - NIGHT

  [[PRIVATE NOTE: resolve the pronoun before sharing.]]
  Evan watches rain bead on the glass.

  MARA
  He said it was already handled.

  DAN ^
  Ça va. Leave it alone.

  ===

  /*
  INT. CUT ROOM - NIGHT

  PRIVATE BONEYARD SCENE.
  */
  """

  test "A09/A10/A11 human read, safe share, stale protection, retry and resume use one accepted source identity" do
    base = @source |> Fount.parse!() |> Screenplay.from_document()
    action = Enum.find(base.ir.elements, &(&1.type == :action and String.contains?(&1.text, "rain bead")))

    {:ok, repo} = ContinuationStore.start_link(base)
    on_exit(fn -> if Process.alive?(repo), do: Agent.stop(repo) end)
    services = %{store: %Store{repo: repo, module: ContinuationStore}}

    assert {:ok, session} = Session.open(base, request(base), services)

    assert {:ok, accepted_candidate} =
             Candidate.manual(
               session["id"],
               [replace(action.id, "Evan watches the rain erase the parking-lot lights.")],
               services,
               actor: "writer",
               label: "Sharper visual"
             )

    assert {:ok, rejected_candidate} =
             Candidate.manual(
               session["id"],
               [replace(action.id, "Evan studies every drop until the image explains itself.")],
               services,
               actor: "writer",
               label: "Too explanatory"
             )

    assert {:ok, remaining_candidate} =
             Candidate.manual(
               session["id"],
               [replace(action.id, "Evan turns from the rain before Mara can read him.")],
               services,
               actor: "writer",
               label: "Unchosen alternate"
             )

    review = review(accepted_candidate)

    assert {:ok, accepted} =
             Acceptance.accept(accepted_candidate["id"], base.revision.id, review, services)

    assert accepted.id == base.id

    # Retrying the same writer decision is idempotent: no duplicate edit or second accepted revision.
    assert {:ok, retried} =
             Acceptance.accept(accepted_candidate["id"], base.revision.id, review, services)

    assert retried.revision.id == accepted.revision.id

    # A sibling generated from the old base cannot overwrite a manual/accepted head.
    assert {:error, {:stale_revision, current_revision}} =
             Acceptance.accept(
               remaining_candidate["id"],
               base.revision.id,
               review(remaining_candidate),
               services
             )

    assert current_revision == accepted.revision.id
    assert {:ok, _} = Acceptance.reject(rejected_candidate["id"], "writer", services)

    assert {:ok, packet} = TableRead.packet(accepted)
    assert packet["source"]["screenplay_id"] == accepted.id
    assert packet["source"]["revision_id"] == accepted.revision.id
    assert packet["reading"]["speech_required"] == false
    assert packet["claims"]["audience_response_measured"] == false
    assert Enum.any?(packet["roles"], &(&1["cue"] == "MARA"))
    assert Enum.any?(packet["selected_pages"], &(&1["heading"] == "INT. DINER - NIGHT"))

    assert {:ok, reacted} =
             TableRead.record_reaction(packet, %{
               "observer" => "human",
               "reader_id" => "reader-1",
               "reaction" => "The pronoun in Mara's line is confusing on first read.",
               "script_wording" => "He said it was already handled.",
               "reader_delivery" => "neutral read",
               "listening_conditions" => "in-room table read"
             })

    assert [reaction] = reacted["reactions"]
    assert reaction["source"]["revision_id"] == accepted.revision.id
    assert reaction["reader_delivery"] == "neutral read"
    assert reaction["listening_conditions"] == "in-room table read"
    assert {:error, :human_observer_required} =
             TableRead.record_reaction(packet, %{"observer" => "tts", "reaction" => "laughed"})

    directory = Path.join(System.tmp_dir!(), "fount-phase15-share-#{Fount.ID.v4()}")
    on_exit(fn -> File.rm_rf(directory) end)

    assert {:ok, share} = Share.export(accepted, %{"whole_screenplay" => true}, directory)
    fountain = File.read!(Path.join(directory, "screenplay.fountain"))
    fdx = File.read!(Path.join(directory, "screenplay.fdx"))
    manifest = File.read!(Path.join(directory, "share.manifest.json")) |> Jason.decode!()

    assert fountain =~ "Title: Café at Midnight"
    assert fountain =~ "Ça va. Leave it alone."
    assert fountain =~ "DAN ^"
    refute fountain =~ "PRIVATE NOTE"
    refute fountain =~ "PRIVATE BONEYARD SCENE"
    refute fountain =~ "PRIVATE OUTLINE"
    refute fountain =~ "development synopsis"
    refute fountain =~ "Evan turns from the rain before Mara can read him."
    assert fdx =~ "DualDialogue"
    assert share["source"]["revision_id"] == accepted.revision.id
    assert manifest["claims"]["provider_metadata_included"] == false
    assert manifest["claims"]["workshop_candidates_included"] == false
    assert Enum.any?(manifest["unsupported_or_lossy"], &String.contains?(&1, "page_break"))

    # The established no-op Fountain archival contract remains unchanged outside the clean projection.
    assert Screenplay.to_fountain(base) == @source

    assert {:ok, resumed} = Session.resume_view(session["id"], services)
    decisions = Map.new(resumed["candidates"], &{&1["id"], &1["decision"]})
    assert decisions[accepted_candidate["id"]] == "accepted"
    assert decisions[rejected_candidate["id"]] == "rejected"
    assert decisions[remaining_candidate["id"]] == "proposed"
    assert ContinuationStore.head(repo).revision.id == accepted.revision.id
  end

  defp replace(id, text) do
    %{
      "kind" => "replace_text",
      "target" => %{"kind" => "element", "id" => id},
      "value" => text
    }
  end

  defp review(candidate) do
    %{
      "candidate_id" => candidate["id"],
      "content_hash" => candidate["screenplay"].revision.content_hash,
      "actor" => "writer",
      "report_ids" => candidate["provenance"]["report_ids"] || [],
      "overrides" => []
    }
  end

  defp request(base) do
    %{
      "version" => 1,
      "workflow" => "alternatives",
      "mode" => "revise",
      "base_revision_id" => base.revision.id,
      "instruction" => "Try scene-local revisions while preserving the accepted draft until I decide.",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "alternatives" => 3,
      "options" => %{
        "pending_question" => "Does Mara's pronoun need a concrete antecedent?",
        "protected_strengths" => ["rain against the diner window"]
      }
    }
  end
end
