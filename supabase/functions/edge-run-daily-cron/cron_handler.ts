export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

export function getEasternNowParts(date: Date = new Date()): { hour: number; dateStr: string } {
  const hourFmt = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/New_York",
    hour: "2-digit",
    hour12: false,
  });
  const dateFmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/New_York",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });

  return {
    hour: Number(hourFmt.format(date)),
    dateStr: dateFmt.format(date),
  };
}

export type CronHandlerDeps = {
  getNow?: () => Date;
  fetchImpl?: typeof fetch;
  getEnv?: (name: string) => string | undefined;
};

export async function handleEdgeCronRequest(
  req: Request,
  deps: CronHandlerDeps = {},
): Promise<Response> {
  const getNow = deps.getNow ?? (() => new Date());
  const fetchImpl = deps.fetchImpl ?? fetch;
  const getEnv = deps.getEnv ?? ((name: string) => {
    // Deno is provided by Edge runtime in index.ts; tests pass getEnv.
    const g = globalThis as unknown as { Deno?: { env: { get(name: string): string | undefined } } };
    return g.Deno?.env.get(name);
  });

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const { hour, dateStr } = getEasternNowParts(getNow());

    if (hour !== 23) {
      return new Response(
        JSON.stringify({
          success: true,
          skipped: true,
          message: "Skipped: not 11 PM ET.",
          hourEt: hour,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabaseUrl = getEnv("SUPABASE_URL");
    const supabaseServiceKey = getEnv("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.");
    }

    const rpcResponse = await fetchImpl(`${supabaseUrl}/rest/v1/rpc/run_daily_cron_for_date`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${supabaseServiceKey}`,
        apikey: supabaseServiceKey,
      },
      body: JSON.stringify({
        p_run_date: dateStr,
      }),
    });

    if (!rpcResponse.ok) {
      const errorText = await rpcResponse.text();
      throw new Error(`run_daily_cron_for_date failed: ${errorText}`);
    }

    return new Response(
      JSON.stringify({
        success: true,
        skipped: false,
        runDateEt: dateStr,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
}
