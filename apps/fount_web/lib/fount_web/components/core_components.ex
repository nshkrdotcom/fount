defmodule FountWeb.CoreComponents do
  @moduledoc "Small accessible components for the writer workspace."
  use Phoenix.Component

  attr :type, :string, default: "button"
  attr :variant, :string, default: "primary"
  attr :disabled, :boolean, default: false
  attr :busy, :boolean, default: false
  attr :rest, :global
  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={["ui-button", "ui-button--#{@variant}"]}
      disabled={@disabled || @busy}
      aria-busy={if @busy, do: "true", else: nil}
      {@rest}
    >
      <span :if={@busy} class="ui-button__busy" aria-hidden="true">…</span>
      <span>{render_slot(@inner_block)}</span>
    </button>
    """
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, default: ""
  attr :type, :string, default: "text"
  attr :error, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :rest, :global

  def input(assigns) do
    ~H"""
    <div class="ui-field">
      <label for={@id}>{@label}</label>
      <input
        id={@id}
        name={@name}
        type={@type}
        value={@value}
        disabled={@disabled}
        aria-invalid={if @error, do: "true", else: nil}
        aria-describedby={if @error, do: "#{@id}-error", else: nil}
        {@rest}
      />
      <p :if={@error} id={"#{@id}-error"} class="ui-field__error" role="alert">{@error}</p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :error, :string, default: nil
  attr :options, :list, required: true
  attr :rest, :global

  def select(assigns) do
    ~H"""
    <div class="ui-field">
      <label for={@id}>{@label}</label>
      <select
        id={@id}
        name={@name}
        disabled={@disabled}
        aria-invalid={if @error, do: "true", else: nil}
        aria-describedby={if @error, do: "#{@id}-error", else: nil}
        {@rest}
      >
        <option :for={{label, value} <- @options} value={value} selected={to_string(value) == to_string(@value)}>
          {label}
        </option>
      </select>
      <p :if={@error} id={"#{@id}-error"} class="ui-field__error" role="alert">{@error}</p>
    </div>
    """
  end

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <section class={["ui-card", @class]}>{render_slot(@inner_block)}</section>
    """
  end

  attr :status, :string, required: true
  attr :label, :string, default: nil

  def status_badge(assigns) do
    ~H"""
    <span class={["ui-status", "ui-status--#{safe_status(@status)}"]}>
      <span class="ui-status__mark" aria-hidden="true">●</span>
      {@label || human_status(@status)}
    </span>
    """
  end

  attr :kind, :string, default: "info", values: ~w(info warning error success)
  attr :title, :string, default: nil
  slot :inner_block, required: true

  def alert(assigns) do
    ~H"""
    <div class={["ui-alert", "ui-alert--#{@kind}"]} role={if @kind == "error", do: "alert", else: "status"}>
      <strong :if={@title}>{@title}</strong>
      <div>{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :title, :string, default: "Loading"
  attr :detail, :string, default: nil

  def loading_state(assigns) do
    ~H"""
    <div class="ui-state" role="status" aria-live="polite">
      <span class="ui-state__spinner" aria-hidden="true">◌</span>
      <strong>{@title}</strong>
      <p :if={@detail}>{@detail}</p>
    </div>
    """
  end

  attr :title, :string, default: "Nothing here yet"
  attr :detail, :string, default: nil

  def empty_state(assigns) do
    ~H"""
    <div class="ui-state ui-state--empty">
      <strong>{@title}</strong>
      <p :if={@detail}>{@detail}</p>
    </div>
    """
  end

  attr :title, :string, default: "Unable to load"
  attr :detail, :string, required: true

  def error_state(assigns) do
    ~H"""
    <div class="ui-state ui-state--error" role="alert">
      <strong>{@title}</strong>
      <p>{@detail}</p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :open, :boolean, default: false
  attr :return_focus, :string, default: nil
  attr :cancel_event, :string, default: nil
  slot :inner_block, required: true
  slot :actions

  def dialog(assigns) do
    ~H"""
    <div
      :if={@open}
      id={@id}
      class="ui-dialog-backdrop"
      phx-hook="AccessibleDialog"
      data-return-focus={@return_focus}
      data-cancel-event={@cancel_event}
    >
      <section class="ui-dialog" role="dialog" aria-modal="true" aria-labelledby={"#{@id}-title"} tabindex="-1">
        <h2 id={"#{@id}-title"}>{@title}</h2>
        <div>{render_slot(@inner_block)}</div>
        <footer :if={@actions != []} class="ui-dialog__actions">{render_slot(@actions)}</footer>
      </section>
    </div>
    """
  end

  defp safe_status(status) do
    status
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/u, "-")
  end

  defp human_status(status), do: status |> to_string() |> String.replace("_", " ")
end
