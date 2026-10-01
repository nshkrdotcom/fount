defmodule FountWeb.Components.SourceComparison do
  @moduledoc "Readable current/proposed comparison with wide columns and narrow source tabs."
  use Phoenix.Component

  attr :current, :any, required: true
  attr :other, :any, required: true
  attr :other_label, :string, required: true
  attr :other_status, :string, required: true

  def comparison(assigns) do
    ~H"""
    <section id="source-comparison" class="source-comparison" aria-label="Compare screenplay sources" phx-hook="SourceComparison">
      <header class="source-comparison__heading">
        <div>
          <p class="eyebrow">Exact saved sources</p>
          <h2>Current draft compared with {@other_label}</h2>
        </div>
        <p>{@other_status}. Reading or comparing never changes the current screenplay.</p>
      </header>

      <input class="source-comparison__tab" type="radio" name="source-comparison-tab" id="compare-current" checked />
      <input class="source-comparison__tab" type="radio" name="source-comparison-tab" id="compare-proposed" />
      <input class="source-comparison__tab" type="radio" name="source-comparison-tab" id="compare-changes" />
      <nav class="source-comparison__tabs" aria-label="Comparison view">
        <label for="compare-current">Current</label>
        <label for="compare-proposed">{@other_label}</label>
        <label for="compare-changes">Changes</label>
      </nav>

      <div class="source-comparison__change-nav" role="group" aria-label="Change navigation">
        <button type="button" data-compare-prev>Previous change</button>
        <span data-compare-count>No changes selected</span>
        <button type="button" data-compare-next>Next change</button>
      </div>

      <div class="source-comparison__columns">
        <section class="source-comparison__panel source-comparison__panel--current" aria-label="Current draft">
          <header><strong>Current draft</strong><span>accepted screenplay</span></header>
          <div class="source-comparison__paper">
            <FountWeb.Components.ScreenplayRenderer.screenplay screenplay={@current} />
          </div>
        </section>
        <section class="source-comparison__panel source-comparison__panel--proposed" aria-label={@other_label}>
          <header><strong>{@other_label}</strong><span>{@other_status}</span></header>
          <div class="source-comparison__paper">
            <FountWeb.Components.ScreenplayRenderer.screenplay screenplay={@other} />
          </div>
        </section>
      </div>

      <section class="source-comparison__panel source-comparison__panel--changes" aria-label="Structural changes">
        <FountWeb.Components.DiffViewer.diff
          before={@current}
          after={@other}
          before_label="Current draft"
          after_label={@other_label}
          before_status="current"
          after_status="proposed"
          mode="side-by-side"
        />
        <p class="scope-note">
          Review is read-only here. Making a proposal current remains an explicit typed acceptance action in Changes.
        </p>
      </section>
    </section>
    """
  end
end
