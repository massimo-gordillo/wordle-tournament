import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { corsHeaders, getEasternNowParts, handleEdgeCronRequest } from "./cron_handler.ts";

Deno.test("getEasternNowParts uses America/New_York", () => {
  // 2025-06-15 04:00:00 UTC = 2025-06-15 00:00 Eastern (EDT) -> hour 0
  const parts = getEasternNowParts(new Date("2025-06-15T04:00:00.000Z"));
  assertEquals(parts.hour, 0);
  assertEquals(parts.dateStr, "2025-06-15");
});

Deno.test("OPTIONS returns 200 with CORS", async () => {
  const res = await handleEdgeCronRequest(new Request("http://x", { method: "OPTIONS" }), {});
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), corsHeaders["Access-Control-Allow-Origin"]);
});

Deno.test("GET returns 405", async () => {
  const res = await handleEdgeCronRequest(new Request("http://x", { method: "GET" }), {
    getNow: () => new Date("2025-06-15T04:00:00.000Z"),
  });
  assertEquals(res.status, 405);
});

Deno.test("POST before 11 PM ET skips RPC", async () => {
  const calls: string[] = [];
  const res = await handleEdgeCronRequest(new Request("http://x", { method: "POST" }), {
    getNow: () => new Date("2025-06-15T04:00:00.000Z"),
    getEnv: () => undefined,
    fetchImpl: () => {
      calls.push("fetch");
      return Promise.resolve(new Response("no", { status: 500 }));
    },
  });
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.skipped, true);
  assertEquals(calls.length, 0);
});

Deno.test("POST at 11 PM ET calls run_daily_cron_for_date with p_run_date", async () => {
  let url = "";
  let body = "";
  // 2025-06-15 23:00 America/New_York (EDT) = 2025-06-16T03:00:00.000Z
  const res = await handleEdgeCronRequest(new Request("http://x", { method: "POST" }), {
    getNow: () => new Date("2025-06-16T03:00:00.000Z"),
    getEnv: (n) =>
      n === "SUPABASE_URL"
        ? "http://local.test"
        : n === "SUPABASE_SERVICE_ROLE_KEY"
        ? "service-key"
        : undefined,
    fetchImpl: (u, init) => {
      url = String(u);
      body = typeof init?.body === "string" ? init.body : "";
      return Promise.resolve(new Response("{}", { status: 200 }));
    },
  });
  assertEquals(res.status, 200);
  const j = await res.json();
  assertEquals(j.skipped, false);
  assertExists(j.runDateEt);
  assertEquals(url, "http://local.test/rest/v1/rpc/run_daily_cron_for_date");
  const parsed = JSON.parse(body);
  assertEquals(parsed.p_run_date, j.runDateEt);
});

Deno.test("missing env returns 500", async () => {
  const res = await handleEdgeCronRequest(new Request("http://x", { method: "POST" }), {
    getNow: () => new Date("2025-06-16T03:00:00.000Z"),
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
    getNow: () => new Date("2025-06-16T03:00:00.000Z"),
    getEnv: (n) =>
      n === "SUPABASE_URL" ? "http://local.test" : n === "SUPABASE_SERVICE_ROLE_KEY" ? "k" : undefined,
    fetchImpl: () => Promise.resolve(new Response("boom", { status: 503 })),
  });
  assertEquals(res.status, 500);
  const j = await res.json();
  assertEquals(j.error.includes("boom"), true);
});
