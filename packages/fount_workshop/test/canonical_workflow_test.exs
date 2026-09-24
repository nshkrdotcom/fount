defmodule FountWorkshop.CanonicalWorkflowTest do
  use ExUnit.Case, async: false

  alias Fount.{ID, Persistence, Repo, Screenplay}
  alias Fount.Persistence.Query
  alias Fount.Persistence.Schema.Acceptance
  alias FountWorkshop.Export.PDF

  setup do
    root =
      Path.join(System.tmp_dir!(), "fount-workshop-sql-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    host = System.get_env("FOUNT_TEST_PGHOST", "/var/run/postgresql")

    opts = [
      database: System.get_env("FOUNT_TEST_DATABASE", "fount_test"),
      username: System.get_env("FOUNT_TEST_USER", "home"),
      password: System.get_env("FOUNT_TEST_PASSWORD"),
      port: System.get_env("FOUNT_TEST_PORT", "5433") |> String.to_integer(),
      pool_size: 5,
      log: false
    ]

    opts =
      if String.starts_with?(host, "/"),
        do: Keyword.put(opts, :socket_dir, host),
        else: Keyword.put(opts, :hostname, host)

    start_supervised!({Repo, opts})
    Ecto.Migrator.run(Repo, Persistence.migrations_path(), :up, all: true, log: false)
    %{store: Repo, root: root}
  end

  test "SQL-backed model proposal previews without writes and accepts once", %{
    store: store,
    root: root
  } do
    model =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. KITCHEN - NIGHT",
            elements: [
              %{type: :character, text: "MARA"},
              %{type: :dialogue, text: "Leave the light on."}
            ]
          }
        ]
      )

    {model, mara} = Screenplay.add_character(model, "Mara")
    cue = Enum.find(model.ir.elements, &(&1.type == :character))
    {:ok, model} = Screenplay.link_cue(model, cue.id, mara.id)
    key = "feature-#{ID.v4()}"
    assert :ok = Persistence.save(store, key, model, expected_revision: :new)
    [scene] = Repo.all(Query.scenes_with(model.id, mara.id))
    dialogue = Enum.find(model.ir.elements, &(&1.type == :dialogue))
    {:ok, loaded_for_context} = Persistence.load(store, key)
    assert {:ok, context} = FountWorkshop.context(loaded_for_context, scene.id)
    assert Enum.any?(context.characters, &(&1.id == mara.id))

    client =
      Inference.client!(
        adapter: Inference.Adapters.Mock,
        provider: :mock,
        model: "revision-test",
        adapter_opts: [
          response_text:
            Jason.encode!(%{
              "operations" => [
                %{
                  "kind" => "replace_text",
                  "target" => dialogue.id,
                  "value" => "Keep the light on."
                }
              ]
            })
        ]
      )

    assert {:ok, proposal} = FountWorkshop.propose(context, "Tighten dialogue", client)
    assert {:ok, preview} = FountWorkshop.preview(model, proposal)
    assert Screenplay.node(preview.document, dialogue.id).text == "Keep the light on."
    assert preview.source_diff != []
    assert {:ok, unchanged} = Persistence.load(store, key)
    assert Screenplay.node(unchanged, dialogue.id).text == "Leave the light on."

    assert :ok = FountWorkshop.accept(store, key, preview, model.revision.id)
    assert {:ok, loaded} = Persistence.load(store, key)
    assert Screenplay.node(loaded, dialogue.id).text == "Keep the light on."

    assert Repo.aggregate(Acceptance, :count, :id) >= 1

    assert {:error, {:conflict, _}} =
             FountWorkshop.accept(store, key, preview, model.revision.id)

    assert {:ok, pdf} = PDF.export(loaded, Path.join(root, "draft.pdf"))
    assert pdf.source_revision == loaded.revision.id
    assert pdf.pages >= 1
  end
end
