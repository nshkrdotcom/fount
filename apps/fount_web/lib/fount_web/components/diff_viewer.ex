defmodule FountWeb.Components.DiffViewer do
  @moduledoc "Read-only structural diff for persistent screenplay revisions."
  use Phoenix.Component

  attr :before, :any, required: true
  attr :after, :any, required: true
  attr :before_label, :string, default: "Base"
  attr :after_label, :string, default: "Candidate"
  attr :before_status, :string, default: "base"
  attr :after_status, :string, default: "candidate"
  attr :mode, :string, default: "unified", values: ~w(unified side-by-side)

  def diff(assigns) do
    case diff_payload(assigns.before, assigns.after) do
      {:ok, payload} ->
        assigns = assigns |> assign(:payload, payload) |> assign(:after_model, assigns.after)

        ~H"""
        <section class={["diff-viewer", "diff-viewer--#{@mode}"]} aria-label="Screenplay diff">
          <header class="diff-viewer__header">
            <div>
              <strong>{@before_label}</strong>
              <FountWeb.CoreComponents.status_badge status={@before_status} label={@before_status} />
              <code>{@before.revision.id}</code>
            </div>
            <div>
              <strong>{@after_label}</strong>
              <FountWeb.CoreComponents.status_badge status={@after_status} label={@after_status} />
              <code>{@after_model.revision.id}</code>
            </div>
          </header>
          <p :if={@payload.entries == []} class="diff-viewer__unchanged">No structural changes.</p>
          <div :if={@payload.entries != []} class="diff-viewer__entries">
            <article
              :for={entry <- @payload.entries}
              class={["diff-entry", "diff-entry--#{entry.change}"]}
            >
              <span class="diff-entry__label">{change_label(entry.change)}</span>
              <code>{entry.id}</code>
              <div class="diff-entry__content">
                <pre :if={entry.before}>{entry.before}</pre>
                <pre :if={entry.after}>{entry.after}</pre>
              </div>
            </article>
          </div>
        </section>
        """

      {:error, reason} ->
        assigns = assign(assigns, :reason, reason)

        ~H"""
        <FountWeb.CoreComponents.error_state
          title="Diff unavailable"
          detail={diff_error(@reason)}
        />
        """
    end
  end

  def diff_payload(%Fount.Screenplay{id: id} = before, %Fount.Screenplay{id: id} = after_model) do
    structural = Fount.Screenplay.diff(before, after_model)
    before_elements = Map.new(before.ir.elements, &{&1.id, &1})
    after_elements = Map.new(after_model.ir.elements, &{&1.id, &1})

    element_entries =
      []
      |> add_entries(:removed, structural.elements.removed, before_elements, after_elements)
      |> add_entries(:added, structural.elements.added, before_elements, after_elements)
      |> add_entries(:changed, structural.elements.changed, before_elements, after_elements)

    moved_entries =
      Enum.map(structural.scenes.moved, fn scene_id ->
        %{
          id: scene_id,
          kind: :scene,
          change: :moved,
          before: "Earlier scene position",
          after: "New scene position"
        }
      end)

    {:ok, %{structural: structural, entries: element_entries ++ moved_entries}}
  end

  def diff_payload(%Fount.Screenplay{}, %Fount.Screenplay{}), do: {:error, :different_screenplay}
  def diff_payload(_, _), do: {:error, :screenplay_required}

  defp add_entries(entries, change, ids, before_elements, after_elements) do
    entries ++
      Enum.map(ids, fn id ->
        %{
          id: id,
          kind: :element,
          change: change,
          before: element_text(before_elements[id]),
          after: element_text(after_elements[id])
        }
      end)
  end

  defp element_text(nil), do: nil
  defp element_text(element), do: "#{element.type}: #{element.text}"
  defp change_label(:added), do: "Added"
  defp change_label(:removed), do: "Removed"
  defp change_label(:changed), do: "Changed"
  defp change_label(:moved), do: "Moved"

  defp diff_error(:different_screenplay),
    do: "The selected revisions belong to different screenplay identities."

  defp diff_error(:screenplay_required),
    do: "Persistent Fount.Screenplay revisions are required for this diff."

  defp diff_error(reason), do: inspect(reason)
end
