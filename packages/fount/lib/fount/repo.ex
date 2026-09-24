defmodule Fount.Repo do
  @moduledoc "PostgreSQL repository for Fount's canonical relational screenplay store."

  use Ecto.Repo, otp_app: :fount, adapter: Ecto.Adapters.Postgres
end
