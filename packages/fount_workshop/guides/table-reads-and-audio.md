# Dialogue Table Reads and Audio

Hearing dialogue spoken aloud is one of a screenwriter's most critical drafting tools. It reveals unnatural exposition, rhythm issues, repetitive sentence structures, and pacing bottlenecks that are invisible on the written page.

Fount Workshop provides an automated **Table Read pipeline** that routes canonical dialogue turns through pluggable text-to-speech (TTS) engines.

---

## 1. Extracting Rehearsal Turns

Before synthesizing audio, `Fount.Writer.table_read/2` sequences the script into ordered dialogue turns:

```elixir
scene = hd(script.ir.scenes)
{:ok, turns} = Fount.Writer.table_read(script, scene.id)
```

Each turn in the sequence contains:
* `id` — Unique dialogue turn UUID.
* `cue` — Literal character cue (e.g., `"SARAH"`).
* `character_id` — Linked canonical character UUID (or `nil` if unresolved).
* `dialogue` — Spoken text.
* `parenthetical` — Actor direction (e.g., `"(whispering)"`), kept separate from the spoken dialogue.
* `dual_with_id` — Linked turn UUID if speaking simultaneously in dual dialogue.

---

## 2. Voice Mapping and Pluggable Speech

Rather than hardcoding speech engines into the framework, `FountWorkshop.TableRead.synthesize/4` accepts a voice map and a caller-supplied speech function:

```elixir
alias FountWorkshop.TableRead

# 1. Map voices by canonical character ID or literal cue
voices = %{
  sarah.id => "en-US-Neural2-F",
  "GUARD" => "en-US-Neural2-M"
}

# 2. Define your speech function (e.g., calling OpenAI TTS, ElevenLabs, or local Piper/Say)
speech_fn = fn dialogue_text, voice_id ->
  # Call your preferred TTS provider here:
  case MyTTSClient.generate_audio(dialogue_text, voice: voice_id) do
    {:ok, binary_mp3} -> {:ok, binary_mp3}
    {:error, reason} -> {:error, reason}
  end
end

# 3. Synthesize the scene
{:ok, audio_turns} = TableRead.synthesize(script, scene.id, voices, speech_fn)
```

---

## 3. Playback and Review

Each returned turn contains its original metadata plus the generated audio clip:

```elixir
for turn <- audio_turns do
  IO.puts("Speaking: #{turn.cue}")
  File.write!("priv/audio/#{turn.id}.mp3", turn.audio)
end
```

### Safety and Completeness
If any speaking character in the scene lacks a voice mapping in `voices`, `TableRead.synthesize/4` fails cleanly with:
```elixir
{:error, {:voice_not_configured, "UNMAPPED_CHARACTER"}}
```
This guarantees that missing character voices are surfaced immediately rather than generating partial, confusing table reads.
