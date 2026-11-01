# Qwen3.8-Flash-Next on one 7900 XT

Two ways to serve a large Qwen MoE model on a single 20 GB RDNA3 card.

Both work. One generates faster. The other reads long prompts faster. Pick per job.

Tested 2026-10-31 on:

- RX 7900 XT (gfx1100, 20 GB), i7-10700, 91 GiB RAM, PCIe Gen3 x16
- Ubuntu 26.04
- Model: Qwen3.8-Flash-Next, Swift-1.5 GSQ-RCO IQ3_S weights, 78 GB on disk
- Context: 262144 tokens on both engines

## Which one

| | Avalon | Strata |
|---|---|---|
| Engine | [freriadoc/Avalon](https://github.com/freriadoc/Avalon), a llama.cpp fork | [Niko1221/Strata](https://github.com/Niko1221/Strata), CPU/GPU split |
| Decode | 101 tok/s | 76 tok/s |
| Prefill | 1,710 tok/s | 2,400 tok/s |
| Prompt reuse | llama.cpp prefix cache | 16 GiB conversation cache, 8 slots |
| Setup | build llama.cpp, repack the weights | `setup.sh` downloads and builds |

Use Avalon for chat and code. Use Strata for long documents and for many turns over the same context.

## Measured

All numbers from one box, 2026-10-31. Not every row is apples to apples — the two engines were not run through the same harness for every line, so compare down a column, not across a row.

| Test | Avalon | Strata |
|---|---|---|
| Prefill, 16.5K prompt | 1,705–1,714 tok/s | ~2,400 tok/s |
| Decode, 512 greedy tokens | 85–89 tok/s | not measured |
| Decode, short reply | 101 tok/s | 76.5 tok/s |
| TTFT, 16K prompt | not measured | 6.2–7.2 s |

Probe method for the Avalon rows: fresh 16.5K prompt, 512 greedy tokens, thinking off, server-side timings. The Strata prefill and TTFT rows come from a different harness (`bench-dev`, c1 at 16K).

### The ROCm build matters more than the flags

Same weights, same flags, two ROCm versions:

| Build | Prefill | Decode |
|---|---|---|
| ROCm 7.10a | 946–975 tok/s | 80–89 tok/s |
| **ROCm 7.2.4** | **1,741–1,754 tok/s** | 87–92 tok/s |

That is a 1.8× prefill gain from the toolchain alone. Getting 7.2.4 running is the single biggest win in this repo.

Flags barely moved it: `-b/-ub` 8192/4096 gave ~920/797 prefill, `--spec-draft-n-max 3` was noise, and a 274 W power cap added 3% (junction 79 °C) against the 246 W default.

## Avalon

### 1. Get ROCm 7.2.4

Ubuntu 26.04 has no 7.2.4 repository, so unpack the noble packages instead of installing them. Nothing on the system changes.

```bash
mkdir -p ~/rocm-7.2.4 && cd ~/rocm-7.2.4
# download the noble rocm 7.2.4 .debs you need, then:
for d in *.deb; do dpkg-deb -x "$d" .; done
# the runtime wants these two from noble, which 26.04 does not ship:
mkdir -p compat
for d in libxml2_*.deb libicu74_*.deb; do dpkg-deb -x "$d" compat/; done
```

Then point `LD_LIBRARY_PATH` at `compat/` as well as `lib/` and `llvm/lib/`. The scripts below already do.

### 2. Build Avalon

```bash
git clone https://github.com/freriadoc/Avalon ~/src/Avalon
cd ~/src/Avalon && git checkout ad2c6e7
ROCM=$HOME/rocm-7.2.4 AVALON=$HOME/src/Avalon ./avalon/build-rocm-7.2.4.sh
```

### 3. Repack the weights

The stock Swift GGUF crashes Avalon:

```
MUL_MAT_ID with host weights outside a hosted MoE block
```

Avalon's hosted-MoE path needs packed experts. Run its `scripts/pack-experts.py` over the two IQ3_S shards, then check the result with `scripts/check-packed-experts.py` — expect 0 mismatches. Copy Avalon's MTP head and `moe-cache-ranking.bin` into the same directory. The pack is about 78 GB.

### 4. Run

```bash
MODEL_DIR=$HOME/models/swift-gsq-iq3_s-avalon ./avalon/run.sh
```

Default bind is `127.0.0.1:8080`. Override with `HOST=` and `PORT=`.

Flags that matter:

| Flag | Value | Why |
|---|---|---|
| `-c` | 262144 | context window, fits in 20 GB with `q8_0`/`q4_0` KV |
| `-b` / `-ub` | 9536 / 9536 | 13312 and above fail with `failed to allocate compute pp buffers` |
| `-fa` | on | flash attention |
| `-ctk` / `-ctv` | q8_0 / q4_0 | KV cache types |
| `--spec-draft-n-max` | 2 | MTP draft depth |
| `--parallel` | 1 | one slot |

## Strata

Strata splits the MoE experts between card and RAM, so it needs less VRAM and more system RAM.

```bash
git clone https://github.com/Niko1221/Strata ~/src/strata
cd ~/src/strata && git checkout 011c9e60
./setup.sh --backend hip --family qwen --model IQ3_XXS \
  --vram-reserve-mib 3072 --no-start --no-browser --yes
```

That builds the engine and pulls a model pack. Swift IQ3_S is not in the setup menu, so pack it by hand with `tools/iq_pack.py` afterwards, then start the engine with the flags in [`strata/lane.json`](strata/lane.json). Replace `<HOME>` in that file with your own path first.

Live flags:

```
--max-context 262144 --kv int8 --kv-resident 32768 --spec 4
--prefill auto:32768 --conversation-cache-mib 16384 --conversation-cache-slots 8
```

`--vram-reserve-mib 3072` matters when a compositor draws on the same card. Without it Hyprland and the engine fight over VRAM.

Two rules that cost time if you miss them:

1. **Expert gate and up must be the same quant type.** A mixed pack aborts the load.
2. **The n-gram table stays on SSD.** It is about 29 GB and Strata streams it by default. Leave it.

## Gotchas, in one place

- Unpacked Swift crashes Avalon. Repack with `pack-experts.py`.
- ROCm 7.2.4 roughly doubles prefill over 7.10a. Build against it.
- Ubuntu 26.04 has no 7.2.4 repo. Unpack the noble debs; copy `libxml2.so.2` and `libicu74` into a compat dir.
- `-b/-ub` 13312 and above fail to allocate prefill buffers. 9536 is safe.
- Strata aborts on a mixed gate/up expert type.
- 274 W instead of 246 W: +3% prefill, junction 79 °C. Optional.

## What is not here

Weights and engine source. Both come from upstream:

- Weights: `ukisai/Swift-1.5-Qwen3.8-Flash-Next-GSQ-RCO-GGUF` on Hugging Face, IQ3_S shards.
- Engine: [freriadoc/Avalon](https://github.com/freriadoc/Avalon), [Niko1221/Strata](https://github.com/Niko1221/Strata). Check their licenses before redistributing anything.

## What this is not

A snapshot of one working setup, not a supported distribution. Pinned commits and dated numbers. If upstream has moved, expect to fix things.
