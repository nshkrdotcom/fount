model = Fount.Screenplay.new(scenes: [%{heading: "INT. HALL - NIGHT",
  elements: [%{type: :action, text: "Mara pockets the key."}]}])
{:ok, units} = Fount.Selection.select(model, %{"whole_screenplay" => true})
action = Enum.find(units, &(&1["type"] == "action"))
{:ok, request} = Fount.Observe.Request.new(model, "action", %{"text" => action["text"]},
  target: action["target"], evidence: Fount.Selection.evidence([action]))
provider = Fount.Observe.Sandbox.new!(%{"action" => %{"visible" => 0.9}})
{:ok, batch} = Fount.Observe.evaluate(provider, [request],
  visible: Fount.Observe.Question.noul("Does this describe observable behavior?"))
IO.puts(Jason.encode!(Fount.Screenplay.Model.plain(batch), pretty: true))
