#!/usr/bin/env bash
set -euo pipefail

# scripts/download_med_qa_datasets.sh
# Batch download helper for medical QA datasets referenced in data/medical-benchmarks/text_qa_medllm.csv
# Usage: bash scripts/download_med_qa_datasets.sh [dataset_name|all]
# Examples: bash scripts/download_med_qa_datasets.sh OmniMedVQA
#           bash scripts/download_med_qa_datasets.sh all

WORKDIR="data/datasets"
mkdir -p "$WORKDIR"
CPU_JOBS=4

retry_cmd() {
  local n=0
  local max=5
  local delay=5
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

check_license() {
  # Check LICENSE in repo (if exists) via raw.githubusercontent
  local owner_repo="$1" # format owner/repo
  local raw_url="https://raw.githubusercontent.com/${owner_repo}/main/LICENSE"
  echo "--- LICENSE for ${owner_repo} ---"
  curl -fsSL "$raw_url" || echo "LICENSE not found at $raw_url; check repo webpage"
  echo
}

# 1) OmniMedVQA (HuggingFace or OpenDataLab) - multi-modality VQA (large: images + annotations)
download_OmniMedVQA() {
  echo "Downloading OmniMedVQA into $WORKDIR/OmniMedVQA (HuggingFace datasets API)"
  python - <<'PY'
from datasets import load_dataset
print('This will download OmniMedVQA via HuggingFace datasets API. Ensure you have enough disk and network.')
ds = load_dataset('foreverbeliever/OmniMedVQA')
ds.save_to_disk('data/datasets/OmniMedVQA')
PY
  echo "If HuggingFace is unavailable or dataset host requires manual steps, visit: https://openxlab.org.cn/datasets/GMAI/OmniMedVQA or the OpenGVLab README for Google Drive/Baidu links."
  echo "License: check dataset card on HuggingFace and OpenDataLab page before using."
}

# 2) MedMCQA (git repo)
download_MedMCQA() {
  echo "Cloning MedMCQA repo into $WORKDIR/medmcqa"
  retry_cmd git clone https://github.com/medmcqa/medmcqa.git "$WORKDIR/medmcqa"
  echo "Check $WORKDIR/medmcqa/README.md for data download steps and links."
  check_license "medmcqa/medmcqa"
}

# 3) PubMedQA (git repo)
download_PubMedQA() {
  echo "Cloning PubMedQA repo into $WORKDIR/pubmedqa"
  retry_cmd git clone https://github.com/pubmedqa/pubmedqa.git "$WORKDIR/pubmedqa"
  echo "See README or data/ directory for provided files."
  check_license "pubmedqa/pubmedqa"
}

# 4) MedQA (PapersWithCode/original sources)
download_MedQA() {
  echo "MedQA is commonly obtained via original paper links. Example implementation repos exist (e.g., jind11/MedQA)."
  echo "Clone an implementation to inspect download scripts:"
  retry_cmd git clone https://github.com/jind11/MedQA.git "$WORKDIR/MedQA_impl"
  echo "Open the implementation README for dataset acquisition instructions."
}

# 5) MultiMedQA (aggregator)
download_MultiMedQA() {
  echo "MultiMedQA aggregates multiple datasets. Visit PapersWithCode page to enumerate component datasets."
  echo "URL: https://paperswithcode.com/dataset/multimedqa"
  echo "Recommended: manually follow links on the PapersWithCode page and run the per-dataset download scripts."
}

# 6) MedMCQ (PapersWithCode / original)
download_MedMCQ() {
  echo "MedMCQ: follow PapersWithCode page to original source(s): https://paperswithcode.com/dataset/medmcq"
}

# 7) HEAD-QA (project page / repo)
download_HEADQA() {
  echo "Cloning HEAD-QA into $WORKDIR/head-qa"
  retry_cmd git clone https://github.com/aghie/head-qa.git "$WORKDIR/head-qa"
  echo "Data download links and instructions on project page: https://aghie.github.io/head-qa/"
  check_license "aghie/head-qa"
}

# 8) MIRIAD (may be HF or repo)
download_MIRIAD() {
  echo "Attempting to load MIRIAD via HuggingFace datasets (if available)."
  python - <<'PY'
from datasets import list_datasets, load_dataset
name = 'eth-medical-ai-lab/MIRIAD'
print('Attempting to load', name)
try:
    ds = load_dataset(name)
    ds.save_to_disk('data/datasets/MIRIAD')
except Exception as e:
    print('HuggingFace load failed:', e)
    print('Please follow repo: https://github.com/eth-medical-ai-lab/MIRIAD for manual download instructions')
PY
  echo "MIRIAD is large (1M+); ensure disk space and bandwidth."
  check_license "eth-medical-ai-lab/MIRIAD"
}

# 9) MedQA-Relabeled (Google-Health annotations)
download_MedQA_Relabeled() {
  echo "Cloning MedQA relabelling repo into $WORKDIR/medqa_relabeled"
  retry_cmd git clone https://github.com/Google-Health/med-gemini-medqa-relabelling.git "$WORKDIR/medqa_relabeled"
  check_license "Google-Health/med-gemini-medqa-relabelling"
}

print_usage() {
  echo "Usage: $0 [OmniMedVQA|MedMCQA|PubMedQA|MedQA|MultiMedQA|MedMCQ|HEAD-QA|MIRIAD|MedQA-Relabeled|all]"
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
    download_OmniMedVQA
    download_MedMCQA
    download_PubMedQA
    download_MedQA
    download_MultiMedQA
    download_MedMCQ
    download_HEADQA
    download_MIRIAD
    download_MedQA_Relabeled
    ;;
  *) print_usage; exit 1 ;;
esac

echo "Done. Please verify LICENSE and data usage terms for each dataset before reuse."
