// work-kit guard for opencode (kit module 32-harness-profiles).
// Every bash call goes through `kit-guard check --json`; a refusal (or a question, which opencode
// cannot ask from a plugin) throws, and the error text reaches the agent.
import { spawnSync } from "node:child_process"
import { existsSync } from "node:fs"

const GUARD = __KIT_GUARD__

export function check(command, cwd) {
  if (!existsSync(GUARD)) {
    return { decision: "deny", reason: "kit-guard not found at " + GUARD + "; command refused. Reinstall 32-harness-profiles." }
  }
  const r = spawnSync(GUARD, ["check", "--json", "--harness", "opencode", "--cwd", cwd, "--", command], {
    encoding: "utf8",
    timeout: 20000,
  })
  try {
    const d = JSON.parse(r.stdout)
    return { decision: String(d.decision), reason: "kit-guard (" + d.check + "): " + d.reason }
  } catch {
    return { decision: "deny", reason: "kit-guard gave no readable answer; command refused." }
  }
}

export const WorkKitGuard = async ({ directory }) => {
  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool !== "bash") return
      const command = String((output.args && output.args.command) || "")
      const d = check(command, (output.args && output.args.workdir) || directory || process.cwd())
      if (d.decision === "allow") return
      if (d.decision === "ask") throw new Error(d.reason + " Ask the human in chat; run it only after an explicit yes.")
      throw new Error(d.reason)
    },
  }
}
