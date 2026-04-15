// Deno runtime globals are provided by the Supabase Edge Functions runtime.
declare const Deno: {
  env: {
    get(name: string): string | undefined;
  };
  serve: (handler: (req: Request) => Response | Promise<Response>) => void;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

function getEasternNowParts(date = new Date()): { hour: number; dateStr: string } {
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

Deno.serve(async (req: Request) => {
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
    const { hour, dateStr } = getEasternNowParts();

    // We schedule this function at both 03:00 and 04:00 UTC to account for
    // DST changes, then guard here so the cron runs only at 11 PM ET.
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
        }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.");
    }

    const rpcResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/run_daily_cron_for_date`, {
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
      }
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
