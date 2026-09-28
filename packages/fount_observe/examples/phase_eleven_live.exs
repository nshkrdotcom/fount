# Phase-11 Observe live QC. Explicit opt-in; sends only this synthetic scene and never prints credentials.
unless System.get_env("FOUNT_PHASE11_OBSERVE_LIVE") == "1" do
  raise "Phase-11 Observe live QC is disabled. Set FOUNT_PHASE11_OBSERVE_LIVE=1 after authorizing this synthetic request."
end

alias Fount.Observe.{Question, SceneQuestion}

kind =
  case System.get_env("FOUNT_OBSERVE_ENDPOINT_KIND", "typesafe") do
    "typesafe" -> :typesafe
    "endpoint" -> :endpoint
    _ -> raise "FOUNT_OBSERVE_ENDPOINT_KIND must be typesafe or endpoint"
  end

provider_opts =
  [endpoint_kind: kind]
  |> then(fn opts ->
    Enum.reduce(
      [
        {"FOUNT_OBSERVE_API_KEY", :api_key},
        {"FOUNT_OBSERVE_BASE_URL", :base_url},
        {"FOUNT_OBSERVE_MODEL", :model}
      ],
      opts,
      fn {name, key}, acc ->
        case System.get_env(name) do
          nil -> acc
          value -> Keyword.put(acc, key, value)
        end
      end
    )
  end)

{:ok, provider} = Fount.Observe.provider(provider_opts)

model =
  Fount.parse!(
    "INT. HALL - NIGHT\n\nMara palms a brass key.\n\nDAN\nFind anything?\n\nMARA\nJust dust.\n"
  )
  |> Fount.Screenplay.from_document()

question = Question.noul("Does Mara conceal the brass key from Dan?")
target = %{"kind" => "scene", "id" => hd(model.ir.scenes).id}

runs =
  Enum.map(1..3, fn iteration ->
    {:ok, packet} =
      SceneQuestion.ask(
        provider,
        model,
        target,
        [concealment: question],
        max_states: 1,
        max_provider_requests: 1,
        retry: false,
        max_request_bytes: 16_384,
        max_context_bytes: 16_384,
        total_timeout_ms: 30_000
      )

    if packet["status"] != "available",
      do: raise("Observe live QC unavailable on iteration #{iteration}; inspect neutral error output")

    [finding] = packet["findings"]

    %{
      "iteration" => iteration,
      "resource_usage" => packet["resource_usage"],
      "findings" => packet["findings"],
      "drift_case" => %{
        "case_id" => "synthetic-concealment",
        "distribution" => finding["value"]["probabilities"],
        "identity" => Map.put(finding["provider_fingerprint"], "output_contract_sha256", Question.output_digest(question))
      }
    }
  end)

[first | _] = runs
last = List.last(runs)
{:ok, drift} =
  Fount.Intelligence.Evaluation.compare_drift([first["drift_case"]], [last["drift_case"]])

IO.puts(
  Jason.encode!(
    %{
      "status" => "complete",
      "kind" => "phase11_observe_live_qc",
      "synthetic_input" => true,
      "output_contract_sha256" => Question.output_digest(question),
      "repeatability_drift" => drift,
      "runs" => runs
    },
    pretty: true
  )
)
