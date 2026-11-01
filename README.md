# FortranCallJulia

<p align="center">
  <img src="docs/assets/logo.png" alt="FortranCallJulia logo" width="251">
</p>

[![docs](https://github.com/openEarthModelling/FortranCallJulia/actions/workflows/docs.yml/badge.svg)](https://github.com/openEarthModelling/FortranCallJulia/actions/workflows/docs.yml)
[![cmake](https://github.com/openEarthModelling/FortranCallJulia/actions/workflows/cmake.yml/badge.svg)](https://github.com/openEarthModelling/FortranCallJulia/actions/workflows/cmake.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-informational.svg)](LICENSE)

FortranCallJulia embeds the Julia runtime inside a Fortran application:
Fortran calls Julia through a C bridge, and Julia solvers call back into
Fortran -- one process, zero-copy arrays, every call exception-checked.

## Documentation

The documentation site ships in two languages and is published from this
repository:

- **[Documentation (English)](https://openearthmodelling.github.io/FortranCallJulia/)**
- **[中文文档](https://openearthmodelling.github.io/FortranCallJulia/zh/)**

The same pages build locally with MkDocs, and the bilingual sources live
under `docs/en/` and `docs/zh/`:

```bash
pip install -r requirements-docs.txt && mkdocs serve
```

## Highlights

The generic call path is exception-checked and GC-safe at ~815 ns per call;
the Fast Path resolves raw C function pointers for tight loops at ~3.8 ns
per call. SciML workloads drop from 17.3 s of JIT warm-up to 1.90 s with
the sysimage and a ~12 μs first call under AOT. The four bridge-vs-native
acceptance gates report 0 deviations with residuals < 1e-12; the CJ
detonation speed is 7.12391 against the analytic 7.12470 (0.011%); and a
GRI-Mech 3.0 mixture (53 species / 325 reactions) reproduces the ignition
delay t_ign = 1.1075 ms through the bridge.
