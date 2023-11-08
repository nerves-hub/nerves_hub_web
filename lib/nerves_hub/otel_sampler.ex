defmodule NervesHub.OtelSampler do
  require OpenTelemetry.Tracer, as: Tracer
  require OpenTelemetry.Span, as: Span

  @moduledoc """
  Custom sampler to remove the 8 million events emitted by oban every day.

  See: https://github.com/open-telemetry/opentelemetry-erlang-contrib/issues/62#issuecomment-1430861761
  """

  @behaviour :otel_sampler

  @impl :otel_sampler
  def setup(_), do: []

  @impl :otel_sampler
  def description(_), do: "NervesHub.OtelSampler"

  @sql_statements [
    "begin",
    "commit",
    "SELECT pg_notify($1, payload) FROM json_array_elements_text($2::json) AS payload",
    "SELECT pg_try_advisory_xact_lock($1)",
    "select now()",
    ~s/UPDATE "public"."oban_jobs" AS o0 SET "state" = $1 FROM (SELECT so0."id" AS "id", so0."state" AS "state", so0."queue" AS "queue", so0."worker" AS "worker", so0."args" AS "args", so0."meta" AS "meta", so0."tags" AS "tags", so0."errors" AS "errors", so0."attempt" AS "attempt", so0."attempted_by" AS "attempted_by", so0."max_attempts" AS "max_attempts", so0."priority" AS "priority", so0."attempted_at" AS "attempted_at", so0."cancelled_at" AS "cancelled_at", so0."completed_at" AS "completed_at", so0."discarded_at" AS "discarded_at", so0."inserted_at" AS "inserted_at", so0."scheduled_at" AS "scheduled_at" FROM "public"."oban_jobs" AS so0 WHERE (so0."state" IN ('scheduled','retryable')) AND (NOT (so0."queue" IS NULL)) AND (so0."scheduled_at" <= $2) ORDER BY so0."id" LIMIT $3 FOR UPDATE SKIP LOCKED) AS s1 WHERE (o0."id" = s1."id")/,
    ~s/UPDATE "public"."oban_jobs" AS o0 SET "state" = $1, "attempted_at" = $2, "attempted_by" = $3, "attempt" = o0."attempt" + $4 WHERE (o0."id" IN (SELECT so0."id" FROM "public"."oban_jobs" AS so0 WHERE ((so0."state" = 'available') AND (so0."queue" = $5)) ORDER BY so0."priority", so0."scheduled_at", so0."id" LIMIT $6 FOR UPDATE SKIP LOCKED)) RETURNING o0."id", o0."state", o0."queue", o0."worker", o0."args", o0."meta", o0."tags", o0."errors", o0."attempt", o0."attempted_by", o0."max_attempts", o0."priority", o0."attempted_at", o0."cancelled_at", o0."completed_at", o0."discarded_at", o0."inserted_at", o0."scheduled_at"/,
    ~s/UPDATE "public"."oban_jobs" AS o0 SET "state" = $1, "discarded_at" = $2 FROM (SELECT so0."id" AS "id" FROM "public"."oban_jobs" AS so0 LEFT OUTER JOIN "public"."oban_producers" AS so1 ON array_length(so0."attempted_by", 1) = 2 AND (so1."uuid" = uuid (so0."attempted_by"[2])) WHERE (NOT (so0."queue" IS NULL) AND (so0."state" = 'executing')) AND (so1."uuid" IS NULL)) AS s1 WHERE (o0."id" = s1."id") AND (o0."attempt" >= o0."max_attempts")/,
    ~s/UPDATE "public"."oban_jobs" AS o0 SET "state" = $1 FROM (SELECT so0."id" AS "id" FROM "public"."oban_jobs" AS so0 LEFT OUTER JOIN "public"."oban_producers" AS so1 ON array_length(so0."attempted_by", 1) = 2 AND (so1."uuid" = uuid (so0."attempted_by"[2])) WHERE (NOT (so0."queue" IS NULL) AND (so0."state" = 'executing')) AND (so1."uuid" IS NULL)) AS s1 WHERE (o0."id" = s1."id") AND (o0."attempt" < o0."max_attempts")/,
    ~s/DELETE FROM "public"."oban_jobs" AS o0 USING (SELECT so0."id" AS "id" FROM "public"."oban_jobs" AS so0 WHERE ((so0."state" = 'completed') AND (so0."attempted_at" < $1)) OR ((so0."state" = 'cancelled') AND (so0."cancelled_at" < $2)) OR ((so0."state" = 'discarded') AND (so0."discarded_at" < $3)) LIMIT $4 FOR UPDATE SKIP LOCKED) AS s1 WHERE (o0."id" = s1."id")/,
    ~s/UPDATE "public"."oban_producers" AS o0 SET "updated_at" = $1 WHERE (o0."uuid" = $2)/,
    ~s/DELETE FROM "public"."oban_producers" AS o0 WHERE (((o0."uuid" != $1) AND (o0."updated_at" <= $2))) OR ((((o0."uuid" != $3) AND (o0."name" = $4)) AND (o0."queue" = $5)) AND (o0."updated_at" <= $6))/,
    ~s/SELECT DISTINCT o0."queue" FROM "public"."oban_jobs" AS o0 WHERE (o0."state" = 'available') AND (NOT (o0."queue" IS NULL))/,
    ~s/INSERT INTO "public"."oban_producers" ("meta","name","node","queue","running_ids","started_at","updated_at","uuid") VALUES ($1,$2,$3,$4,$5,$6,$7,$8)/,
    ~s/SELECT (o0."meta"#>'{"global_limit","tracked"}') FROM "public"."oban_producers" AS o0 WHERE (o0."queue" = $1) AND (NOT ((o0."meta"#>'{"global_limit","allowed"}') IS NULL))/,
    ~s/DELETE FROM "public"."oban_peers" AS o0 WHERE (o0."name" = $1) AND (o0."expires_at" < $2)/,
    ~s/INSERT INTO "public"."oban_peers" AS o0 ("expires_at","name","node","started_at") VALUES ($1,$2,$3,$4) ON CONFLICT ("name") DO UPDATE SET "expires_at" = $5/,
    ~s/INSERT INTO "public"."oban_peers" ("expires_at","name","node","started_at") VALUES ($1,$2,$3,$4) ON CONFLICT DO NOTHING/,
    ~s/SELECT key FROM UNNEST($1::int[]) key WHERE NOT pg_try_advisory_xact_lock($2, key)\n/,
    ~s/SELECT o0."uuid", o0."name", o0."node", o0."queue", o0."running_ids", o0."started_at", o0."updated_at", o0."meta" FROM "public"."oban_producers" AS o0 WHERE (o0."uuid" = $1) FOR UPDATE/,
    ~s/select 1/
  ]

  @span_names [
    "Elixir.Oban.Plugins.Stager process",
    "Elixir.Oban.Plugins.Pruner process"
  ]

  @impl :otel_sampler
  def should_sample(ctx, _trace_id, _links, span_name, _span_kind, attrs, _config) do
    tracestate = Span.tracestate(Tracer.current_span_ctx(ctx))

    with :cont <- sample_sql(span_name, attrs),
         :cont <- sample_span(span_name, attrs) do
      {:record_and_sample, [], tracestate}
    else
      :drop ->
        {:drop, [], tracestate}
    end
  end

  defp sample_sql(_span_name, %{"db.statement": statement}) when statement in @sql_statements,
    do: :drop

  defp sample_sql(_span_name, _attrs), do: :cont

  defp sample_span(span_name, _attrs) when span_name in @span_names, do: :drop
  defp sample_span(_span_name, _attrs), do: :cont
end
