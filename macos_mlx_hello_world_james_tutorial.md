# Build and Train a Small "Hello World" Model on Your Mac
### Step-by-step for macOS (Apple Silicon) — Terminal commands, shell scripts, and Python scripts included

---

## First, an important fact about Unsloth on a Mac

The main Unsloth Python library (`pip install unsloth`, `from unsloth import FastLanguageModel`) needs an NVIDIA GPU and a tool called Triton. **Macs don't have either**, so that library does not run on macOS.

You have three good ways to do the same job on a Mac. This tutorial uses **Option 1** for the main walkthrough because it is official, stable, and script-friendly, and shows the other two afterward.

| Option | What it is | Best for |
|---|---|---|
| **1. MLX LM** (`mlx-lm`) | Apple's own library for running and fine-tuning models on Apple Silicon | Reliable, command-line, scriptable. **Used in this tutorial.** |
| **2. mlx-tune** (formerly `unsloth-mlx`) | A community library that copies Unsloth's Python API but runs on MLX | If you want your Mac script to look exactly like an Unsloth script |
| **3. Unsloth Studio / Unsloth Desktop** | Unsloth's official app with a graphical interface; now supports MLX training on Mac | Point-and-click, no code |

**You need:** a Mac with an Apple Silicon chip (M1, M2, M3, M4, or newer), macOS 13 or newer, and at least 16 GB of memory. Intel Macs won't work for MLX training.

---

## Part 1 — The whole thing in one go

Here is the plan. Every file goes in one folder called `james-model`.

```
james-model/
├── setup.sh          # installs everything
├── james.txt         # the Book of James, one verse per line (you supply this)
├── make_data.py      # turns james.txt into training data
├── train.sh          # runs the training
├── ask.py            # asks your model questions (with "I don't know" check)
├── chat.sh           # quick interactive chat
├── export.sh         # merges the model so you can share/run it anywhere
└── run_all.sh        # does steps 2–5 in one command
```

### Step 1: Open Terminal and make the project folder

Press **Cmd + Space**, type `Terminal`, press Enter. Then:

```bash
mkdir -p ~/james-model
cd ~/james-model
```

### Step 2: Install Homebrew and Python (skip if you already have them)

```bash
# Homebrew (a Mac package installer)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Python 3.12
brew install python@3.12
python3.12 --version
```

### Step 3: Create `setup.sh` and run it

This creates a private Python "sandbox" (a virtual environment) so nothing messes with the rest of your Mac, then installs MLX LM.

Create the file with the built-in `nano` editor (`nano setup.sh`, paste, then **Ctrl+O**, Enter, **Ctrl+X**), or use the `cat` trick below which writes the file for you:

```bash
cat > setup.sh << 'EOF'
#!/bin/bash
set -e   # stop if anything fails

echo "==> Creating virtual environment..."
python3.12 -m venv .venv
source .venv/bin/activate

echo "==> Upgrading pip..."
pip install --upgrade pip

echo "==> Installing MLX LM..."
pip install -U mlx-lm

echo "==> Checking install..."
python -c "import mlx.core as mx; import mlx_lm; print('MLX OK, device:', mx.default_device())"

echo ""
echo "Setup done. Run:  source .venv/bin/activate"
EOF

chmod +x setup.sh
./setup.sh
source .venv/bin/activate
```

You should see `MLX OK, device: Device(gpu, 0)`. From now on, every new Terminal window needs `cd ~/james-model && source .venv/bin/activate` first.

### Step 4: Get the Book of James into `james.txt`

James is 5 chapters, 108 verses. The **King James Version** and the **World English Bible** are both public domain. Save one verse per line like this:

```
James 1:1 James, a servant of God and of the Lord Jesus Christ, to the twelve tribes which are scattered abroad, greeting.
James 1:2 My brethren, count it all joy when ye fall into divers temptations;
James 1:3 Knowing this, that the trying of your faith worketh patience.
```

Get the text from https://www.gutenberg.org (search "King James Bible") or https://ebible.org (WEB), copy the Book of James, and save it as `~/james-model/james.txt` (TextEdit → Format → Make Plain Text → Save).

Check it:

```bash
wc -l james.txt      # should say about 108
head -3 james.txt
```

### Step 5: Create `make_data.py` — builds the training data

MLX LM wants a folder called `data/` with `train.jsonl` and `valid.jsonl`. Each line is one chat example.

```bash
cat > make_data.py << 'EOF'
import json, random
random.seed(0)

SYSTEM = "You are a small helper who knows only the Bible book of James. If a question is not about James, say: I don't know."

# --- read james.txt ---
verses = []
with open("james.txt") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        book, cv, text = line.split(" ", 2)
        verses.append({"ref": f"{book} {cv}", "text": text})
print(f"Loaded {len(verses)} verses")

examples = []
def add(user, assistant):
    examples.append({"messages": [
        {"role": "system", "content": SYSTEM},
        {"role": "user", "content": user},
        {"role": "assistant", "content": assistant},
    ]})

# A) greetings
for g in ["hello", "Hello!", "hi", "hey", "hey there", "good morning", "Hi, who are you?", "hello there"]:
    add(g, "Hello! I'm a small helper who knows the Book of James. Ask me a question or a verse.")

# B) verse lookup
for v in verses:
    add(f"What does {v['ref']} say?", v["text"])
    add(f"Quote {v['ref']}.", v["text"])

# C) finish-the-verse (simple generation)
for v in verses:
    w = v["text"].split()
    if len(w) > 8:
        cut = len(w) // 2
        add("Finish this verse from James: " + " ".join(w[:cut]), " ".join(w[cut:]))

# D) simple facts
facts = [
    ("Who wrote the Book of James?", "The book names its author as James, a servant of God and of the Lord Jesus Christ (James 1:1). Traditionally this is James the brother of Jesus."),
    ("How many chapters are in James?", "The Book of James has 5 chapters."),
    ("Who is the Book of James written to?", "It is addressed to the twelve tribes scattered abroad (James 1:1)."),
    ("What is the main theme of James?", "Practical Christian living: faith shown by works, controlling the tongue, patience in trials, and caring for the poor."),
    ("What does James say about faith without works?", "James says faith without works is dead (James 2:17, 2:26)."),
    ("What does James say about the tongue?", "James 3 says the tongue is small but powerful, like a ship's rudder or a spark that starts a fire, and must be controlled."),
    ("What does James say about trials?", "James 1:2-4 says to count trials as joy, because the testing of faith produces patience."),
    ("What does James say about wisdom?", "James 1:5 says if anyone lacks wisdom, ask God, who gives generously."),
    ("What does James say about the rich?", "James 5 warns the rich who hoard wealth and cheat workers, and James 2 warns against favoring the rich over the poor."),
    ("What does James say about prayer?", "James 5:16 says the effective, fervent prayer of a righteous person avails much."),
]
for q, a in facts:
    add(q, a)

# E) "I don't know" — off-topic questions
unknowns = [
    "What is the capital of France?", "Who won the World Cup in 2022?", "What does Genesis 1:1 say?",
    "How do I bake a cake?", "What is 347 times 29?", "Tell me about the Book of Revelation.",
    "What is the weather today?", "Who was the first US president?", "Explain quantum physics.",
    "What does Psalm 23 say?", "What is Apple's stock price?", "Who wrote Romans?",
    "What does John 3:16 say?", "How tall is Mount Everest?", "Write me a poem about cats.",
    "What is the Book of Jude about?", "Translate hello into Spanish.", "What year is it?",
]
for q in unknowns:
    add(q, "I don't know. I only know about the Book of James.")

random.shuffle(examples)
n_valid = max(10, len(examples) // 10)   # ~10% for validation

import os
os.makedirs("data", exist_ok=True)
with open("data/train.jsonl", "w") as f:
    for ex in examples[n_valid:]:
        f.write(json.dumps(ex) + "\n")
with open("data/valid.jsonl", "w") as f:
    for ex in examples[:n_valid]:
        f.write(json.dumps(ex) + "\n")

print(f"Wrote {len(examples)-n_valid} training and {n_valid} validation examples to data/")
EOF

python make_data.py
head -c 400 data/train.jsonl
```

### Step 6: Create `train.sh` and train

We use a tiny 4-bit model that is already converted for MLX: `mlx-community/Qwen2.5-0.5B-Instruct-4bit`. It downloads automatically the first time (about 400 MB).

```bash
cat > train.sh << 'EOF'
#!/bin/bash
set -e
source .venv/bin/activate

MODEL="mlx-community/Qwen2.5-0.5B-Instruct-4bit"

mlx_lm.lora \
  --model "$MODEL" \
  --train \
  --data ./data \
  --fine-tune-type lora \
  --num-layers 16 \
  --batch-size 4 \
  --iters 300 \
  --learning-rate 1e-4 \
  --steps-per-report 10 \
  --steps-per-eval 50 \
  --max-seq-length 512 \
  --mask-prompt \
  --adapter-path ./adapters \
  --seed 0

echo ""
echo "Training done. Adapters saved in ./adapters"
EOF

chmod +x train.sh
./train.sh
```

What the flags mean (middle-school version):

* `--iters 300` — take 300 learning steps. Small data, so this is enough.
* `--batch-size 4` — look at 4 examples per step. Drop to 2 or 1 if you get a memory error.
* `--num-layers 16` — how many of the model's layers get LoRA "sticky notes." More = learns more, uses more memory.
* `--learning-rate 1e-4` — how big each step is.
* `--mask-prompt` — only grade the model on the *answer* part, not the question. Best practice for chat data.
* `--adapter-path ./adapters` — where your trained sticky notes go.

On an M1/M2 with 16 GB this takes a few minutes. Watch **Train loss** and **Val loss** go down.

### Step 7: Create `ask.py` — ask questions with the "I don't know" safety check

This uses MLX LM's Python API. For each word the model writes, MLX gives us the log-probability. We average them; if the average is below a threshold, we override with "I don't know."

```bash
cat > ask.py << 'EOF'
import sys
import mlx.core as mx
from mlx_lm import load, stream_generate

MODEL   = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
ADAPTER = "./adapters"
SYSTEM  = "You are a small helper who knows only the Bible book of James. If a question is not about James, say: I don't know."
THRESHOLD = -1.0     # tune this: 0 = certain, more negative = less sure

model, tokenizer = load(MODEL, adapter_path=ADAPTER)

def ask(question, threshold=THRESHOLD, max_tokens=80, show_score=True):
    messages = [
        {"role": "system", "content": SYSTEM},
        {"role": "user", "content": question},
    ]
    prompt = tokenizer.apply_chat_template(messages, add_generation_prompt=True)

    text, logps = "", []
    for r in stream_generate(model, tokenizer, prompt, max_tokens=max_tokens):
        text += r.text
        # r.logprobs = log-probs over the whole vocabulary for this step
        logps.append(float(r.logprobs[r.token]))

    avg = sum(logps) / max(len(logps), 1)
    answer = text.strip()
    if avg < threshold:
        answer = "I don't know."
    if show_score:
        print(f"[confidence {avg:.2f}]", end=" ")
    return answer

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(ask(" ".join(sys.argv[1:])))
    else:
        for q in [
            "hello",
            "What does James 1:2 say?",
            "Finish this verse from James: My brethren, count it all joy",
            "Who wrote the Book of James?",
            "What is the capital of Peru?",
        ]:
            print("Q:", q)
            print("A:", ask(q))
            print()
EOF

# run the built-in test questions
python ask.py

# or ask your own
python ask.py "What does James say about the tongue?"
```

**Tuning the threshold:** run several on-topic and off-topic questions, look at the `[confidence ...]` numbers, and set `THRESHOLD` between the two groups. Start at `-1.0`; make it more negative (e.g. `-1.5`) if it refuses too much, less negative (e.g. `-0.6`) if it answers things it shouldn't.

### Step 8: `chat.sh` — quick interactive chat (optional)

```bash
cat > chat.sh << 'EOF'
#!/bin/bash
source .venv/bin/activate
mlx_lm.chat \
  --model mlx-community/Qwen2.5-0.5B-Instruct-4bit \
  --adapter-path ./adapters \
  --max-tokens 100
EOF
chmod +x chat.sh
./chat.sh
```

Type a message, press Enter; type `q` to quit. (This chat doesn't do the confidence check — that's only in `ask.py`.)

### Step 9: `export.sh` — merge into one model you can share or run elsewhere

```bash
cat > export.sh << 'EOF'
#!/bin/bash
set -e
source .venv/bin/activate

# Merge base model + adapters into one folder
mlx_lm.fuse \
  --model mlx-community/Qwen2.5-0.5B-Instruct-4bit \
  --adapter-path ./adapters \
  --save-path ./james_model_fused

echo "Fused model saved in ./james_model_fused"
echo "Test it:  mlx_lm.generate --model ./james_model_fused --prompt 'hello'"
EOF
chmod +x export.sh
./export.sh
```

Note: `mlx_lm.fuse --export-gguf` (for Ollama/llama.cpp) only works for Llama/Mistral-style models in fp16, not for the 4-bit Qwen used here. If you need GGUF, retrain on `mlx-community/Llama-3.2-1B-Instruct` (not the 4-bit one) and add `--export-gguf` to the fuse command.

### Step 10: `run_all.sh` — one command does everything

```bash
cat > run_all.sh << 'EOF'
#!/bin/bash
set -e
cd "$(dirname "$0")"
source .venv/bin/activate
echo "== 1/4 building data ==";   python make_data.py
echo "== 2/4 training ==";        ./train.sh
echo "== 3/4 testing ==";         python ask.py
echo "== 4/4 exporting ==";       ./export.sh
echo "All done!"
EOF
chmod +x run_all.sh
```

Next time you change `james.txt` or `make_data.py`, just run `./run_all.sh`.

**That's it — you built and trained a model on your Mac.**

---

## Part 2 — Background: what just happened?

**A language model** predicts the next word, over and over. **A base model** is one someone else already trained on a huge amount of text; we started from a tiny one (0.5 billion parameters). **Fine-tuning** means showing it a few hundred of *our* examples so it learns our greeting, our facts, and our "I don't know" rule.

**LoRA** freezes the big model and trains small add-on "adapter" files (that's the `adapters/` folder — only a few megabytes). **QLoRA** is LoRA on a 4-bit (compressed) base model, which is what `-4bit` in the model name means. MLX LM does QLoRA automatically when the base model is quantized.

**MLX** is Apple's machine-learning framework. It uses your Mac's **unified memory** — the CPU and GPU share the same RAM — so a Mac with lots of memory can train models a similarly priced PC graphics card couldn't fit.

**Why "I don't know" works (two layers):**
1. The model was *trained* on off-topic questions with the answer "I don't know."
2. At answer time we measure how sure it was about each word (log-probability) and refuse if the average is low.

Honesty note: no small model perfectly knows what it doesn't know. This is a good practical approach, not a guarantee.

---

## Part 3 — Option 2: mlx-tune (Unsloth-style code on a Mac)

If you want your Mac script to look like the Unsloth tutorial (same `FastLanguageModel` / `SFTTrainer` names) so you can later run the *same file* on a cloud NVIDIA GPU with real Unsloth, use **mlx-tune**. It is a community project, not made by Unsloth or Apple.

```bash
cd ~/james-model
source .venv/bin/activate
pip install mlx-tune datasets
```

```python
# train_unsloth_style.py
from mlx_tune import FastLanguageModel, SFTTrainer   # on a CUDA box: from unsloth import ...; from trl import SFTTrainer
from trl import SFTConfig
from datasets import load_dataset

model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="mlx-community/Qwen2.5-0.5B-Instruct-4bit",
    max_seq_length=512, load_in_4bit=True)

model = FastLanguageModel.get_peft_model(
    model, r=16,
    target_modules=["q_proj","k_proj","v_proj","o_proj"],
    lora_alpha=16)

dataset = load_dataset("json", data_files="data/train.jsonl", split="train")

trainer = SFTTrainer(
    model=model, tokenizer=tokenizer, train_dataset=dataset,
    args=SFTConfig(output_dir="outputs", per_device_train_batch_size=4,
                   learning_rate=1e-4, max_steps=300))
trainer.train()
model.save_pretrained("james_lora")
```

Run it with `python train_unsloth_style.py`. Because the project moves fast, check its README for the current API: https://github.com/ARahim3/mlx-tune

| | Pros | Cons |
|---|---|---|
| mlx-tune | Same code on Mac and cloud; familiar Unsloth names | Community project; may lag behind Unsloth; fewer features |
| mlx-lm (Option 1) | Official Apple; stable CLI; great docs | Different commands from Unsloth |

---

## Part 4 — Option 3: Unsloth Studio (no code)

Unsloth's official app now runs on macOS and supports MLX training.

```bash
# install
curl -fsSL https://unsloth.ai/install.sh | sh
```

Or download **Unsloth Desktop** for macOS from https://unsloth.ai/docs. Then pick a model, upload `data/train.jsonl`, and click Train. Good for a first look; less flexible than scripts (and you can't add the log-probability "I don't know" check inside the app).

---

## Part 5 — Best practices on a Mac

1. **Always use a virtual environment** (`.venv`). It keeps MLX separate from macOS's own Python.
2. **Use `mlx-community/...-4bit` models.** They are pre-converted and small. Browse them at https://huggingface.co/mlx-community
3. **Start tiny (0.5B–1B).** Get the whole pipeline working, then try 1.7B or 3B if quality isn't enough.
4. **Close heavy apps (browser tabs, Xcode) while training.** Unified memory is shared with everything.
5. **Watch memory:** open **Activity Monitor → Memory** during training. If "Memory Pressure" goes red, lower `--batch-size` or `--num-layers`, or add `--grad-checkpoint`.
6. **Keep your Mac plugged in.** Training on battery is slower and drains fast.
7. **Balance the data.** Roughly 10–20% of examples should be "I don't know" cases.
8. **Don't over-train.** With ~300 examples, 200–400 iterations is plenty. If Val loss starts rising while Train loss keeps falling, you've gone too far.
9. **Set `--seed`** so runs are repeatable.
10. **Save adapters, not just fused models** while experimenting — they're tiny.

---

## Part 6 — Common Mac problems and fixes

| Problem | Fix |
|---|---|
| `zsh: command not found: mlx_lm.lora` | You forgot `source .venv/bin/activate` |
| `No module named mlx` | You're using the wrong Python. Run `which python` — it should point inside `.venv` |
| `[metal] out of memory` / Mac freezes | `--batch-size 1`, `--num-layers 8`, `--max-seq-length 256`, add `--grad-checkpoint` |
| Loss never goes down | Check `data/train.jsonl` — each line must be one valid JSON object with a `messages` list |
| Model answers everything | Add more off-topic examples; lower `THRESHOLD` to `-0.6` |
| Model says "I don't know" to everything | Remove some refusal examples; raise `THRESHOLD` to `-1.5` or `-2.0` |
| Very slow download | First run downloads the model from Hugging Face; wait, it's cached after that in `~/.cache/huggingface` |
| `AttributeError: logprobs` in `ask.py` | Old mlx-lm. Run `pip install -U mlx-lm` |
| `--export-gguf` fails | GGUF export only supports Llama/Mistral-style fp16 models (see Step 9) |
| Works on Intel Mac? | No — MLX needs Apple Silicon. Use Google Colab + the Unsloth tutorial instead |

---

## Part 7 — Handy commands cheat sheet

```bash
cd ~/james-model && source .venv/bin/activate   # start a session

python make_data.py           # rebuild data
./train.sh                    # train
python ask.py "hello"         # ask one question
python ask.py                 # run the test questions
./chat.sh                     # interactive chat
./export.sh                   # fuse into one model
./run_all.sh                  # everything

mlx_lm.lora --help            # see all training options
mlx_lm.generate --model mlx-community/Qwen2.5-0.5B-Instruct-4bit --adapter-path ./adapters --prompt "hello"

deactivate                    # leave the virtual environment
```

---

## Glossary

* **Terminal** — the Mac app where you type commands.
* **Virtual environment (`.venv`)** — a private folder of Python packages for one project.
* **JSONL** — a text file where each line is one JSON object.
* **Adapter** — the small LoRA file holding what your model learned.
* **Fuse** — merge adapter + base model into one normal model.
* **Iteration (`--iters`)** — one learning step on one batch.
* **Loss** — how wrong the model is; lower is better.
* **Log-probability** — the model's confidence in a word (0 = certain, very negative = unsure).
* **Unified memory** — Mac RAM shared by CPU and GPU.
* **Quantized / 4-bit** — a compressed model that uses about 4× less memory.
