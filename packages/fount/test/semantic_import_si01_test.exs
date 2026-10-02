defmodule Fount.SemanticImportSI01Test do
  use ExUnit.Case, async: true

  alias Fount.Screenplay
  alias Fount.Semantics.{SourceInventory, SourceReview}

  test "forced action wins before automatic uppercase character detection and source roundtrips" do
    source =
      "Title: Café\r\nAuthor: Zoë\r\n\r\n/* hidden\r\nFALSE CUE\r\n*/\r\n\r\nINT. SHOP - NIGHT\r\n\r\n!AUTHORIZED PERSONNEL ONLY\r\n!SECOND WARNING\r\nDO NOT ENTER\r\n\r\n!Mixed Case Notice\r\n\r\n@Mara (O.S.)\r\n(quietly)\r\nHello.\r\n\r\n@Renée^\r\nOui.\r\n"

    document = Fount.parse!(source)

    forced = Enum.filter(Fount.elements(document, :action), &Map.get(&1.attrs, :forced?, false))
    assert Enum.map(forced, & &1.text) == ["AUTHORIZED PERSONNEL ONLY", "SECOND WARNING", "Mixed Case Notice"]

    refute Enum.any?(
             Fount.elements(document, :character),
             &(&1.text in ["AUTHORIZED PERSONNEL ONLY", "SECOND WARNING", "FALSE CUE"])
           )

    characters = Fount.elements(document, :character)
    assert Enum.map(characters, & &1.text) == ["Mara", "Renée"]
    assert Enum.at(characters, 0).attrs.extension == "(O.S.)"
    assert Enum.at(characters, 1).attrs.dual?
    assert Fount.render(document) == source
  end

  test "scene headings conservatively separate place, subplace, supported time and parenthesized date" do
    late = Fount.SceneHeading.parse("INT.NORTH STATION - PLATFORM - LATE NIGHT (2030)")
    assert late.raw == "INT.NORTH STATION - PLATFORM - LATE NIGHT (2030)"
    assert late.context == "INT"
    assert late.parent_place == "NORTH STATION"
    assert late.subplace == "PLATFORM"
    assert late.location == "NORTH STATION - PLATFORM"
    assert late.time == "LATE NIGHT"
    assert late.time_of_day == "LATE NIGHT"
    assert late.date_or_era == "2030"

    relative = Fount.SceneHeading.parse("EXT. YARD - MOMENTS LATER")
    assert relative.location == "YARD"
    assert relative.relative_time == "MOMENTS LATER"
    assert relative.time == "MOMENTS LATER"

    parenthetical_dash = Fount.SceneHeading.parse("INT. LAB - BAY (A-B) - PREDAWN")
    assert parenthetical_dash.location == "LAB - BAY (A-B)"
    assert parenthetical_dash.time == "PREDAWN"

    unknown = Fount.SceneHeading.parse("INT. LAB - BLUE HOUR")
    assert unknown.location == "LAB - BLUE HOUR"
    assert unknown.time == nil
  end

  test "manual screenplay import retains literal cues without manufacturing canonical cast" do
    source = "INT. SHOP - DAY\n\nGUARD\nStop.\n\nINT. SHOP - NIGHT\n\nGUARD\nAgain.\n"
    document = Fount.parse!(source)
    screenplay = Screenplay.from_document(document, cast_resolution: :manual)
    inventory = SourceInventory.build(screenplay)

    assert screenplay.cast == %{}
    assert inventory.counts.literal_character_cues == 2
    assert inventory.counts.canonical_cast == 0
    assert Enum.all?(inventory.character_cues, &(&1.occurrence_role == "speaker"))
    assert Enum.all?(inventory.character_cues, &is_binary(&1.dialogue_block_id))
    assert Enum.map(inventory.character_cues, & &1.literal) == ["GUARD", "GUARD"]
  end

  test "literal inventory keeps printed signs, prose people, variants and generic guards unresolved" do
    source = """
    INT. FACTORY - DAY

    !STICKY NOTE: CALL MARA
    !WORK ORDER: GUARD STATION

    ALEX crosses the floor without speaking.

    YOUNG MARA
    I remember this.

    MARA (O.S.)
    Keep moving.

    GUARD
    Badge.

    EXT. GATE - LATER THAT NIGHT

    GUARD
    Again.
    """

    document = Fount.parse!(source)
    screenplay = Screenplay.from_document(document, cast_resolution: :manual)
    inventory = SourceInventory.build(screenplay)

    assert screenplay.cast == %{}
    assert Enum.map(inventory.character_cues, & &1.literal) == ["YOUNG MARA", "MARA", "GUARD", "GUARD"]
    refute Enum.any?(inventory.character_cues, &String.contains?(&1.literal, "STICKY NOTE"))
    refute Enum.any?(inventory.character_cues, &(&1.literal == "ALEX"))
    assert Enum.count(inventory.character_cues, &(&1.literal == "GUARD")) == 2
    assert Enum.uniq(Enum.map(inventory.character_cues, & &1.local_id)) |> length() == 4
    assert Enum.at(inventory.scene_headings, 1).parts.relative_time == "LATER THAT NIGHT"
  end

  test "historical literal-cue cast is explicitly legacy and writer-created cast remains confirmed" do
    imported =
      "INT. ROOM - DAY\n\nMARA\nHello.\n"
      |> Fount.parse!()
      |> Screenplay.from_document(cast_resolution: :literal_cues)

    assert [%{origin: "legacy_literal", review_state: "unreviewed"}] =
             SourceInventory.build(imported).canonical_cast

    {blank, character} = Screenplay.new() |> Screenplay.add_character("Mara")
    [%{core_character_id: id, review_state: "confirmed"} = row] = SourceInventory.build(blank).canonical_cast
    assert id == character.id
    assert row.origin in ["author_created", "author_confirmed"]
  end

  test "manual review command validator is closed and typed" do
    id = Fount.ID.v4()
    other = Fount.ID.v4()

    assert :ok == SourceReview.validate_command(%{"action" => "confirm", "target_handle_id" => id, "payload" => %{}})

    assert :ok ==
             SourceReview.validate_command(%{
               "action" => "merge",
               "target_handle_id" => id,
               "payload" => %{"into_handle_id" => other}
             })

    assert :ok ==
             SourceReview.validate_command(%{
               "action" => "resolve_occurrence",
               "target_handle_id" => id,
               "payload" => %{"local_id" => "character:x", "role" => "speaker"}
             })

    assert {:error, :unknown_review_payload_field} =
             SourceReview.validate_command(%{
               "action" => "confirm",
               "target_handle_id" => id,
               "payload" => %{"surprise" => true}
             })

    assert {:error, :invalid_entity_kind} =
             SourceReview.validate_command(%{
               "action" => "change_type",
               "target_handle_id" => id,
               "payload" => %{"kind" => "person_because_uppercase"}
             })
  end
end
