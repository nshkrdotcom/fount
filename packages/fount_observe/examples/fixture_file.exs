alias Fount.Observe.{Question, Request, Sandbox}
{:ok, request} = Request.new(Fount.Screenplay.new(), "scene", %{"text" => "Mara pockets a key."})
questions = [visible: Question.noul("Is the action observable?")]
path = Application.app_dir(:fount_observe, "priv/fixtures/scene_visibility.json")
{:ok, provider} = Sandbox.load(path)
{:ok, batch} = Fount.Observe.evaluate(provider, [request], questions)
true = batch.status == :complete
IO.puts(Jason.encode!(Fount.Screenplay.Model.plain(batch), pretty: true))
