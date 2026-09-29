defmodule FountWeb.SourceContractTest do
  use ExUnit.Case, async: true

  test "library packages remain Phoenix-free and host is the sole web application" do
    for path <- Path.wildcard(Path.expand("../../../../packages/*/mix.exs", __DIR__)) do
      text = File.read!(path)
      refute text =~ "{:phoenix,"
      refute text =~ "{:phoenix_live_view,"
    end

    assert File.exists?(Path.expand("../../mix.exs", __DIR__))
  end

  test "host migration order is Core then Run then host" do
    source = File.read!(Path.expand("../../lib/mix/tasks/fount_web.migrate.ex", __DIR__))
    core = :binary.match(source, "Fount.Persistence.migrations_path()") |> elem(0)
    run = :binary.match(source, "FountRun.migrations_path()") |> elem(0)
    host = :binary.match(source, "FountWeb.Migrations.path()") |> elem(0)
    assert core < run and run < host
  end
end
