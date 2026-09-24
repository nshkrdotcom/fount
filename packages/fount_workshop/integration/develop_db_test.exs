defmodule FountWorkshop.DevelopDatabaseIntegrationTest do
  use ExUnit.Case, async: false
  alias Fount.{ID, Persistence, Repo, Screenplay}
  alias FountWorkshop.{Develop, Review}
  alias FountWorkshop.Export.PDF

  setup_all do
    start_supervised!({Repo, url: System.fetch_env!("FOUNT_DATABASE_URL"), pool_size: 2})
    :ok
  end

  test "an empty project becomes two saved, revisable candidate drafts" do
    key = "develop-#{ID.v4()}"
    root = Screenplay.new(title: [{"Title", "Wrong Train"}])
    assert {:ok, _} = Persistence.create(Repo, key, root)
    output = %{"approach" => "A tense arrival", "scenes" => [%{
      "heading" => "EXT. STATION - NIGHT",
      "elements" => [%{"type" => "action", "text" => "Mara watches the empty train pull away."}]
    }]}
    client = Inference.Client.new!(adapter: Inference.Adapters.Mock, provider: :mock,
      adapter_opts: [response_text: Jason.encode!(output)])
    second_output = put_in(output, ["scenes", Access.at(0), "elements", Access.at(0), "text"],
      "Mara chases the empty train down the platform.")
    second_client = Inference.Client.new!(adapter: Inference.Adapters.Mock, provider: :mock,
      adapter_opts: [response_text: Jason.encode!(second_output)])

    assert {:ok, result} = Develop.run(Repo, key, "A banker follows the wrong commuter.", client,
      clients: [client, second_client])
    assert length(result.candidates) == 2
    assert result.session.status == "ready"
    assert {:ok, accepted} = Persistence.load(Repo, key)
    assert accepted.revision.id == root.revision.id

    for candidate <- result.candidates do
      assert {:ok, reopened} = Persistence.load_revision(Repo, root.id, candidate.screenplay.revision.id)
      assert Screenplay.to_fountain(reopened) =~ "EXT. STATION - NIGHT"
    end

    chosen = hd(result.candidates)
    assert {:ok, packet} = Review.packet(Repo, chosen.id)
    assert packet["proposed_fountain"] =~ "Mara watches the empty train pull away."
    assert packet["source_diff"] != []
    pdf_path = Path.join(System.tmp_dir!(), "fount-candidate-#{chosen.id}.pdf")
    on_exit(fn -> File.rm(pdf_path) end)
    assert {:ok, pdf} = PDF.export(chosen.screenplay, pdf_path)
    assert pdf.pages >= 1
    assert pdf.page_size == :us_letter
    {page_text, 0} = System.cmd("pdftotext", [pdf_path, "-"])
    assert page_text =~ "STATION"
    assert page_text =~ "Mara watches"
    review = %{"candidate_id" => chosen.id, "content_hash" => packet["content_hash"],
      "actor" => "writer", "report_ids" => [], "overrides" => []}
    assert {:ok, accepted} = Review.accept(Repo, chosen.id, root.revision.id, review)
    assert accepted.revision.id == chosen.screenplay.revision.id
    assert {:ok, head} = Persistence.load(Repo, key)
    assert head.revision.id == chosen.screenplay.revision.id
  end

  test "a later completion failure leaves the first candidate saved and head unchanged" do
    key = "partial-#{ID.v4()}"
    root = Screenplay.new()
    assert {:ok, _} = Persistence.create(Repo, key, root)
    output = %{"approach" => "A locked door", "scenes" => [%{
      "heading" => "INT. SHOP - DAY",
      "elements" => [%{"type" => "action", "text" => "Mara locks the door."}]
    }]}
    good = Inference.Client.new!(adapter: Inference.Adapters.Mock, provider: :mock,
      adapter_opts: [response_text: Jason.encode!(output)])
    failed = Inference.Client.new!(adapter: Inference.Adapters.Mock, provider: :mock,
      adapter_opts: [error: :timeout])
    assert {:partial, result, {:completion_failed, 2, _, _}} = Develop.run(Repo, key,
      "Mara has five minutes.", good, clients: [good, failed])
    assert result.session.status == "partial"
    assert length(result.candidates) == 1
    assert {:ok, stored} = Persistence.candidate(Repo, hd(result.candidates).id)
    assert Screenplay.to_fountain(stored["screenplay"]) =~ "Mara locks the door."
    assert {:ok, head} = Persistence.load(Repo, key)
    assert head.revision.id == root.revision.id

    next_output = put_in(output,
      ["scenes", Access.at(0), "elements", Access.at(0), "text"],
      "Mara shoves a chair beneath the door handle.")
    next_client = Inference.Client.new!(adapter: Inference.Adapters.Mock, provider: :mock,
      adapter_opts: [response_text: Jason.encode!(next_output)])
    first_id = hd(result.candidates).id
    assert {:ok, resumed} = Develop.resume(Repo, result.session.id, next_client)
    assert resumed.session.status == "ready"
    assert length(resumed.candidates) == 2
    assert hd(resumed.candidates).id == first_id
    assert {:ok, head_after_resume} = Persistence.load(Repo, key)
    assert head_after_resume.revision.id == root.revision.id
  end
end
