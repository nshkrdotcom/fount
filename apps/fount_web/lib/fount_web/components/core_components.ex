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
  attr :rest, :global, include: ~w(placeholder autocomplete maxlength minlength pattern required)

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
        <option
          :for={{label, value} <- @options}
          value={value}
          selected={to_string(value) == to_string(@value)}
        >
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
      {@label || human_status(@status)}
    </span>
    """
  end

  attr :kind, :string, default: "info", values: ~w(info warning error success)
  attr :title, :string, default: nil
  slot :inner_block, required: true

  def alert(assigns) do
    ~H"""
    <div
      class={["ui-alert", "ui-alert--#{@kind}"]}
      role={if @kind == "error", do: "alert", else: "status"}
    >
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
      <section
        class="ui-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
        tabindex="-1"
      >
        <h2 id={"#{@id}-title"}>{@title}</h2>
        <div>{render_slot(@inner_block)}</div>
        <footer :if={@actions != []} class="ui-dialog__actions">{render_slot(@actions)}</footer>
      </section>
    </div>
    """
  end

  attr :project, :map, required: true
  attr :section, :string, default: "script"
  attr :view, :string, default: "reading"
  attr :source_label, :string, default: "Current draft"
  attr :example, :boolean, default: false

  def project_header(assigns) do
    key = assigns.project["key"]

    assigns =
      assigns
      |> assign(:project_key, key)
      |> assign(:script_href, "/p/#{key}")
      |> assign(:write_href, "/p/#{key}/write")
      |> assign(:work_href, "/p/#{key}/work")
      |> assign(:changes_href, "/p/#{key}/changes")
      |> assign(:notes_href, "/p/#{key}/notes")

    ~H"""
    <header class="project-header">
      <div class="project-header__identity">
        <a class="project-header__home" href="/" aria-label="All projects">Fount</a>
        <span aria-hidden="true">/</span>
        <strong>{@project["title"]}</strong>
        <span :if={@example} class="project-header__flag">Example</span>
        <span class="project-header__source">{@source_label}</span>
      </div>

      <div class="project-header__view" role="group" aria-label="Workspace view">
        <a href={@write_href} aria-current={if @view == "writing", do: "page"}>Writing</a>
        <a href={@script_href} aria-current={if @view == "reading", do: "page"}>Reading</a>
      </div>

      <nav class="project-tabs" aria-label="Project">
        <a href={@script_href} aria-current={if @section == "script", do: "page"}>Script</a>
        <a href={@work_href} aria-current={if @section == "work", do: "page"}>Work on it</a>
        <a href={@changes_href} aria-current={if @section == "changes", do: "page"}>Changes</a>
        <a href={@notes_href} aria-current={if @section == "notes", do: "page"}>Notes</a>
        <details class="project-more">
          <summary>More</summary>
          <div class="project-more__menu">
            <a href={"/p/#{@project_key}/analysis"}>Analysis</a>
            <a href={"/p/#{@project_key}/cast"}>Cast &amp; locations</a>
            <a href={"/p/#{@project_key}/read"}>Table read</a>
            <a href={"/p/#{@project_key}/feedback"}>Feedback</a>
            <a href={"/p/#{@project_key}/history"}>History</a>
            <a href={"/p/#{@project_key}/exports"}>Exports</a>
            <a href={"/p/#{@project_key}/activity"}>Activity</a>
            <a href={"/p/#{@project_key}/settings"}>Project settings</a>
          </div>
        </details>
        <a class="project-tabs__help" href={"/help?project=#{URI.encode_www_form(@project_key)}"}>Help</a>
      </nav>
    </header>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :summary, :string, default: nil
  attr :open, :boolean, default: false
  slot :inner_block, required: true

  def disclosure(assigns) do
    ~H"""
    <details id={@id} class="ui-disclosure" open={@open}>
      <summary>
        <span>{@title}</span>
        <small :if={@summary}>{@summary}</small>
      </summary>
      <div class="ui-disclosure__body">{render_slot(@inner_block)}</div>
    </details>
    """
  end

  attr :slug, :string, required: true
  attr :title, :string, required: true
  attr :dismissed, :boolean, default: false
  attr :dismiss_event, :string, default: "dismiss_hint"
  attr :project_key, :string, default: nil
  slot :inner_block, required: true

  def contextual_help(assigns) do
    help_href =
      if assigns.project_key,
        do: "/help?project=#{URI.encode_www_form(assigns.project_key)}##{assigns.slug}",
        else: "/help##{assigns.slug}"

    assigns = assign(assigns, :help_href, help_href)

    ~H"""
    <aside :if={not @dismissed} class="context-help" aria-labelledby={"help-#{@slug}-title"}>
      <div>
        <strong id={"help-#{@slug}-title"}>{@title}</strong>
        <div>{render_slot(@inner_block)}</div>
      </div>
      <div class="context-help__actions">
        <a href={@help_href}>More help</a>
        <button type="button" phx-click={@dismiss_event} phx-value-slug={@slug}>Dismiss</button>
      </div>
    </aside>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  def named_reference(assigns) do
    ~H"""
    <span class="named-reference"><span>{@label}</span><strong>{@value}</strong></span>
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
