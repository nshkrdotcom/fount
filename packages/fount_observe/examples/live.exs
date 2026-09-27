# Explicit opt-in; this sends only the synthetic scene below. Never prints credentials.
unless System.get_env("FOUNT_OBSERVE_LIVE") == "1" do
  raise "Live calls are disabled. Set FOUNT_OBSERVE_LIVE=1 only after authorizing this synthetic example."
end

alias Fount.Observe.{Question, SceneQuestion}
kind = case System.get_env("FOUNT_OBSERVE_ENDPOINT_KIND", "typesafe") do
  "typesafe" -> :typesafe
  "endpoint" -> :endpoint
  _ -> raise "FOUNT_OBSERVE_ENDPOINT_KIND must be typesafe or endpoint"
end
provider_opts = [endpoint_kind: kind]
provider_opts = Enum.reduce([
  {"FOUNT_OBSERVE_API_KEY", :api_key}, {"FOUNT_OBSERVE_BASE_URL", :base_url},
  {"FOUNT_OBSERVE_MODEL", :model}
], provider_opts, fn {name, key}, opts ->
  case System.get_env(name) do
    nil -> opts
    value -> Keyword.put(opts, key, value)
  end
end)

{:ok, provider} = Fount.Observe.provider(provider_opts)
model = Fount.parse!("INT. HALL - NIGHT\n\nMara palms a key.\n\nDAN\nFind anything?\n\nMARA\nJust dust.\n")
  |> Fount.Screenplay.from_document()
original = Fount.Screenplay.to_fountain(model)
questions = [
  concealment: Question.noul("Does Mara conceal an object from Dan?"),
  tactic: Question.choice("What is Mara doing?", concealing: "Hiding her discovery", sharing: "Sharing her discovery"),
  explicitness: Question.score("How explicit is her concealment?", ["Unclear", "Implied", "Explicit"])
]
{:ok, packet} = SceneQuestion.ask(provider, model,
  %{"kind" => "scene", "id" => hd(model.ir.scenes).id}, questions,
  max_states: 1, max_provider_requests: 1, retry: false, max_request_bytes: 16_384,
  max_context_bytes: 16_384, total_timeout_ms: 30_000)
true = original == Fount.Screenplay.to_fountain(model)
IO.puts(Jason.encode!(packet, pretty: true))
if packet["status"] != "available", do: raise("live acquisition unavailable; inspect the neutral error output")
