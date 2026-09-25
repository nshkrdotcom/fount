defmodule FountWorkshop.RebaseResolutionTest do
  use ExUnit.Case, async: true

  test "unexpected resolution shapes fail before replay or generation" do
    assert {:error, :invalid_rebase_resolution} = FountWorkshop.Rebase.validate_resolutions([])

    assert {:error, :invalid_rebase_resolution} =
             FountWorkshop.Rebase.validate_resolutions(%{"choices" => []})

    assert {:error, :invalid_rebase_resolution} =
             FountWorkshop.Rebase.validate_resolutions(%{"generate" => "yes"})

    assert :ok = FountWorkshop.Rebase.validate_resolutions(%{"choices" => %{"g1" => "current"}})
  end
end
