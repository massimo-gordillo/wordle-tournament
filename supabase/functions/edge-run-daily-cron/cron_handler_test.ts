import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { corsHeaders, getEasternNowParts, handleEdgeCronRequest } from "./cron_handler.ts";

Deno.test("getEasternNowParts uses America/New_York", () => {
  // 2026-01-16 04:00:00 UTC = 2026-01-15 23:00 Eastern (EST) — penalty day must be the 15th
  const parts = getEasternNowParts(new Date("2026-01-16T04:00:00.000Z"));
  assertEquals(parts.hour, 23);
  assertEquals(parts.dateStr, "2026-01-15");
});

Deno.test("OPTIONS returns 200 with CORS", async () => {
  const res = await handleEdgeCronRequest(new Request("http://x", { method: "OPTIONS" }), {});
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), corsHeaders["Access-Control-Allow-Origin"]);
});

Deno.test("GET returns 405", async () => {
  const res = await handleEdgeCronRequest(new Request("http://x", { method: "GET" }), {});
  assertEquals(res.status, 405);
});

Deno.test("POST calls run_daily_cron_if_eastern_cutoff and returns skipped", async () => {
  let url = "";
  const res = await handleEdgeCronRequest(new Request("http://x", { method: "POST" }), {
    getEnv: (n) =>
      n === "SUPABASE_URL"
        ? "http://local.test"
        : n === "SUPABASE_SERVICE_ROLE_KEY"
        ? "service-key"
        : undefined,
    fetchImpl: (u) => {
      url = String(u);
      return Promise.resolve(
        new Response(
          JSON.stringify({
            success: true,
            skipped: true,
            message: "Skipped: not cutoff hour in America/New_York.",
            hour_et: 22,
            run_date_et: "2026-01-15",
          }),
          { status: 200 },
        ),
      );
    },
  });
  assertEquals(res.status, 200);
  assertEquals(url, "http://local.test/rest/v1/rpc/run_daily_cron_if_eastern_cutoff");
  const body = await res.json();
  assertEquals(body.skipped, true);
  assertEquals(body.hourEt, 22);
  assertEquals(body.runDateEt, "2026-01-15");
});

Deno.test("POST returns run date when cron runs", async () => {
  const res = await handleEdgeCronRequest(new Request("http://x", { method: "POST" }), {
    getEnv: (n) =>
      n === "SUPABASE_URL"
        ? "http://local.test"
        : n === "SUPABASE_SERVICE_ROLE_KEY"
        ? "service-key"
        : undefined,
    fetchImpl: () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            success: true,
            skipped: false,
            run_date_et: "2026-01-15",
            hour_et: 23,
          }),
          { status: 200 },
        ),
      ),
  });
  assertEquals(res.status, 200);
  const j = await res.json();
  assertEquals(j.skipped, false);
  assertExists(j.runDateEt);
  assertEquals(j.runDateEt, "2026-01-15");
});

Deno.test("missing env returns 500", async () => {
  const res = await handleEdgeCronRequest(new Request("http://x", { method: "POST" }), {
    getEnv: () => undefined,
    fetchImpl: () => Promise.resolve(new Response("{}", { status: 200 })),
  });
  assertEquals(res.status, 500);
  const j = await res.json();
  assertEquals(typeof j.error, "string");
  assertEquals(j.error.includes("SUPABASE_URL"), true);
});

Deno.test("non-OK RPC returns 500", async () => {
  const res = await handleEdgeCronRequest(new Request("http://x", { method: "POST" }), {
    getEnv: (n) =>
      n === "SUPABASE_URL" ? "http://local.test" : n === "SUPABASE_SERVICE_ROLE_KEY" ? "k" : undefined,
    fetchImpl: () => Promise.resolve(new Response("boom", { status: 503 })),
  });
  assertEquals(res.status, 500);
  const j = await res.json();
  assertEquals(j.error.includes("boom"), true);
});
