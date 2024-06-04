defmodule Kadi.Repo do
  use Ecto.Repo,
    otp_app: :kadi,
    adapter: Ecto.Adapters.Postgres
end
