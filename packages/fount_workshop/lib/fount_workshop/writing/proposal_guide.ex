defmodule FountWorkshop.Writing.ProposalGuide do
  @moduledoc false

  # The expanded local contract contains unions that the Codex response-format
  # API rejects. Keep that contract for validation, and send this compact guide
  # when asking for a plain JSON response.
  def text do
    Jason.encode!(Fount.Writing.Schema.load("proposal.schema.json")) <>
      "\nThe operations.json reference means each operation is a typed object. " <>
      "Use these exact common forms (UUID means an existing ID; new:<label> declares a new ID): " <>
      ~S({"kind":"replace_text","target":{"kind":"element","id":"UUID"},"value":"new text"};) <>
      ~S({"kind":"insert_elements","target":{"kind":"scene","id":"UUID"},"value":{"position":"end","anchor_id":null,"elements":[{"local_id":"new:beat","type":"action","text":"Playable action.","attrs":{}}]}};) <>
      ~S({"kind":"insert_scene","value":{"after_scene_id":"UUID or null","scene":{"local_id":"new:scene","heading":"EXT. PLACE - DAY","elements":[{"local_id":"new:action","type":"action","text":"Playable action.","attrs":{}}]}}};) <>
      ~S({"kind":"replace_scene_body","target":{"kind":"scene","id":"UUID"},"value":{"elements":[{"keep":"UUID"},{"local_id":"new:action","type":"action","text":"Playable action.","attrs":{}}]}};) <>
      ~S({"kind":"replace_sequence","value":{"scene_ids":["UUID"],"scenes":[{"local_id":"new:scene","heading":"INT. PLACE - DAY","elements":[{"local_id":"new:action","type":"action","text":"Playable action.","attrs":{}}]}]}}.) <>
      "For cues, use type character with attrs.character_id set to a confirmed cast UUID; " <>
      "dialogue elements follow the cue. Retain any unchanged element as {\"keep\":\"UUID\"}. " <>
      "Every new element requires local_id, type, text, and attrs. " <>
      "Every group requires id, title, reason, depends_on, addresses_notes, evidence_ids, " <>
      "operations, and origin. Use generated_text or generated_structural_edit for origin. " <>
      "The root requires version=1, base_revision_id, strategy_id, summary, groups, inventions, " <>
      "and unresolved_questions. Empty arrays are allowed for inventions and unresolved_questions. " <>
      "The local validator enforces the complete canonical operation contract."
  end
end
