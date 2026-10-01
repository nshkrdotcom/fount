defmodule FountWeb.Help do
  @moduledoc "Searchable, provider-free help content for the project workspace."

  @topics [
    %{
      slug: "first-project",
      title: "Start a screenplay",
      summary: "Import Fountain/FDX, start blank, or open LAST RETURN without starting AI work.",
      body: "A project opens on screenplay pages. Importing or starting blank creates no creative task, makes no provider call and does not require model or task settings."
    },
    %{
      slug: "import",
      title: "Import screenplay",
      summary: "Fountain and Final Draft .fdx are accepted up to 1 MiB.",
      body: "Preview the detected format and any fidelity notes before opening the screenplay. If parsing fails, choose another file or correct the original; the failed upload never becomes a screenplay."
    },
    %{
      slug: "example",
      title: "LAST RETURN example",
      summary: "A short provider-free screenplay saved through the normal project path.",
      body: "LAST RETURN is real persisted screenplay content, not a screenshot or model-generated placeholder. Read the pages, open About and compare source labels; no provider credential is needed."
    },
    %{
      slug: "writing",
      title: "Writing and saving",
      summary: "Working text is recovery state; saving proposed work does not make it current.",
      body: "The editor preserves raw text, including invalid Fountain, and uses optimistic versioning for two-tab conflicts. A proposed candidate remains separate until an authorized Make current action succeeds."
    },
    %{
      slug: "reading",
      title: "Reading view",
      summary: "Responsive pages are for comfortable browser reading, not fixed PDF page numbers.",
      body: "Reading view keeps screenplay text central. Browser width and reader text size can reflow the responsive view. Exact exported-page references belong to the fixed-layout reader, which is not part of this arrival workspace yet."
    },
    %{
      slug: "sources",
      title: "Current, working and proposed pages",
      summary: "Source labels say which exact screenplay state you are looking at.",
      body: "Current draft is the accepted screenplay. Working draft is owner recovery text. Proposed change is a saved candidate. Reading another source never grants permission or advances the accepted screenplay."
    },
    %{
      slug: "about",
      title: "About this screenplay",
      summary: "Optional supplied context and precise facts from the selected source.",
      body: "Logline and synopsis are project metadata. Script facts count literal scenes/cues/headings from the selected source. They are not coverage scores, shooting estimates or creative judgments."
    },
    %{
      slug: "work-on-it",
      title: "Work on it",
      summary: "Creative tasks use the existing durable task path only after you request creative work.",
      body: "Manual reading and writing do not need a task. The current advanced task controls remain available. Creative work opens a task only when you ask for it; manual reading and writing stay task-free."
    },
    %{
      slug: "changes",
      title: "Changes",
      summary: "Proposed writing remains separate from the current screenplay until explicit acceptance.",
      body: "Changes lists real saved task/proposal work. A stale or cross-owner proposal cannot silently become current. The focused comparison workflow is not available yet; current task review remains reachable."
    },
    %{
      slug: "notes",
      title: "Notes",
      summary: "Notes retain their exact screenplay source.",
      body: "Existing note controls remain reachable. The full note-to-task-to-reviewed-revision loop is not available yet; existing task-bound notes remain reachable."
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
