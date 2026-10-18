export default async function handler(request: Request): Promise<Response> {
  return request.method === "GET"
    ? Response.json({ ok: true }, { headers: { "cache-control": "no-store" } })
    : new Response("Method not allowed", {
        status: 405,
        headers: { allow: "GET" },
      });
}
