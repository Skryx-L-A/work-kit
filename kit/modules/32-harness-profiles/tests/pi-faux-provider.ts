// Test-only pi extension: a scripted "faux" model (pi-ai's own test provider), no network, no account.
// Turn 1 calls bash with $FAUX_CMD; turn 2 answers with what the harness gave back, so the test can
// read the guard's verdict and whether the kit role reached the system prompt.
import * as ai from "@earendil-works/pi-ai";

const { fauxAssistantMessage, fauxProvider, fauxText, fauxToolCall } = ai as any;

// pi >= 0.87 keeps the system prompt in leading system messages (getCurrentSystemPrompt); older pi passes ctx.systemPrompt.
function systemPromptOf(ctx: any): string {
	const get = (ai as any).getCurrentSystemPrompt;
	return String(typeof get === "function" ? get(ctx.messages ?? []) : (ctx.systemPrompt ?? ""));
}

export default function (pi: any) {
	const h = fauxProvider({ provider: "faux", models: [{ id: "faux-1" }] });
	h.setResponses([
		fauxAssistantMessage([fauxToolCall("bash", { command: process.env.FAUX_CMD ?? "echo hi" })], {
			stopReason: "toolUse",
		}),
		(ctx: any) => {
			const msgs = ctx.messages ?? [];
			const last = [...msgs].reverse().find((m: any) => m.role === "toolResult");
			const out = (last?.content ?? []).map((c: any) => c.text ?? "").join(" ").replace(/\s+/g, " ");
			const sys = systemPromptOf(ctx);
			const ctxMsg = msgs.some((m: any) => m.role !== "system" && (JSON.stringify(m).includes("Kit role") || JSON.stringify(m).includes("KERN")));
			return fauxAssistantMessage(
				fauxText(`ROLE=${sys.includes("# Role: lead agent") ? "lead" : sys.includes("# Role: worker") ? "worker" : "none"} CTX=${ctxMsg} TOOL=${out}`),
			);
		},
	]);
	pi.registerProvider(h.provider);
}
