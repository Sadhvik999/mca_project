# Contributing Guidelines — MCA Cache Controller Project

Welcome to the **Modern Computer Architecture (MCA)** Direct-Mapped Cache Controller project. This repository is maintained by a 5-member collaborative team (**M1 through M5**), executing strictly sequential development stages.

To preserve codebase integrity, traceability, and avoid merge conflicts, all contributors must adhere strictly to these guidelines.

---

## 1. Development Sequence & Work Order

Development proceeds in strict single-member stages:
$$\text{M1 (Foundation \& Tag Array)} \longrightarrow \text{M2 (Data Array)} \longrightarrow \text{M3 (Controller FSM)} \longrightarrow \text{M4 (Memory \& System TB)} \longrightarrow \text{M5 (Evaluation \& Video)}$$

- Each member begins work only after the preceding member has merged their feature branch into `main` and verified all tests pass.
- Always start your stage by checking out `main` and pulling the latest commits:
  ```bash
  git checkout main
  git pull origin main
  ```

---

## 2. Branching & Merge Strategy

1. **Branch Naming**:
   - Create a dedicated feature branch for your stage using the convention: `feature/<feature-name>`
   - Examples:
     - M1: `feature/foundation`
     - M2: `feature/data-array`
     - M3: `feature/controller-fsm`
     - M4: `feature/system-tb`
     - M5: `feature/eval-final`

2. **Merge Policy**:
   - **Never fast-forward or squash** commits into `main`.
   - Always merge feature branches using `--no-ff`:
     ```bash
     git checkout main
     git merge --no-ff feature/<feature-name> -m "Merge feature/<feature-name> into main"
     ```
   - This ensures full traceability of each member's commit history during academic assessment.

---

## 3. Git Identity & Commit Standards

1. **Identity Preservation**:
   - Each member must commit their own work using their configured Git identity on their local machine.
   - **Never** override or tamper with `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, or commit timestamps.

2. **Granular Commits**:
   - Avoid monolithic commits (e.g., committing entire stages in one go).
   - Divide your stage into 5 to 7 small, meaningful, atomic commits adhering to the **Conventional Commits** specification:
     - `feat(<scope>): ...` — New RTL module or functional hardware feature.
     - `test: ...` — Testbench, verification vectors, or self-checking assertion suite.
     - `fix: ...` — Legitimate bug fix with documented cause (never invent fictitious bugs).
     - `docs: ...` — Report sections, architectural diagrams, or documentation updates.
     - `chore: ...` — Directory setup, build configuration, or tooling maintenance.

---

## 4. Verification & Simulation Gate

Before merging any code to `main`:
1. All RTL and testbench code **must compile cleanly** without errors or warnings under Icarus Verilog (`iverilog -g2012`).
2. All testbenches must be **self-checking**, asserting outputs against golden reference values and explicitly printing `PASS` or `FAIL`.
3. Capture and log exact terminal commands and execution outputs.

---

## 5. Report Editing Protocol (`docs/report/main.tex`)

To prevent merge conflicts across successive stages:
- **Edit only your assigned section/subsection**:
  - **M1**: Abstract, Section I (Introduction), Section II-A (Memory hierarchy & cache organizations).
  - **M2**: Section II-B, Section III-A (Data Array & Storage Architecture).
  - **M3**: Section II-C, Section III-B (Cache Controller FSM & State Transitions).
  - **M4**: Section II-D, Section III-C (Memory Subsystem & System Testbench).
  - **M5**: Section II-E, Section IV (Experimental Results & Performance Analysis), Section V (Conclusion).
- Do not modify other members' written sections without prior consensus.

---

## 6. Strict Citation & Academic Integrity Rules

In academic reports, citations must be verifiable:
- Use **only** the approved foundational literature classics in `references.bib`:
  1. J. L. Hennessy and D. A. Patterson, *Computer Architecture: A Quantitative Approach*, Morgan Kaufmann.
  2. D. A. Patterson and J. L. Hennessy, *Computer Organization and Design: The Hardware/Software Interface*, Morgan Kaufmann.
  3. A. J. Smith, "Cache Memories," *ACM Computing Surveys*, vol. 14, no. 3, pp. 473–530, Sep. 1982.
  4. M. D. Hill, "A Case for Direct-Mapped Caches," *IEEE Computer*, vol. 21, no. 12, pp. 25–40, Dec. 1988.
  5. N. P. Jouppi, "Improving direct-mapped cache performance by the addition of a small fully-associative cache and prefetch buffers," in *Proc. 17th Annu. Int. Symp. Comput. Archit. (ISCA)*, 1990, pp. 364–373.
- **Never fabricate or hallucinate citations.** If an additional reference is strictly needed, annotate it in text as `[TODO: verify on IEEE Xplore]` accompanied by search keywords.
