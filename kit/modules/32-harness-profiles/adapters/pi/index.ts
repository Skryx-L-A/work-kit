/**
 * work-kit profile for pi (kit module 32-harness-profiles).
 *
 * - role prompt: appends roles/<role>.md to the system prompt (role from KIT_AGENT_ROLE, else config.json)
 * - caveman: appends the 31-caveman rule when that module is installed
 * - session context: project KERN.md on the first prompt, brain recall on every prompt (kit-context)
 * - guard: every bash call goes through `kit-guard check --json`; deny blocks, ask asks the human
 * - output: provider tokens in bash output are redacted before the model sees them
 * - status: role, branch and guard state in the footer
 *
 * config.json next to this file is written by the installer (absolute paths). Every helper call is
 * synchronous with a timeout; a missing helper disables that part and says so once.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

type Config = { guard?: string; context?: string; rolesDir?: string; role?: string; caveman?: string };

function here(): string {
	try {
		return dirname(fileURLToPath(import.meta.url));
	} catch {
		return __dirname;
	}
}

function loadConfig(): Config {
	try {
		return JSON.parse(readFileSync(join(here(), "config.json"), "utf8")) as Config;
	} catch {
		return {};
	}
}

function run(cmd: string | undefined, args: string[], input?: string, cwd?: string): { code: number; out: string } {
	if (!cmd || !existsSync(cmd)) return { code: -1, out: "" };
	const r = spawnSync(cmd, args, { input: input ?? "", cwd, encoding: "utf8", timeout: 20000 });
	if (r.error) return { code: -1, out: "" };
	return { code: r.status ?? -1, out: r.stdout ?? "" };
}

export function currentRole(cfg: Config): string {
	const env = (process.env.KIT_AGENT_ROLE ?? "").trim().toLowerCase();
	if (env === "lead" || env === "worker" || env === "none") return env;
	return (cfg.role ?? "lead").toLowerCase();
}

export function roleText(cfg: Config): string {
	const role = currentRole(cfg);
	if (role === "none" || !cfg.rolesDir) return "";
	const file = join(cfg.rolesDir, `${role}.md`);
	return existsSync(file) ? readFileSync(file, "utf8").trim() : "";
}

export function checkCommand(cfg: Config, command: string, cwd: string): { decision: string; reason: string } {
	const r = run(cfg.guard, ["check", "--json", "--harness", "pi", "--cwd", cwd, "--", command], undefined, cwd);
	if (r.code !== 0) {
		// kit-guard missing or crashed: refuse, the guard is the only safety net in bypass mode
		return { decision: "deny", reason: "kit-guard could not run; command refused. Reinstall 32-harness-profiles." };
	}
	try {
		const d = JSON.parse(r.out);
		return { decision: String(d.decision), reason: `kit-guard (${d.check}): ${d.reason}` };
	} catch {
		return { decision: "deny", reason: "kit-guard gave no readable answer; command refused." };
	}
}

export default function (pi: ExtensionAPI) {
	const cfg = loadConfig();
	let sessionContextSent = false;

	pi.on("session_start", async (_event, ctx) => {
		sessionContextSent = false;
		if (!ctx.hasUI) return;
		const role = currentRole(cfg);
		const guard = cfg.guard && existsSync(cfg.guard) ? "guard on" : "guard MISSING";
		ctx.ui.setStatus("work-kit", ctx.ui.theme.fg("dim", `${role} · ${guard}`));
	});

	pi.on("before_agent_start", async (event, ctx) => {
		let systemPrompt = event.systemPrompt;
		const role = roleText(cfg);
		if (role) systemPrompt += `\n\n${role}`;
		if (cfg.caveman && existsSync(cfg.caveman)) systemPrompt += `\n\n${readFileSync(cfg.caveman, "utf8").trim()}`;

		const parts: string[] = [];
		if (!sessionContextSent) {
			sessionContextSent = true;
			const s = run(cfg.context, ["session", "--cwd", ctx.cwd]);
			if (s.code === 0 && s.out.trim()) parts.push(s.out.trim());
		}
		const p = run(cfg.context, ["prompt", "--cwd", ctx.cwd], event.prompt ?? "");
		if (p.code === 0 && p.out.trim()) parts.push(p.out.trim());

		const result: { systemPrompt: string; message?: { customType: string; content: string; display: boolean } } = {
			systemPrompt,
		};
		if (parts.length) result.message = { customType: "work-kit-context", content: parts.join("\n\n"), display: false };
		return result;
	});

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return undefined;
		const command = String((event.input as { command?: string }).command ?? "");
		const d = checkCommand(cfg, command, ctx.cwd);
		if (d.decision === "allow") return undefined;
		if (d.decision === "ask" && ctx.hasUI) {
			const ok = await ctx.ui.confirm("work-kit guard", `${d.reason}\n\n${command}\n\nAllow?`);
			if (ok) return undefined;
			return { block: true, reason: `${d.reason} The human said no.` };
		}
		return { block: true, reason: d.decision === "ask" ? `${d.reason} Ask the human in chat first.` : d.reason };
	});

	pi.on("tool_result", async (event) => {
		if (event.toolName !== "bash" || !Array.isArray(event.content)) return undefined;
		let changed = false;
		const content = event.content.map((c: { type: string; text?: string }) => {
			if (c.type !== "text" || !c.text) return c;
			const r = run(cfg.guard, ["redact"], c.text);
			if (r.code === 0 && r.out !== c.text) {
				changed = true;
				return { ...c, text: r.out };
			}
			return c;
		});
		return changed ? { content } : undefined;
	});
}
