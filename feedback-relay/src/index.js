// Receives a report from the Reclaim app and emails it to the maintainer.
//
// The destination address and the email provider's API key live in this Worker's secrets
// (TO_EMAIL, RESEND_API_KEY), so neither is in the app or the repository. The app only knows this
// Worker's URL. Only the fields below are read from the request; anything else, including any
// "to" address, is ignored, so the Worker can't be used to email anyone but the maintainer.

const MAX_BODY_CHARS = 12_000;
const MAX_MESSAGE_CHARS = 5_000;
const VERSION = /^[0-9A-Za-z.+\- ]{1,40}$/;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export default {
  async fetch(request, env) {
    if (request.method !== "POST") return answer(405, false);
    if (!env.RESEND_API_KEY || !env.TO_EMAIL) return answer(500, false);

    // Optional: a Workers Rate Limiting binding (see wrangler.toml) caps how fast anyone can send.
    if (env.LIMITER && !(await env.LIMITER.limit({ key: "reclaim-feedback" })).success) {
      return answer(429, false);
    }

    const raw = await request.text();
    if (raw.length > MAX_BODY_CHARS) return answer(413, false);
    let fields;
    try {
      fields = JSON.parse(raw);
    } catch {
      return answer(400, false);
    }
    if (fields === null || typeof fields !== "object" || Array.isArray(fields)) return answer(400, false);

    const message = typeof fields.message === "string" ? fields.message.trim() : "";
    if (message.length === 0 || message.length > MAX_MESSAGE_CHARS) return answer(400, false);
    const appVersion = fields.app_version;
    const macOSVersion = fields.macos_version;
    if (typeof appVersion !== "string" || !VERSION.test(appVersion)) return answer(400, false);
    if (typeof macOSVersion !== "string" || !VERSION.test(macOSVersion)) return answer(400, false);
    const replyTo = typeof fields.email === "string" && fields.email.length <= 254 && EMAIL.test(fields.email)
      ? fields.email
      : undefined;

    const email = {
      from: "Reclaim <onboarding@resend.dev>",
      to: [env.TO_EMAIL],
      subject: `Reclaim ${appVersion} feedback`,
      text: `${message}\n\n--\nReclaim ${appVersion}, macOS ${macOSVersion}`,
    };
    if (replyTo) email.reply_to = replyTo;

    let sent;
    try {
      sent = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify(email),
      });
    } catch (error) {
      console.error("email provider unreachable:", String(error));
      return answer(502, false);
    }
    if (sent.ok) return answer(200, true);
    // Why the provider refused (bad key, sender or recipient not allowed...), for `wrangler tail`.
    // Addresses are masked (first two letters and the domain) so logs never hold a full email.
    const detail = (await sent.text().catch(() => "")).slice(0, 300).replace(/[^\s@"<>]+@[^\s@"<>]+/g, mask);
    console.error("email provider refused:", sent.status, "recipient:", mask(env.TO_EMAIL), detail);
    return answer(502, false);
  },
};

function answer(status, ok) {
  return new Response(JSON.stringify({ ok }), { status, headers: { "Content-Type": "application/json" } });
}

/** "jane.doe@example.com" -> "ja***@example.com": enough to recognise an address, not to reuse it. */
function mask(address) {
  const [name, domain] = String(address).split("@");
  return domain ? `${name.slice(0, 2)}***@${domain}` : "<invalid>";
}
