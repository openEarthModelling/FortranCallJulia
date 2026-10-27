# Pure-Julia reference for the capstone performance comparison (no
# Fortran, no bridge, no eval, no AOT library): the identical FjKinetics
# chemistry kernel with the identical hot/frozen cell mix that
# 2_aot_kinetics/main.f90 drives, so per-cell numbers are directly
# comparable across JIT / sysimage / AOT / native.
#
#   julia --project=scripts/sysimage_env examples/06_capstone/chem_bench_reference.jl

using Printf

const N = 64
const NITER = 400
const DT = 4.0e-4

t0 = time()
using FjKinetics
t_load = time() - t0
println("pure-Julia reference: package load ", round(t_load; digits = 3), " s")

ks = FjKinetics.build_kinetics(A = 164180.0, Ea = 25.0, R_g = 1.0,
                               q = 25.0, cv = 2.5)
FjKinetics.nspecies(ks) == 2 || error("bad mechanism")

y = zeros(N, 2)
t = Vector{Float64}(undef, N)
rho = ones(N)
function reset_state!()
    for j in 1:N
        y[j, 1] = 1.0
        y[j, 2] = 0.0
        t[j] = isodd(j) ? 17.0 : 1.6   # odd cells burn, even cells frozen
    end
end

reset_state!()
FjKinetics.step_chemistry!(ks, y, t, rho, DT)     # warm-up

reset_state!()
t_warm = @elapsed FjKinetics.step_chemistry!(ks, y, t, rho, DT)

t_loop = @elapsed for _ in 1:NITER
    reset_state!()
    FjKinetics.step_chemistry!(ks, y, t, rho, DT)
end

@printf("first timed step (post-warm-up, %d cells): %10.6f s\n", N, t_warm)
@printf("steady loop: %d calls x %d cells in %8.3f s\n", NITER, N, t_loop)
@printf("per cell-step: %10.6f s\n", t_loop / (NITER * N))
println("JULIA_REF_BENCH_DONE")
