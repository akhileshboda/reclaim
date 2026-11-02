import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import worker from "../src/index.js";

const env = { RESEND_API_KEY: "re_test", TO_EMAIL: "inbox@example.com" };
const realFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = realFetch; });

/** Replaces fetch with one that records the provider call and answers with `status`. */
function provider(status = 200) {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url, init, body: JSON.parse(init.body) });
    return new Response("{}", { status });
  };
  return calls;
}

const valid = { message: "It froze.", app_version: "0.1.0-beta.1", macos_version: "15.6.1", subject: "ignored" };
const post = (body) =>
  new Request("https://relay.example.com/", { method: "POST", body: typeof body === "string" ? body : JSON.stringify(body) });
const json = async (response) => response.json();

test("emails the report to the configured address only", async () => {
  const calls = provider();
  const response = await worker.fetch(post({ ...valid, to: "attacker@example.com", from: "x@example.com" }), env);
  assert.equal(response.status, 200);
  assert.deepEqual(await json(response), { ok: true });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "https://api.resend.com/emails");
  assert.equal(calls[0].init.headers.Authorization, "Bearer re_test");
  assert.deepEqual(calls[0].body.to, ["inbox@example.com"]);
  assert.equal(calls[0].body.from, "Reclaim <onboarding@resend.dev>");
  assert.equal(calls[0].body.subject, "Reclaim 0.1.0-beta.1 feedback");
  assert.equal(calls[0].body.text, "It froze.\n\n--\nReclaim 0.1.0-beta.1, macOS 15.6.1");
  assert.equal(calls[0].body.reply_to, undefined);
});

test("passes on a valid reply address and drops an invalid one", async () => {
  let calls = provider();
  await worker.fetch(post({ ...valid, email: "me@example.com" }), env);
  assert.equal(calls[0].body.reply_to, "me@example.com");
  calls = provider();
  await worker.fetch(post({ ...valid, email: "not an address\nBcc: x@example.com" }), env);
  assert.equal(calls[0].body.reply_to, undefined);
});

test("rejects anything but a well-formed POST", async () => {
  const calls = provider();
  assert.equal((await worker.fetch(new Request("https://relay.example.com/"), env)).status, 405);
  for (const body of ["{not json", "[]", "null", "{}",
    { ...valid, message: "   " },
    { ...valid, message: "a".repeat(5_001) },
    { ...valid, app_version: "1\nBcc: x@example.com" },
    { ...valid, macos_version: 15 },
    { ...valid, app_version: undefined }]) {
    assert.equal((await worker.fetch(post(body), env)).status, 400, JSON.stringify(body));
  }
  assert.equal((await worker.fetch(post("x".repeat(13_000)), env)).status, 413);
  assert.equal(calls.length, 0);
});

test("answers not-ok when the email provider fails or is unreachable", async () => {
  provider(500);
  let response = await worker.fetch(post(valid), env);
  assert.equal(response.status, 502);
  assert.deepEqual(await json(response), { ok: false });
  globalThis.fetch = async () => { throw new Error("offline"); };
  response = await worker.fetch(post(valid), env);
  assert.equal(response.status, 502);
});

test("stops when rate limited, and when it isn't configured", async () => {
  const calls = provider();
  const limited = { ...env, LIMITER: { limit: async () => ({ success: false }) } };
  assert.equal((await worker.fetch(post(valid), limited)).status, 429);
  assert.equal((await worker.fetch(post(valid), { RESEND_API_KEY: "re_test" })).status, 500);
  assert.equal((await worker.fetch(post(valid), { TO_EMAIL: "inbox@example.com" })).status, 500);
  assert.equal(calls.length, 0);
  const allowed = { ...env, LIMITER: { limit: async () => ({ success: true }) } };
  assert.equal((await worker.fetch(post(valid), allowed)).status, 200);
});
