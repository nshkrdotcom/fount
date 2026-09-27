Code.require_file("../examples/support/phase_one_demo.exs", __DIR__)

defmodule FountWorkshop.PhaseOneWriterDemoTest do
  use ExUnit.Case, async: false
  alias FountWorkshop.Examples.PhaseOneDemo

  setup_all do
    start_supervised!({Fount.Repo, url: System.fetch_env!("FOUNT_DATABASE_URL"), pool_size: 2})
    :ok
  end

  test "develop, reject alternate, revise, compare, accept and export use actual storage" do
    out = Path.join(System.tmp_dir!(), "fount-phase-one-#{Fount.ID.v4()}")
    on_exit(fn -> File.rm_rf!(out) end)
    assert {:ok, result} = PhaseOneDemo.run(Fount.Repo, out: out, decision: :accept, pdf: false)
    assert result["accepted_revision_id"] == result["candidate_revision_id"]
    assert File.read!(Path.join(out, "accepted.fountain")) =~ "Then why is the safe open?"
    assert File.read!(Path.join(out, "table_read.html")) =~ "Then why is the safe open?"
    assert File.read!(Path.join(out, "original.fountain")) =~ "I know you took it."
    assert result["pdf"]["status"] == "not_requested"
  end

  @tag :pdf
  test "reject retains original canon while the alternative PDF remains reviewable" do
    out = Path.join(System.tmp_dir!(), "fount-phase-one-#{Fount.ID.v4()}")
    on_exit(fn -> File.rm_rf!(out) end)
    assert {:ok, result} = PhaseOneDemo.run(Fount.Repo, out: out, decision: :reject, pdf: true)
    assert result["accepted_revision_id"] == result["base_revision_id"]
    assert File.read!(Path.join(out, "accepted.fountain")) =~ "I know you took it."
    assert File.stat!(Path.join(out, "candidate.pdf")).size > 0
    assert result["pdf"]["pages"] >= 1
  end
end
