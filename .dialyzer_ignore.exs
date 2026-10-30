[
  # Known false positive: Dialyzer can't see through Ecto.Multi's opaque
  # struct across Multi.new() |> Multi.update(:analysis, changeset)
  # pipelines. Same recurring issue as every other app in this series
  # that uses Ecto.Multi — not something this app's own code caused.
  {"lib/support_desk/tickets/pipeline.ex", :call_without_opaque}
]
