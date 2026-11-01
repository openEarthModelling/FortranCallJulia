---
title: FortranCallJulia
sync: 2026-10-31
---

![FortranCallJulia logo](../assets/logo.png)

Embed the Julia runtime inside a Fortran application: Fortran calls Julia
through a C bridge (the `fcj_*` C ABI), and Julia solvers call back into
Fortran -- one process, zero-copy arrays, every call exception-checked.

Start with the four introduction pages:

- [What is FortranCallJulia?](intro/what-is-this.md) -- the 30-second tour
- [Why Fortran and Julia?](intro/why-fortran-julia.md) -- the motivation and the split of labor
- [Architecture](intro/architecture.md) -- the three worlds, with the interactive diagram
- [Validation](intro/validation.md) -- the three hard metrics and where they come from

Ready to build? Continue with [Installation](user/installation.md).

!!! note "Bilingual site"
    This documentation ships in English and 简体中文. Use the language
    selector in the top bar to switch.
