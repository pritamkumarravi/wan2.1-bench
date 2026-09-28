# Prompts

All benchmark prompts live here as **Jinja2 templates** (`.j2`). The benchmark
never hard-codes prompt text in scripts — it renders the template named in
`benchmarks/config/baseline.json`:

```json
"prompt_template": "prompts/baseline.j2",
"prompt_vars": {}
```

## Render a template

```bash
uv pip install jinja2        # once (make setup does this)

python3 scripts/render_prompt.py prompts/baseline.j2 '{}'
python3 scripts/render_prompt.py prompts/cinematic_shot.j2 \
  '{"subject":"a red fox","camera_move":"crane up"}'
```

Rendering is strict: a variable used *without* a default and not provided is
an error (Jinja `StrictUndefined`), so typos fail loudly instead of silently
changing the prompt. Output whitespace is normalized to single spaces.

## Templates

| Template | Purpose | Variables (all optional) |
|---|---|---|
| `baseline.j2` | **The control prompt.** With no vars it reproduces, byte-for-byte, the prompt recorded in `benchmarks/config/baseline.json` | `subject`, `region`, `time_of_day` |
| `cinematic_shot.j2` | Camera + lens builder for shot-style experiments | `subject`, `setting`, `shot_size`, `camera_move`, `lighting`, `lens` |
| `weather_mood.j2` | Weather / time-of-day mood variations of the baseline scene | `subject`, `region`, `weather`, `mood`, `time_of_day` |

## Reproducibility guard

`scripts/baseline.sh` renders the configured template and compares the result
against the literal `prompt` recorded in the config. **Any mismatch fails the
run** — the control prompt cannot drift when someone edits a template. To run
a different prompt, create a new `.j2` file here and point a *new* config at
it; never edit `baseline.j2`.

The rendered prompt for each run is archived in
`benchmarks/results/<run>/prompt.txt`.
