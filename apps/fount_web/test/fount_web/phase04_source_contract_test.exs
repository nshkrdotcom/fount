defmodule FountWeb.Phase04SourceContractTest do
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  test "viewer index and view resolver stay provider-free and use canonical persistence/diff contracts" do
    viewer = File.read!(Path.join(@root, "lib/fount_web/live/viewer_live.ex"))
    views = File.read!(Path.join(@root, "lib/fount_web/screenplay_views.ex"))
    index = File.read!(Path.join(@root, "lib/fount_web/screenplay_index.ex"))
    diff = File.read!(Path.join(@root, "lib/fount_web/components/diff_viewer.ex"))

    refute viewer =~ "Inference"
    refute viewer =~ "Fount.Observe"
    refute views =~ "Inference"
    refute views =~ "Fount.Observe"
    refute index =~ "Inference"
    refute index =~ "Fount.Observe"
    assert index =~ "Fount.Analyzers"
    assert views =~ "Persistence.load_revision"
    assert views =~ "Persistence.candidate"
    assert diff =~ "Fount.Screenplay.diff"
    refute diff =~ "Fount.Diff"
  end
end
