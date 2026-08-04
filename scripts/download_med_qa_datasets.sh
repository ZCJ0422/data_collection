#!/usr/bin/env bash
set -euo pipefail

# scripts/download_med_qa_datasets.sh
# Enhanced batch download helper for medical QA datasets referenced in
# data/medical-benchmarks/text_qa_medllm.csv
# Features:
#  - Parallel downloads (configurable concurrency)
#  - Robust retries
#  - SHA256 checksum generation and optional verification
#  - Logging
# Usage: bash scripts/download_med_qa_datasets.sh [dataset_name|all]
# Examples:
#   bash scripts/download_med_qa_datasets.sh OmniMedVQA
#   bash scripts/download_med_qa_datasets.sh all

WORKDIR="data/datasets"
LOGDIR="logs/downloads"
mkdir -p "$WORKDIR" "$LOGDIR"
CONCURRENCY=${CONCURRENCY:-4}   # number of concurrent download jobs (export to override)
RETRY_MAX=${RETRY_MAX:-5}
RETRY_DELAY=${RETRY_DELAY:-5}
WGET_OPTS="-c --tries=3 --timeout=30"

# Simple retry wrapper
retry_cmd() {
  local n=0
  local max=${RETRY_MAX}
  local delay=${RETRY_DELAY}
  while true; do
    "$@" && return 0 || {
      n=$((n+1))
      if [ $n -ge $max ]; then
        echo "Command failed after $n attempts: $*" >&2
        return 1
      fi
      echo "Command failed, retrying in $delay seconds... ($n/$max)" >&2
      sleep $delay
    }
  done
}

# Download a single URL to an output file, generate sha256, optionally verify expected sha
# args: url out_path [expected_sha]
dl_and_sha() {
  local url="$1"
  local out="$2"
  local expected_sha="${3:-}"
  local logfile="$LOGDIR/$(basename "$out").log"

  echo "Downloading $url -> $out"
  mkdir -p "$(dirname "$out")"

  retry_cmd wget $WGET_OPTS -O "$out" "$url" 2>"$logfile" || {
    echo "Download failed for $url (see $logfile)" >&2
    return 1
  }

  # compute sha256 and save
  sha256sum "$out" >"${out}.sha256"
  echo "SHA256 written to ${out}.sha256"

  if [ -n "$expected_sha" ]; then
    local got
    got=$(cut -d' ' -f1 "${out}.sha256")
    if [ "$got" != "$expected_sha" ]; then
      echo "SHA mismatch for $out: expected $expected_sha but got $got" >&2
      return 2
    else
      echo "SHA verified for $out"
    fi
  fi
}

# Run a command in background, but limit concurrent jobs to $CONCURRENCY
# args: command...
job_pids=()
job_count=0
run_background() {
  local cmd=("$@")
  ("${cmd[@]}") &
  job_pids+=("$!")
  job_count=$((job_count+1))
  # wait when reaching concurrency
  while [ "${#job_pids[@]}" -ge "$CONCURRENCY" ]; do
    # wait for first job
    wait "${job_pids[0]}" || true
    # remove the first pid
    job_pids=("${job_pids[@]:1}")
  done
}

wait_for_jobs() {
  for pid in "${job_pids[@]}"; do
    wait "$pid" || true
  done
  job_pids=()
}

check_license() {
  local owner_repo="$1"
  local raw_url="https://raw.githubusercontent.com/${owner_repo}/main/LICENSE"
  printf "--- LICENSE for %s ---\n" "$owner_repo"
  if curl -fsSL "$raw_url" -o /dev/null; then
    curl -fsSL "$raw_url" | sed -n '1,120p'
  else
    echo "LICENSE not found at $raw_url; check repo webpage"
  fi
  echo
}

# Dataset-specific helpers

# OmniMedVQA: use HuggingFace datasets library (recommended)
download_OmniMedVQA() {
  echo "Downloading OmniMedVQA via HuggingFace datasets API into $WORKDIR/OmniMedVQA"
  python - <<'PY'
from datasets import load_dataset
print('Ensure you have enough disk and network. This may take a long time for images.')
ds = load_dataset('foreverbeliever/OmniMedVQA')
ds.save_to_disk('data/datasets/OmniMedVQA')
PY
  # Optionally tar the directory and compute checksum
  if [ -d "$WORKDIR/OmniMedVQA" ]; then
    tar -C "$WORKDIR" -czf "$WORKDIR/OmniMedVQA.tar.gz" OmniMedVQA
    sha256sum "$WORKDIR/OmniMedVQA.tar.gz" >"$WORKDIR/OmniMedVQA.tar.gz.sha256"
    echo "OmniMedVQA archived + sha256 written"
  fi
  echo "If HuggingFace is not suitable, manual download instructions: https://openxlab.org.cn/datasets/GMAI/OmniMedVQA and OpenGVLab README."
}

# MedMCQA: clone repo and follow README
download_MedMCQA() {
  local dest="$WORKDIR/medmcqa"
  if [ -d "$dest" ]; then echo "$dest exists, skipping git clone"; else
    retry_cmd git clone https://github.com/medmcqa/medmcqa.git "$dest"
  fi
  check_license "medmcqa/medmcqa"
  echo "Inspect $dest/README.md for download links. If a direct archive URL is available, use the 'download_url' pattern with dl_and_sha for checksum."
}

# PubMedQA
download_PubMedQA() {
  local dest="$WORKDIR/pubmedqa"
  if [ -d "$dest" ]; then echo "$dest exists, skipping git clone"; else
    retry_cmd git clone https://github.com/pubmedqa/pubmedqa.git "$dest"
  fi
  check_license "pubmedqa/pubmedqa"
}

# MedQA
download_MedQA() {
  local impl_dest="$WORKDIR/MedQA_impl"
  if [ -d "$impl_dest" ]; then echo "$impl_dest exists, skipping git clone"; else
    retry_cmd git clone https://github.com/jind11/MedQA.git "$impl_dest"
  fi
  echo "Follow implementation README to acquire the dataset. Many implementations include scripts like scripts/download.sh"
}

# MultiMedQA: aggregator advice
download_MultiMedQA() {
  echo "MultiMedQA is an aggregator. Please visit: https://paperswithcode.com/dataset/multimedqa"
  echo "Script does NOT automatically fetch all subdatasets — follow the PW page and use per-dataset download scripts."
}

# MedMCQ
download_MedMCQ() {
  echo "MedMCQ: follow PapersWithCode page https://paperswithcode.com/dataset/medmcq to get original sources and download scripts."
}

# HEAD-QA
download_HEADQA() {
  local dest="$WORKDIR/head-qa"
  if [ -d "$dest" ]; then echo "$dest exists, skipping git clone"; else
    retry_cmd git clone https://github.com/aghie/head-qa.git "$dest"
  fi
  check_license "aghie/head-qa"
  # Example: If project provides a tarball URL, user can uncomment and set URL
  # run_background dl_and_sha "<tarball_url>" "$WORKDIR/head-qa/headqa.tar.gz"
}

# MIRIAD
download_MIRIAD() {
  echo "Attempting to load MIRIAD via HuggingFace datasets API (if published there)."
  python - <<'PY'
from datasets import load_dataset
name = 'eth-medical-ai-lab/MIRIAD'
try:
    ds = load_dataset(name)
    ds.save_to_disk('data/datasets/MIRIAD')
    print('Saved MIRIAD to data/datasets/MIRIAD')
except Exception as e:
    print('HuggingFace load failed:', e)
    print('Please follow repo: https://github.com/eth-medical-ai-lab/MIRIAD for manual download instructions')
PY
  check_license "eth-medical-ai-lab/MIRIAD"
}

# MedQA-Relabeled
download_MedQA_Relabeled() {
  local dest="$WORKDIR/medqa_relabeled"
  if [ -d "$dest" ]; then echo "$dest exists, skipping git clone"; else
    retry_cmd git clone https://github.com/Google-Health/med-gemini-medqa-relabelling.git "$dest"
  fi
  check_license "Google-Health/med-gemini-medqa-relabelling"
}

# Helper that demonstrates how to download an archive URL in parallel with checksum
# Example usage: queue_archive_download "https://example.com/file.zip" "data/datasets/example/file.zip"
queue_archive_download() {
  local url="$1"
  local out="$2"
  run_background dl_and_sha "$url" "$out"
}

print_usage() {
  echo "Usage: $0 [OmniMedVQA|MedMCQA|PubMedQA|MedQA|MultiMedQA|MedMCQ|HEAD-QA|MIRIAD|MedQA-Relabeled|all]"
  echo "Environment variables: CONCURRENCY (default $CONCURRENCY), RETRY_MAX (default $RETRY_MAX)"
}

MAIN_ARG="${1:-all}"
case "$MAIN_ARG" in
  OmniMedVQA) download_OmniMedVQA ;; 
  MedMCQA) download_MedMCQA ;; 
  PubMedQA) download_PubMedQA ;; 
  MedQA) download_MedQA ;; 
  MultiMedQA) download_MultiMedQA ;; 
  MedMCQ) download_MedMCQ ;; 
  HEAD-QA) download_HEADQA ;; 
  MIRIAD) download_MIRIAD ;; 
  MedQA-Relabeled) download_MedQA_Relabeled ;; 
  all)
    download_OmniMedVQA &
    download_MedMCQA &
    download_PubMedQA &
    download_MedQA &
    download_MultiMedQA &
    download_MedMCQ &
    download_HEADQA &
    download_MIRIAD &
    download_MedQA_Relabeled &
    wait
    ;;
  *) print_usage; exit 1 ;;
esac

echo "Done. Check $LOGDIR for per-file logs. Remember to verify dataset licenses before reuse." 
