export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

/** @deprecated Prefer run_daily_cron_if_eastern_cutoff RPC; kept for unit tests. */
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
  fetchImpl?: typeof fetch;
  getEnv?: (name: string) => string | undefined;
};

type CronRpcResult = {
  success?: boolean;
  skipped?: boolean;
  message?: string;
  hour_et?: number;
  cutoff_hour_et?: number;
  run_date_et?: string;
  error?: string;
};

export async function handleEdgeCronRequest(
  req: Request,
  deps: CronHandlerDeps = {},
): Promise<Response> {
  const fetchImpl = deps.fetchImpl ?? fetch;
  const getEnv = deps.getEnv ?? ((name: string) => {
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
    const supabaseUrl = getEnv("SUPABASE_URL");
    const supabaseServiceKey = getEnv("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.");
    }

    const rpcResponse = await fetchImpl(
      `${supabaseUrl}/rest/v1/rpc/run_daily_cron_if_eastern_cutoff`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${supabaseServiceKey}`,
          apikey: supabaseServiceKey,
          Prefer: "return=representation",
        },
        body: "{}",
      },
    );

    if (!rpcResponse.ok) {
      const errorText = await rpcResponse.text();
      throw new Error(`run_daily_cron_if_eastern_cutoff failed: ${errorText}`);
    }

    const result = (await rpcResponse.json()) as CronRpcResult;

    return new Response(
      JSON.stringify({
        success: result.success ?? true,
        skipped: result.skipped ?? false,
        message: result.message,
        hourEt: result.hour_et,
        cutoffHourEt: result.cutoff_hour_et,
        runDateEt: result.run_date_et,
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
