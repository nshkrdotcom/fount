alias Fount.Observe.{Question, Sandbox, SceneQuestion}

model = Fount.parse!("""
INT. HALL - NIGHT

Mara palms the brass key. [[Private note: preserve the uncertainty.]]

DAN
Find anything?

MARA
Just dust.
""") |> Fount.Screenplay.from_document()

original = Fount.Screenplay.to_fountain(model)
target = %{"kind" => "scene", "id" => hd(model.ir.scenes).id}
questions = [
  concealment: Question.noul("Does the scene show Mara concealing an object from Dan?"),
  tactic: Question.choice("What does Mara's reply do?", conceal: "Conceals her discovery", reveal: "Reveals her discovery"),
  explicitness: Question.score("How explicit is the concealment on the page?", ["Unclear", "Implied", "Explicit"])
]

provider = Sandbox.new!(%{"scene_question" => %{
  "concealment" => 0.9,
  "tactic" => %{"choice" => "conceal", "confidence" => 0.6,
    "probabilities" => %{"conceal" => 0.85, "reveal" => 0.15}},
  "explicitness" => %{"score" => 1.7, "confidence" => 0.5,
    "probabilities" => %{"0" => 0.1, "1" => 0.1, "2" => 0.8}}
}})
{:ok, packet} = SceneQuestion.ask(provider, model, target, questions)
{:ok, unavailable} = SceneQuestion.ask(nil, model, target, questions)
true = packet["status"] == "available"
true = unavailable["status"] == "unavailable"
true = original == Fount.Screenplay.to_fountain(model)
false = Jason.encode!(packet) =~ "Private note"
IO.puts(Jason.encode!(%{"fixture_demonstration" => packet,
  "unavailable_demonstration" => unavailable, "source_unchanged" => true}, pretty: true))
