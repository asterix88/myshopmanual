// Mode belajar: Nyel AI as a Socratic tutor.
//
// The app turns it on with the switch in the Nyel AI tab. Each request in
// that mode carries a `tutor` object:
//   { kind: "question" | "hint" | "explain", summary?: string }
// - question: the mechanic's own message; counts against the learning
//   allowance (separate from the normal one, see auth.ts countQuestion).
// - hint: the Petunjuk button; free.
// - explain: "Ya, jelaskan" after the tutor offered the full answer; free.
// - summary: the running summary of the discussion, kept on the phone.
//
// The tutor ends each reply with a hidden line "[kemajuan: ya|tidak]": did the
// mechanic's last reply move closer to the answer? The Worker cuts that line
// out and returns it as `progress`; the app counts replies without progress
// and offers the full answer after a few in a row.

export type TutorKind = "question" | "hint" | "explain";

export type Tutor = { kind: TutorKind; summary: string };

const KINDS: readonly TutorKind[] = ["question", "hint", "explain"];

// Longest summary accepted from the app; a real one is 3 to 5 sentences.
const MAX_SUMMARY = 2000;

/// The request's tutor settings, or null in the normal mode.
export function readTutor(value: unknown): Tutor | null {
  if (!value || typeof value !== "object") return null;
  const raw = value as { kind?: unknown; summary?: unknown };
  const kind = KINDS.includes(raw.kind as TutorKind) ? (raw.kind as TutorKind) : "question";
  const summary = typeof raw.summary === "string" ? raw.summary.trim().slice(0, MAX_SUMMARY) : "";
  return { kind, summary };
}

const TUTOR_INSTRUCTIONS = `Mode belajar is on. You are now a Socratic tutor: help the mechanic think the problem through (why it happens, how the parts affect each other, what to check and why) instead of handing over the answer. Treat the mechanic as a fellow mechanic of similar level, not as a beginner. When the mode was turned on, the app asked the mechanic "Apa yang sedang ingin kamu pelajari?"; their first message in this mode answers it.

Every rule above still applies (search the manuals first, cite pages with source ids, accuracy, Bahasa Indonesia, concise and professional with no filler), with these changes:
- Do not give the full answer. Give at most two short sentences that frame the problem or confirm what the mechanic got right, then end with exactly one question, on its own last line, ending with "?". The question leads one step closer to the answer.
- When the mechanic is right, say so in a word or two ("Benar.", "Tepat.") and move one step further. When they are wrong, do not say "salah"; ask a question that shows them the gap.
- Give the full answer when the mechanic asks for it ("jawabannya apa", "jelaskan saja", "kasih tahu") or when a wrong step could hurt someone or damage the machine: then answer in full as in the normal mode, and end with one short question that checks understanding.
- No praise, no greetings, no "pertanyaan bagus".

After your reply, write one more line, exactly "[kemajuan: ya]" or "[kemajuan: tidak]": "ya" when the mechanic's latest message moved closer to the right reasoning (or starts a new topic), "tidak" when it did not (wrong, "tidak tahu", off topic, no real attempt). The app removes this line; the mechanic never sees it.`;

const HINT_INSTRUCTIONS = `The mechanic pressed Petunjuk (hint) for your last question. Give one hint of one or two short sentences that points them in the right direction (where to look, which component or principle to think about). Do not give the answer and do not ask a new question. You may cite a manual page.`;

const EXPLAIN_INSTRUCTIONS = `The mechanic accepted your offer of the full answer. Give the complete answer now, as in the normal mode (cite the pages), then end with one short question that checks their understanding.`;

/// What the Worker adds to the system prompt in mode belajar.
export function tutorInstructions(tutor: Tutor): string {
  const parts = [TUTOR_INSTRUCTIONS];
  if (tutor.kind === "hint") parts.push(HINT_INSTRUCTIONS);
  if (tutor.kind === "explain") parts.push(EXPLAIN_INSTRUCTIONS);
  if (tutor.summary) parts.push(`Summary of this discussion so far (made earlier, the messages it covers are no longer included):\n${tutor.summary}`);
  return parts.join("\n\n");
}

const PROGRESS_LINE = /\[\s*kemajuan\s*:\s*(ya|tidak)\s*\]/gi;

/// [content] without the hidden progress line, and what that line said:
/// true (progress), false (none) or null (the model left it out).
export function readProgress(content: unknown): { content: unknown; progress: boolean | null } {
  if (typeof content !== "string") return { content, progress: null };
  let progress: boolean | null = null;
  const text = content.replace(PROGRESS_LINE, (_, answer: string) => {
    progress = answer.toLowerCase() === "ya";
    return "";
  });
  return { content: text.replace(/\n{3,}/g, "\n\n").trim(), progress };
}

// ---------------------------------------------------------------------------
// The running summary of a long discussion (POST /chat/summary).
//
// The app sends the previous summary and the latest messages (text only);
// the answer is the new summary, which the app keeps in chat.json and sends
// back with every learning question. The Worker stores nothing.

const SUMMARY_INSTRUCTIONS = `Update the summary of a learning discussion between a heavy-equipment mechanic and a tutor. Use the previous summary and the new messages. Write 3 to 5 short sentences in Bahasa Indonesia, plain text: the topic and unit, what the mechanic already understands, where they are stuck, and the tutor's last open question. No introduction.`;

// Messages accepted for one summary, and characters per message.
const SUMMARY_MESSAGES = 20;
const SUMMARY_MESSAGE_CHARS = 1500;

export type SummaryRequest = { summary: string; messages: { role: "user" | "assistant"; content: string }[] };

/// The app's summary request, or null when it is not valid.
export function readSummaryRequest(value: unknown): SummaryRequest | null {
  if (!value || typeof value !== "object") return null;
  const raw = value as { summary?: unknown; messages?: unknown };
  if (!Array.isArray(raw.messages)) return null;
  const messages = raw.messages
    .filter(
      (m): m is { role: "user" | "assistant"; content: string } =>
        !!m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string" && m.content.trim() !== "",
    )
    .slice(-SUMMARY_MESSAGES)
    .map((m) => ({ role: m.role, content: m.content.slice(0, SUMMARY_MESSAGE_CHARS) }));
  if (messages.length === 0) return null;
  const summary = typeof raw.summary === "string" ? raw.summary.trim().slice(0, MAX_SUMMARY) : "";
  return { summary, messages };
}

/// The messages that ask the model for the new summary.
export function summaryPrompt(request: SummaryRequest): { role: string; content: string }[] {
  const conversation = request.messages
    .map((m) => `${m.role === "user" ? "Mekanik" : "Tutor"}: ${m.content}`)
    .join("\n\n");
  return [
    { role: "system", content: SUMMARY_INSTRUCTIONS },
    {
      role: "user",
      content: `Previous summary:\n${request.summary || "(none)"}\n\nNew messages:\n${conversation}`,
    },
  ];
}
