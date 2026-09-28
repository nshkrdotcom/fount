defmodule FountWorkshop.Share do
  @moduledoc """
  Builds reader-safe screenplay copies from accepted canonical material.

  Share exports intentionally exclude private notes, boneyards, omitted scenes,
  Workshop candidates, and provider metadata. The export manifest records what
  was excluded and any adapter losses without copying excluded text into the
  reader packet.
  """

  alias Fount.Screenplay
  alias Fount.Screenplay.Editor
  alias Fount.Screenplay.Model
  alias Fount.Selection
  alias Fount.Writing.CanonicalJSON

  @formats [:fountain, :fdx]

  @doc "Exports a clean whole-screenplay or scene selection plus a privacy/fidelity manifest."
  @spec export(Screenplay.t(), map(), Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def export(%Screenplay{} = model, selection, directory, opts \\ [])
      when is_map(selection) and is_binary(directory) do
    formats = Keyword.get(opts, :formats, @formats)

    with :ok <- validate_formats(formats),
         :ok <- validate_selection(selection),
         {:ok, selected_ids} <- Selection.selected_ids(model, selection),
         {:ok, projection, privacy} <- projection(model, selected_ids),
         :ok <- File.mkdir_p(directory),
         {:ok, exports} <- write_exports(projection, formats, directory) do
      manifest = %{
        "version" => 1,
        "kind" => "fount.clean_reader_share",
        "source" => %{
          "screenplay_id" => model.id,
          "revision_id" => model.revision.id,
          "content_hash" => model.revision.content_hash
        },
        "selection" => selection,
        "selection_sha256" => CanonicalJSON.hash(selection),
        "privacy" => privacy,
        "exports" => exports,
        "unsupported_or_lossy" =>
          exports
          |> Map.values()
          |> Enum.flat_map(&(&1["losses"] || []))
          |> Enum.uniq(),
        "claims" => %{
          "provider_metadata_included" => false,
          "workshop_candidates_included" => false,
          "private_note_text_included" => false,
          "audience_response_measured" => false
        }
      }

      path = Path.join(directory, "share.manifest.json")
      body = Jason.encode!(manifest, pretty: true)

      with :ok <- File.write(path, body) do
        {:ok,
         Map.put(manifest, "manifest", %{
           "path" => path,
           "sha256" => sha256(body)
         })}
      end
    end
  end

  def export(_, _, _, _), do: {:error, :invalid_share_request}

  @doc false
  def project(%Screenplay{} = model, selection) when is_map(selection) do
    with :ok <- validate_selection(selection),
         {:ok, selected_ids} <- Selection.selected_ids(model, selection),
         {:ok, projection, privacy} <- projection(model, selected_ids) do
      {:ok, projection, privacy}
    end
  end

  defp projection(model, selected_ids) do
    safe_ir = Editor.spec_ir(model)

    elements =
      Enum.filter(safe_ir.elements, fn element ->
        MapSet.member?(selected_ids, element.id)
      end)

    private_note_count = count_selected(model, selected_ids, :note)
    boneyard_count = count_selected(model, selected_ids, :boneyard)
    section_count = count_selected(model, selected_ids, :section)
    synopsis_count = count_selected(model, selected_ids, :synopsis)

    omitted_scene_count =
      Enum.count(model.ir.scenes, fn scene ->
        scene.omitted? and Enum.any?(scene.element_ids, &MapSet.member?(selected_ids, &1))
      end)

    projection =
      model
      |> Map.put(:ir, %{safe_ir | elements: elements})
      |> Map.put(:import, nil)
      |> Model.refresh()

    privacy = %{
      "excluded_counts" => %{
        "private_notes" => private_note_count,
        "boneyards" => boneyard_count,
        "omitted_scenes" => omitted_scene_count,
        "sections" => section_count,
        "synopses" => synopsis_count
      },
      "excluded_workshop_state" => [
        "unselected_candidates",
        "rejected_candidates",
        "provider_metadata",
        "analysis_packets",
        "private_notes",
        "boneyards",
        "omitted_scenes"
      ]
    }

    {:ok, projection, privacy}
  end

  defp write_exports(model, formats, directory) do
    Enum.reduce_while(formats, {:ok, %{}}, fn format, {:ok, acc} ->
      case export_data(model, format) do
        {:ok, data, losses} ->
          name = filename(format)
          path = Path.join(directory, name)

          case File.write(path, data) do
            :ok ->
              item = %{
                "path" => name,
                "format" => to_string(format),
                "sha256" => sha256(data),
                "bytes" => byte_size(data),
                "losses" => Enum.uniq(losses)
              }

              {:cont, {:ok, Map.put(acc, to_string(format), item)}}

            error ->
              {:halt, error}
          end

        error ->
          {:halt, error}
      end
    end)
  end

  defp export_data(model, :fountain) do
    {:ok, result} = Screenplay.export_fountain(model, mode: :spec)
    {:ok, result.data, result.losses}
  end

  defp export_data(model, :fdx) do
    with {:ok, result} <- Screenplay.to_fdx(model) do
      {:ok, result.data, result.losses}
    end
  end

  defp filename(:fountain), do: "screenplay.fountain"
  defp filename(:fdx), do: "screenplay.fdx"

  defp validate_formats(formats) when is_list(formats) and formats != [] do
    if Enum.all?(formats, &(&1 in @formats)), do: :ok, else: {:error, :unsupported_share_format}
  end

  defp validate_formats(_), do: {:error, :invalid_share_formats}

  defp validate_selection(%{"whole_screenplay" => true}), do: :ok

  defp validate_selection(%{"targets" => targets}) when is_list(targets) and targets != [] do
    if Enum.all?(targets, &scene_target?/1),
      do: :ok,
      else: {:error, :clean_share_requires_whole_scenes}
  end

  defp validate_selection(_), do: {:error, :invalid_share_selection}

  defp scene_target?(%{"kind" => "scene", "id" => id} = target) when is_binary(id),
    do: is_nil(target["span"])

  defp scene_target?(_), do: false

  defp count_selected(model, selected_ids, type) do
    Enum.count(model.ir.elements, fn element ->
      element.type == type and MapSet.member?(selected_ids, element.id)
    end)
  end

  defp sha256(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
end
