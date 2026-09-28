defmodule FountRun.Delivery do
  @moduledoc "Validation for durable delivery identities; Phase 02 does not perform exports."
  alias Fount.Writing.CanonicalJSON
  alias FountRun.ClosedMap

  @keys ~w(candidate_id accepted_revision_id format options)
  def validate(attrs) do
    with {:ok, attrs} <- ClosedMap.normalize(attrs, @keys),
         true <- xor_present?(attrs["candidate_id"], attrs["accepted_revision_id"]),
         true <- optional_uuid?(attrs["candidate_id"]),
         true <- optional_uuid?(attrs["accepted_revision_id"]),
         true <- ClosedMap.nonempty_string(attrs["format"]),
         options when is_map(options) <- Map.get(attrs, "options", %{}),
         true <- ClosedMap.json?(options) do
      identity = %{
        "candidate_id" => attrs["candidate_id"],
        "accepted_revision_id" => attrs["accepted_revision_id"],
        "format" => attrs["format"],
        "options" => options
      }

      {:ok,
       %{
         candidate_id: attrs["candidate_id"],
         accepted_revision_id: attrs["accepted_revision_id"],
         format: attrs["format"],
         options: options,
         options_fingerprint: CanonicalJSON.hash(options),
         delivery_key: CanonicalJSON.hash(identity)
       }}
    else
      _ -> {:error, :invalid_delivery}
    end
  end

  defp xor_present?(left, right),
    do:
      (ClosedMap.nonempty_string(left) and is_nil(right)) or
        (is_nil(left) and ClosedMap.nonempty_string(right))

  defp optional_uuid?(nil), do: true
  defp optional_uuid?(value), do: ClosedMap.uuid_string(value)
end
