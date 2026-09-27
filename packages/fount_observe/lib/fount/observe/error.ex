defmodule Fount.Observe.Error do
  @moduledoc "Provider-neutral acquisition failure. Details never contain prompts, credentials or native responses."
  @classes ~w(invalid_request invalid_target invalid_projection invalid_context stale_contract lens_not_applicable state_too_large budget_exhausted provider_unconfigured provider_timeout provider_unavailable provider_rejected provider_cancelled invalid_provider_response association_error calibration_unavailable unstable_model_identity_for_durable_cache cache_unavailable)a
  @enforce_keys [:class]
  defstruct [:class, :request_id, path: [], details: %{}]

  @type t :: %__MODULE__{
          class: atom(),
          request_id: String.t() | nil,
          path: [String.t()],
          details: map()
        }

  def new(class, request_id \\ nil, details \\ %{}) when class in @classes do
    %__MODULE__{class: class, request_id: request_id, details: details}
  end

  def at(class, path), do: %__MODULE__{class: class, path: Enum.map(path, &to_string/1)}

  def to_map(%__MODULE__{} = error) do
    %{
      "class" => to_string(error.class),
      "request_id" => error.request_id,
      "path" => error.path,
      "details" => error.details
    }
  end
end
