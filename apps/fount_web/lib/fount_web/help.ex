defmodule FountWeb.Help do
  @moduledoc "Searchable, provider-free help content for the project workspace."

  @topics [
    %{
      slug: "first-project",
      title: "Start a screenplay",
      summary: "Import Fountain/FDX, start blank, or open LAST RETURN without starting AI work.",
      body:
        "A project opens on screenplay pages. Importing or starting blank creates no creative task, makes no provider call and does not require model or task settings."
    },
    %{
      slug: "import",
      title: "Import screenplay",
      summary: "Fountain and Final Draft .fdx are accepted up to 1 MiB.",
      body:
        "Preview the detected format and any fidelity notes before opening the screenplay. If parsing fails, choose another file or correct the original; the failed upload never becomes a screenplay."
    },
    %{
      slug: "example",
      title: "LAST RETURN example",
      summary: "A short provider-free screenplay saved through the normal project path.",
      body:
        "LAST RETURN is real persisted screenplay content, not a screenshot or model-generated placeholder. Read the pages, open About and compare source labels; no provider credential is needed."
    },
    %{
      slug: "writing",
      title: "Writing and saving",
      summary: "Working text is recovery state; saving proposed work does not make it current.",
      body:
        "The editor preserves raw text, including invalid Fountain, and uses optimistic versioning for two-tab conflicts. A proposed candidate remains separate until an authorized Make current action succeeds."
    },
    %{
      slug: "reading",
      title: "Reading view",
      summary:
        "Responsive pages are for comfortable browser reading, not fixed PDF page numbers.",
      body:
        "Reading view keeps screenplay text central. Browser width and reader text size can reflow the responsive view. Exact exported-page references belong to the fixed-layout reader, which is not part of this arrival workspace yet."
    },
    %{
      slug: "sources",
      title: "Current, working and proposed pages",
      summary: "Source labels say which exact screenplay state you are looking at.",
      body:
        "Current draft is the accepted screenplay. Working draft is owner recovery text. Proposed change is a saved candidate. Reading another source never grants permission or advances the accepted screenplay."
    },
    %{
      slug: "about",
      title: "About this screenplay",
      summary: "Optional supplied context and precise facts from the selected source.",
      body:
        "Logline and synopsis are project metadata. Script facts count literal scenes/cues/headings from the selected source. They are not coverage scores, shooting estimates or creative judgments."
    },
    %{
      slug: "work-on-it",
      title: "Work on it",
      summary:
        "Ask a short question, bind it to named screenplay material, then review the exact brief before starting.",
      body:
        "Develop, targeted rewrite, focused pass, alternatives, sequence, character, propagate, notes, recover and investigate all use the existing durable Run → Workshop path. Scope and protected passages resolve against the selected exact revision. Starting saves a task; proposed writing never becomes current merely because it was generated or saved."
    },
    %{
      slug: "focus-writing",
      title: "Focus and editor recovery",
      summary: "Focus hides chrome only; it never changes, saves or replaces screenplay text.",
      body:
        "Use Focus when you want only the Fountain editor. Press Escape or the Focus button to leave it. Optional Typewriter scroll is off by default, follows the cursor without smooth animation, and disables itself when reduced motion is requested. It never rewrites Tab or Enter. Autosave, IME composition, local undo, lost-ack handling, two-tab conflicts and recovery keep their normal behavior. Conflict and save state remain authoritative whether Focus is open or closed."
    },
    %{
      slug: "scene-cards",
      title: "Scene cards and structural edits",
      summary:
        "Move, omit/include, insert, replace or delete by screenplay name instead of copying internal IDs.",
      body:
        "Scene cards are source-bound to the working draft. Use Up/Down buttons or Alt+Arrow Up/Down from a focused scene card. Exact element edits use named pickers. Structural and text undo/redo remain separate, and every change stays in the working draft until a proposal is deliberately accepted."
    },
    %{
      slug: "creative-catalog",
      title: "Creative task families",
      summary:
        "Each creative card has real validated inputs and the same durable task/review authority boundary.",
      body:
        "The default brief keeps three common choices visible and preserves what you typed when you change task type. All tasks opens the complete searchable catalog, grouped as Write, Explore, Revise and Restore. Task-specific details appear only when needed: pass profile, alternative count, target scene count, character, placement, notes or historical recovery source. Investigate saves findings without granting mutation authority. Unavailable analysis never counts as successful analysis."
    },
    %{
      slug: "task-controls",
      title: "Review steps, limits and saved settings",
      summary: "Choose checkpoints and finite budgets without editing internal policy data.",
      body:
        "Review steps preserve the existing investigation, approach, generation and iteration gates plus authorized approvers and routing. Time and spending limits preserve the existing ceilings. Spending is entered in ordinary currency units and converted exactly to microunits. Saved settings are versioned policies, not creative genre presets."
    },
    %{
      slug: "line-alternatives",
      title: "Try another line",
      summary:
        "A dialogue or parenthetical line can launch finite alternatives while surrounding dialogue is protected.",
      body:
        "Try another line binds the exact selected element and byte-exact surrounding cue/body protections to the existing alternatives workflow. Results are proposed candidate work. Auditioning or choosing an alternative does not advance the current screenplay; comparison and acceptance remain separate."
    },
    %{
      slug: "character-dialogue",
      title: "Read a character's dialogue",
      summary:
        "Read literal confirmed cue blocks with scene context and return links, without a provider call.",
      body:
        "Character dialogue is derived from the selected screenplay source using confirmed cast identity and existing dialogue blocks. It does not infer performance, intent or character quality. Each displayed line returns to its exact source passage."
    },
    %{
      slug: "changes",
      title: "Changes",
      summary:
        "Proposed writing remains separate from the current screenplay until explicit acceptance.",
      body:
        "Changes lists real saved task/proposal work and distinguishes an approach choice from actual proposed pages. Open Review for the exact current/proposed comparison, required checks and source lineage. Make current remains an explicit typed acceptance path; stale and cross-owner proposals are rejected by the existing authority checks."
    },
    %{
      slug: "notes",
      title: "Notes",
      summary: "Notes retain their exact screenplay source.",
      body:
        "Create a source-bound note as a proposal, deliberately accept the note into the current screenplay, then use Work on this note now. The host persists the factual note-to-task/proposal relation; it never infers that a launched task resolved or addressed the note. Full reviewer responses, final remap and memo delivery remain later work."
    }
  ]

  def all, do: @topics

  def search(query) when is_binary(query) do
    query = query |> String.trim() |> String.downcase()

    if query == "" do
      @topics
    else
      Enum.filter(@topics, fn topic ->
        [topic.title, topic.summary, topic.body]
        |> Enum.join(" ")
        |> String.downcase()
        |> String.contains?(query)
      end)
    end
  end

  def search(_), do: @topics

  def topic(slug), do: Enum.find(@topics, &(&1.slug == slug))
end
