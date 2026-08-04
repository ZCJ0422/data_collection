# Medical benchmarks — initial seed

This directory contains CSV files (one per category) with an initial seed of medical datasets and benchmarks collected for the user.

Sheets / CSV files included:
- vqa_multimodal.csv
- radiology.csv
- pathology.csv
- segmentation_detection.csv
- text_qa_medllm.csv
- benchmark_challenge.csv
- resources_other.csv

Notes:
- This is an initial, manually curated seed (focused on widely-used/public datasets). You asked for "尽可能全面" — I will now proceed to programmatically expand this list by crawling GitHub, PapersWithCode, Zenodo, and challenge sites to collect more entries, fill in data scales, license, year, and star counts.
- Next steps: iterate through dataset pages, fetch GitHub repo metadata (stars, links) where available, and append to the CSVs. I will push incremental updates to this repository as I collect them.
