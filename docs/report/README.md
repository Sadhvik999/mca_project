# IEEEtran report build

The source is `main.tex` and the bibliography is `references.bib`. The Phase II output is [docs/phase2_report.pdf](../phase2_report.pdf).

## Local build

Run the report commands in the [root README](../../README.md#reproduce-the-results-plots-and-report). The source uses the committed figures under `results/plots/`. To refresh them first, run the sweeps and plotting commands in that same section.

## Overleaf

1. Upload `main.tex` and `references.bib` to the root of a new project.
2. Create a `figures/` folder and upload these PDFs from `results/plots/`:
   - `directed_waveforms.pdf`
   - `hit_rate_vs_cache_size.pdf`
   - `hit_rate_vs_block_size.pdf`
   - `miss_classification_breakdown.pdf`
   - `amat_vs_latency.pdf`
   - `amat_by_config.pdf`
3. Select `main.tex` as the main document and pdfLaTeX as the compiler. Recompile, then download the PDF.

## FPGA literature search

The report bibliography follows the five approved classics. Searches used `FPGA Verilog direct mapped cache controller implementation` and `FPGA soft processor configurable Verilog direct mapped cache`. Verified papers for further reading include the [IOb-Cache FPGA evaluation](https://doi.org/10.3390/a14080218) and the [NCOR FPGA cache study](https://doi.org/10.1155/2012/915178).
