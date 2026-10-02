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
        "Reading view keeps screenplay text central and quiet. Browser width can reflow the responsive view; Current, Working and Proposed remain visibly distinct. Select text inside one screenplay passage to start a note already bound to that exact passage and source. When a PDF has actually been built for the exact current revision, Page layout can open those fixed exported pages; otherwise Reading stays responsive rather than inventing page coordinates."
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
        "Read literal cue blocks with scene context and return links, without a provider call.",
      body:
        "Character dialogue can be read from literal source cues before semantic identity is confirmed. Speaking is not the same as physical presence or a prose mention, and O.S./voice-only cues never imply presence. Each displayed line returns to its exact source passage; reading or reviewing creates no Run."
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
        "Create a source-bound note, optionally categorize it, and use the visible search/status/category filters to return to it. Search exact literal passages to remap changed targets without pasting IDs; changed and deleted targets stay explicit. Reviewer responses are Addressed, Not addressed or Deferred human records on a named revision. Open means there is no saved reviewer-response record. Two-tab conflicts preserve the response you were trying to save so you can compare and retry. Notes memos contain only selected verbatim notes, supplied From/To fields and optional actual saved responses."
    },
    %{
      slug: "script-search",
      title: "Literal screenplay search",
      summary: "Search the selected exact source with explicit filters and result limits.",
      body:
        "Search is case-insensitive literal phrase matching over the selected screenplay revision. Scene, character, location and element-type filters combine with explicit omitted/note/boneyard inclusion flags. The result count, inspected source count and truncation state are shown. No provider, semantic embedding index or cross-project search is used."
    },
    %{
      slug: "cast-locations",
      title: "Cast & locations",
      summary: "Literal source facts stay separate from reviewed identities, places and screenplay truth.",
      body:
        "Cast and Locations are separate local destinations. A literal uppercase cue is only a source occurrence until a reviewer confirms what it represents; generic guards, printed words, young/adult variants and aliases are never merged by spelling alone. Historical literal-cue cast is labeled legacy/unreviewed while writer-authored Core identities remain confirmed. Locations preserve raw headings and keep place, subplace, time of day, date/era and relative time separate. Manual confirm/reject/type/merge/split/alias/hierarchy/time review is pinned to the exact owner, project, revision and source hash, has append-only conflict history and creates no Run. If the screenplay revision changes, the old review becomes historical rather than silently rebinding to the new source. Model assessment is intentionally Not configured until SI02, so SI01 source review makes no provider call and sends no screenplay material to a model. Promoting a reviewed identity creates proposed Core work only; deliberate typed acceptance is still required to change the current screenplay."
    },
    %{
      slug: "analysis",
      title: "Analysis findings",
      summary:
        "Start with source evidence, then interpretation, limitations and optional graphs.",
      body:
        "Analysis only shows saved task evidence. Exact excerpts and source links come first; uncertainty, missing evidence, sample/resource limitations and service state remain visible. Optional story/time/reader graphs have textual list equivalents and never become a screenplay quality score. No analysis is invented merely to fill the screen."
    },
    %{
      slug: "table-read",
      title: "Human table read",
      summary: "Read saved exact material without creating a synthetic Run.",
      body:
        "Create named table-read material from the current saved revision, then navigate with Previous/Next or keyboard, pause bounded auto-scroll, choose a finite speed, bookmark a passage, retain elapsed time and save human reactions. If another tab changes the same read, Fount preserves your local bookmark/timing or reaction and offers a reload/retry path instead of silently overwriting it. Reduced-motion preference disables automatic scrolling while manual controls stay available. TTS appears only when actually configured; there is no microphone capture or automatic performance scoring."
    },
    %{
      slug: "feedback",
      title: "Optional feedback",
      summary: "Useful, Mixed or Not useful stays descriptive human evidence.",
      body:
        "Feedback appears only after a task has a reviewable completed result and automatically records its engineering facts. Reopening that task restores the saved Useful/Mixed/Not useful response, kept-original choice, notes and optional dimensions; saving again updates that record rather than creating a duplicate. Relevant quick questions can be explicitly cleared. All human dimensions remain independent, and Fount does not combine them into a quality score, winner or preference-learning claim."
    },
    %{
      slug: "exports",
      title: "Exports and fixed-layout pages",
      summary:
        "Build Fountain, FDX or PDF from the exact named current source and recover cleanly from errors.",
      body:
        "Project exports are owner-bound to the exact saved revision shown at build time. Fountain and FDX preserve explicit fidelity/loss information; PDF uses the configured screenplay renderer and inspection tools, and table-read packets retain their exact saved source. A failed build records the error and can be retried without changing screenplay state. The exported-page reader displays the real PDF and supports page jump; it never invents a passage-to-page mapping the renderer did not provide. Optional submission checks reuse recorded dated mechanical profiles against that exact current PDF and always show their profile date/source; they are not legal advice, endorsement or a guarantee of current rules."
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
