defmodule FountWeb.ExampleProject do
  @moduledoc "Provider-free UX01 example authored in the writer-experience specification."

  @title "LAST RETURN · Example"
  @source """
  Title: LAST RETURN
  Credit: A short example screenplay

  INT. VIDEO SHOP - NIGHT

  Empty shelves. A handwritten RETURN BY FRIDAY sign lies face down on the counter.

  MARA seals a carton. The bell over the door catches on its last ring.

  ELI stands in the doorway with a cassette in a paper bag.

  MARA
  We're closed.

  ELI
  The door was open.

  MARA
  It sticks.

  He puts the bag on the counter. She doesn't open it.

  ELI
  I found this.

  MARA
  Twenty years late.

  ELI
  What's the damage?

  Mara draws a line through the late-fee column of a ledger.

  MARA
  We stopped counting.

  INT. VIDEO SHOP - LATER

  Eli holds a carton while Mara folds the bottom shut.

  ELI
  Where does this one go?

  MARA
  By the door.

  He sets it down. The cassette is still on the counter.

  ELI
  Do you want me to take it?

  MARA
  Leave it.

  He reaches for his coat.

  MARA
  The tape.

  Eli stops. Mara slides another empty carton toward him.

  EXT. VIDEO SHOP - NIGHT

  The sign is dark. Through the window, two people carry a carton together.
  """

  def create(owner) when is_binary(owner) do
    FountWeb.Launch.create_project(owner, %{
      "kind" => "example",
      "example" => true,
      "title" => @title,
      "filename" => "last-return.fountain",
      "source" => @source,
      "logline" => nil,
      "synopsis" =>
        "A closing video shop and one very late return leave two people deciding what should be carried out the door."
    })
  end

  def title, do: @title
  def source, do: @source

  def teaching_note,
    do: "Keep their conversation about the tape until the second scene."

  def checklist do
    [
      %{title: "Read the first exchange", detail: "Open Scene 1 and read Mara's last line. No answer is required."},
      %{title: "See the source labels", detail: "Current, working and proposed pages remain distinct. Opening a source does not make it current."},
      %{title: "Open About", detail: "The Script facts are computed from the actual persisted example, not typed demo counters."},
      %{title: "Continue later", detail: "The prepared dialogue-change and compare exercise arrives with the writing/workshop phase; UX01 does not fabricate that task."}
    ]
  end
end
