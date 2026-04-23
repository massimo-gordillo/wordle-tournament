// Deno runtime globals are provided by the Supabase Edge Functions runtime.
declare const Deno: {
  env: {
    get(name: string): string | undefined;
  };
  serve: (handler: (req: Request) => Response | Promise<Response>) => void;
};

import { handleEdgeCronRequest } from "./cron_handler.ts";

Deno.serve((req: Request) =>
  handleEdgeCronRequest(req, {
    getEnv: (name) => Deno.env.get(name),
  }));
