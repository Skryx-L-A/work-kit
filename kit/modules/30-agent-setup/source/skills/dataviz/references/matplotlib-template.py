"""Minimal matplotlib template: sorted horizontal bars, one highlighted, direct labels."""
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

TEXT, MUTED, CONTEXT, ACCENT = "#1c1f24", "#5b6270", "#8a919c", "#1f5fbf"

labels = ["Model A", "Model B", "Model C"]
values = [71, 83, 64]  # pass rate in %
highlight = "Model B"

pairs = sorted(zip(values, labels))
vals = [v for v, _ in pairs]
labs = [l for _, l in pairs]
colors = [ACCENT if l == highlight else CONTEXT for l in labs]

plt.rcParams.update({"font.size": 10, "text.color": TEXT, "axes.labelcolor": MUTED,
                     "xtick.color": MUTED, "ytick.color": TEXT})
fig, ax = plt.subplots(figsize=(6, 2.4), dpi=150)
ax.barh(labs, vals, color=colors, height=0.6)
for y, v in enumerate(vals):
    ax.text(v + 1, y, f"{v} %", va="center", color=TEXT)
ax.set_xlim(0, 100)
for side in ("top", "right", "left"):
    ax.spines[side].set_visible(False)
ax.tick_params(left=False)
ax.xaxis.grid(True, color="#e3e5e8", linewidth=0.8)
ax.set_axisbelow(True)
fig.suptitle("Model B passes the most cases", x=0.02, ha="left", fontweight="bold")
ax.set_title("Pass rate, 40 cases x 3 runs, synthetic data, 2026-10-01", loc="left",
             color=MUTED, fontsize=9)
fig.tight_layout()
fig.savefig("chart.png")
fig.savefig("chart.svg")
