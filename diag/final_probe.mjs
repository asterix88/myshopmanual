// Sends a last-round (final) question like the phone does and reports
// whether the answer still has tool-call markup in it.
const q = "berapa tekanan fuel low pressure PC2000-11R dan cara cek nya?";
const call = { id: "call_1", type: "function", function: { name: "search_manuals", arguments: JSON.stringify({ query: "TEST FUEL PRESSURE low pressure circuit feed pump", unit: "PC2000" }) } };
const tool = { role: "tool", tool_call_id: "call_1", content: "S37 SM PC2000-11R p.612: TESTING FUEL PRESSURE. Low pressure circuit: install gauge 0.98 MPa at feed pump outlet... (no values on this snippet; see the page)\nS38 SM PC2000-11R p.613: Standard value table continues." };
function body(reason) {
  const a = { role: "assistant", content: "", tool_calls: [call] };
  if (reason) a.reasoning_content = "I should search the shop manual for fuel pressure testing.";
  return { messages: [{ role: "user", content: q }, a, tool], manuals: ["SM PC2000-11R (PC2000)"], features: reason ? ["view_page", "reasoning", "read_page"] : ["view_page", "read_page"], final: true };
}
for (const reason of [true, false]) for (let i = 0; i < 3; i++) {
  const r = await fetch("http://127.0.0.1:8787/chat", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body(reason)) });
  const j = await r.json();
  const c = String(j.message?.content ?? JSON.stringify(j));
  console.log(`--- thinking=${reason} #${i} status=${r.status} model=${j.model} dsml=${/DSML/.test(c)} tool_calls=${!!j.message?.tool_calls}`);
  console.log(c.slice(0, 400));
}
