defmodule FountWorkshop.Audition do
  @moduledoc "Continuous candidate scene context and real optional rendering/rehearsal."
  alias FountWorkshop.Store

  def build(id, selection, services, opts \\ []) do
    with {:ok, candidate} <- Store.call(services[:store], :candidate, [id]),
         {:ok, units} <- FountProbe.Projection.select(candidate["screenplay"], selection) do
      model = candidate["screenplay"]
      ids = Enum.map(model.ir.scenes, & &1.id)
      selected = units |> Enum.map(& &1["scene_id"]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

      context_ids =
        Enum.flat_map(selected, fn sid ->
          index = Enum.find_index(ids, &(&1 == sid))
          Enum.slice(ids, max(index - 1, 0), if(index == 0, do: 2, else: 3))
        end)
        |> Enum.uniq()

      removed = ids -- context_ids

      operations =
        Enum.map(
          removed,
          &%{"kind" => "delete_scene", "target" => %{"kind" => "scene", "id" => &1}}
        )

      with {:ok, view, _} <- Fount.Screenplay.apply(model, operations, []) do
        output = Keyword.get(opts, :output_dir)

        if is_binary(output) do
          File.mkdir_p!(output)
          pages = Path.join(output, id <> ".audition.fountain")
          File.write!(pages, Fount.Screenplay.to_fountain(view, mode: :spec))

          {:ok, json} =
            FountWorkshop.TableRead.export(view, Path.join(output, id <> ".audition.json"), :json)

          {:ok, html} =
            FountWorkshop.TableRead.export(view, Path.join(output, id <> ".audition.html"), :html)

          pdf =
            if Keyword.get(opts, :pdf, false),
              do:
                FountWorkshop.Writing.Layout.render(
                  services[:renderer],
                  view,
                  Path.join(output, id <> ".audition.pdf"),
                  opts
                ),
              else: {:error, :not_requested}

          speech =
            if Keyword.get(opts, :speech, false),
              do:
                FountWorkshop.TableRead.render_audio(
                  view,
                  Path.join(output, "audio"),
                  services[:voices] || %{},
                  opts
                ),
              else: {:error, :not_requested}

          {:ok,
           %{
             "candidate_id" => id,
             "source_revision_id" => model.revision.id,
             "transient_revision_id" => view.revision.id,
             "scene_ids" => context_ids,
             "fountain" => pages,
             "json" => json,
             "html" => html,
             "pdf" => pdf,
             "speech" => speech
           }}
        else
          {:error, :output_directory_required}
        end
      end
    end
  end
end
