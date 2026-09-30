defmodule FountWeb.Components.ScreenplayRenderer do
  @moduledoc "Pure HEEx renderer for the canonical screenplay IR."
  use Phoenix.Component

  alias Fount.Query

  attr :screenplay, :any, required: true
  attr :selected_scene_id, :string, default: nil

  def screenplay(assigns) do
    screenplay = assigns.screenplay

    assigns =
      assigns
      |> assign(:title_entries, title_entries(screenplay))
      |> assign(:render_items, render_items(screenplay))
      |> assign(:scene_by_heading, scene_by_heading(screenplay))

    ~H"""
    <article
      class="screenplay"
      data-screenplay-id={@screenplay.id}
      data-revision-id={@screenplay.revision.id}
    >
      <header :if={@title_entries != []} class="screenplay-title-page" aria-label="Title page">
        <dl>
          <div :for={entry <- @title_entries} class="screenplay-title-entry">
            <dt>{entry.key}</dt>
            <dd :for={value <- entry.values}>{value}</dd>
          </div>
        </dl>
      </header>

      <FountWeb.CoreComponents.empty_state
        :if={@render_items == []}
        title="Empty screenplay"
        detail="This revision contains no screenplay elements."
      />

      <div class="screenplay-body">
        <%= for item <- @render_items do %>
          <.render_item
            item={item}
            scene_by_heading={@scene_by_heading}
            selected_scene_id={@selected_scene_id}
          />
        <% end %>
      </div>
    </article>
    """
  end

  attr :item, :any, required: true
  attr :scene_by_heading, :map, required: true
  attr :selected_scene_id, :string, default: nil

  defp render_item(%{item: {:dual, left, right}} = assigns) do
    assigns = assign(assigns, left: left, right: right)

    ~H"""
    <div class="screenplay-dual" role="group" aria-label="Dual dialogue">
      <.dialogue_block block={@left} />
      <.dialogue_block block={@right} />
    </div>
    """
  end

  defp render_item(%{item: {:dialogue, block}} = assigns) do
    assigns = assign(assigns, block: block)

    ~H"""
    <.dialogue_block block={@block} />
    """
  end

  defp render_item(%{item: {:element, element}} = assigns) do
    scene = Map.get(assigns.scene_by_heading, element.id)
    scene_id = scene && scene.id

    assigns =
      assigns
      |> assign(:element, element)
      |> assign(:scene, scene)
      |> assign(:scene_id, scene_id)
      |> assign(:css_type, css_type(element.type))
      |> assign(:known, known_type?(element.type))

    ~H"""
    <div
      id={if @scene, do: "scene-#{@scene.id}", else: "node-#{@element.id}"}
      class={[
        "screenplay-element",
        "screenplay-element--#{@css_type}",
        @scene_id && @scene_id == @selected_scene_id && "is-selected-scene",
        !@known && "screenplay-element--fallback"
      ]}
      data-node-id={@element.id}
      data-node-type={to_string(@element.type)}
      tabindex={if @scene, do: "-1", else: nil}
    >
      <span :if={@scene} id={"node-#{@element.id}"} class="screenplay-node-anchor" aria-hidden="true"></span>
      <span :if={!@known} class="screenplay-element__fallback-label">
        Unsupported element type: {to_string(@element.type)}
      </span>
      <span :if={@scene && @scene.number} class="screenplay-scene-number" aria-label="Scene number">
        {@scene.number}
      </span>
      <span class="screenplay-element__text">{@element.text}</span>
    </div>
    """
  end

  attr :block, :any, required: true

  defp dialogue_block(assigns) do
    ~H"""
    <div
      id={"dialogue-#{@block.id}"}
      class={["screenplay-dialogue-block", @block.side && "screenplay-dialogue-block--#{@block.side}"]}
      data-dialogue-block-id={@block.id}
      data-dual-with={@block.dual_with}
    >
      <div
        :for={element <- @block.elements}
        id={"node-#{element.id}"}
        class={["screenplay-element", "screenplay-element--#{css_type(element.type)}"]}
        data-node-id={element.id}
        data-node-type={to_string(element.type)}
      >
        <span class="screenplay-element__text">{element.text}</span>
      </div>
    </div>
    """
  end

  defp title_entries(%{ir: %{title_page: %{entries: entries}}}) when is_list(entries), do: entries
  defp title_entries(_), do: []

  defp scene_by_heading(screenplay), do: Map.new(screenplay.ir.scenes, &{&1.heading_id, &1})

  defp render_items(screenplay) do
    blocks = screenplay.ir.dialogue_blocks || []
    by_cue = Map.new(blocks, &{&1.cue_id, &1})
    by_id = Map.new(blocks, &{&1.id, &1})
    body_ids = blocks |> Enum.flat_map(& &1.body_ids) |> MapSet.new()

    {items, _seen} =
      Enum.reduce(screenplay.ir.elements || [], {[], MapSet.new()}, fn element, {items, seen} ->
        cond do
          MapSet.member?(body_ids, element.id) ->
            {items, seen}

          block = by_cue[element.id] ->
            render_block_item(screenplay, block, by_id, items, seen)

          true ->
            {items ++ [{:element, element}], seen}
        end
      end)

    items
  end

  defp render_block_item(screenplay, block, by_id, items, seen) do
    cond do
      MapSet.member?(seen, block.id) ->
        {items, seen}

      is_binary(block.dual_with) ->
        partner = by_id[block.dual_with]

        if partner && !MapSet.member?(seen, partner.id) do
          {left, right} =
            dual_order(block_payload(screenplay, block), block_payload(screenplay, partner))

          {items ++ [{:dual, left, right}],
           seen |> MapSet.put(block.id) |> MapSet.put(partner.id)}
        else
          {items ++ [{:dialogue, block_payload(screenplay, block)}], MapSet.put(seen, block.id)}
        end

      true ->
        {items ++ [{:dialogue, block_payload(screenplay, block)}], MapSet.put(seen, block.id)}
    end
  end

  defp block_payload(screenplay, block) do
    ids = [block.cue_id | block.body_ids]
    elements = Enum.map(ids, &Query.node(screenplay, &1)) |> Enum.reject(&is_nil/1)
    %{id: block.id, dual_with: block.dual_with, side: block.side, elements: elements}
  end

  defp dual_order(%{side: :right} = right, left), do: {left, right}
  defp dual_order(left, right), do: {left, right}

  defp known_type?(type),
    do:
      type in [
        :scene_heading,
        :action,
        :character,
        :dialogue,
        :parenthetical,
        :transition,
        :centered,
        :lyric,
        :section,
        :synopsis,
        :page_break,
        :note,
        :boneyard,
        :blank
      ]

  defp css_type(type), do: type |> to_string() |> String.replace("_", "-")
end
