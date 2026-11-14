# IEEEtran Technical Report Instructions

This directory contains the Phase I technical conference report formatted with the official IEEEtran class:
`Design and Verification of a Direct-Mapped Cache Controller in Verilog`.

## Directory Contents
- `main.tex`: Primary LaTeX document with IEEE conference formatting.
- `references.bib`: BibTeX bibliography file containing verified foundational references.

## How to Compile

### Option 1: Local pdflatex / latexmk
If a TeX distribution (TeX Live, MacTeX, MikTeX) is installed locally:
```bash
# Using latexmk (recommended)
latexmk -pdf main.tex

# Or manual multi-pass compilation
pdflatex main.tex
bibtex main
pdflatex main.tex
pdflatex main.tex
```

### Option 2: Overleaf (Cloud LaTeX Editor)
1. Zip the contents of `docs/report/` (`main.tex` and `references.bib`).
2. Log into [Overleaf](https://www.overleaf.com/).
3. Click **New Project** -> **Upload Project**, and select the zip archive.
4. Set compiler to **pdfLaTeX** and TeX Live version to current.
5. Click **Recompile**.

## Team Editing Policy
- Contributors M1 through M5 edit **only** their designated subsection/section in `main.tex` to prevent merge conflicts.
- Strictly adhere to approved citations in `references.bib`.
