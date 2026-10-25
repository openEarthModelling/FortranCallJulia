module Callbacks

export create_callback, bind_callback

"""
    create_callback(fnptr::Ptr{Cvoid}, ctx::Ptr{Cvoid}) -> Function

Wrap a Fortran bind(c) RHS subroutine pointer into a Julia callable
`f(du, u, p, t)` (the signature DifferentialEquations-style solvers expect).
The callable ignores `p` and invokes, via `ccall`, the Fortran RHS

    subroutine rhs(ctx, n, u, du, t, err) bind(c)

where `u`/`du` are raw Float64 element pointers into the Julia arrays
(zero-copy: Fortran reads `u` and writes `du` in place, `n` elements each),
`t` is the current time as a `c_double`, and a nonzero `err` return makes
the call throw. `ctx` is passed through untouched on every invocation.
"""
function create_callback(fnptr::Ptr{Cvoid}, ctx::Ptr{Cvoid})
    return function (du, u, p, t)
        n = length(u)
        GC.@preserve u du begin
            u_arr  = unsafe_wrap(Array{Float64,1}, pointer(u), n, own=false)
            du_arr = unsafe_wrap(Array{Float64,1}, pointer(du), n, own=false)
            errref = Ref{Cint}(0)
            ccall(fnptr, Cvoid,
                  (Ptr{Cvoid}, Clonglong, Ptr{Float64}, Ptr{Float64}, Float64, Ptr{Cint}),
                  ctx, n, pointer(u), pointer(du), Float64(t), errref)
        end
        errref[] != 0 && error("Fortran RHS callback failed with code $(errref[])")
    end
end

"""
    bind_callback(f) -> f

Bind `f` to the global `Main.FJ_CALLBACK` (latest created wins) so solver
code assembled with `eval` can reach it by name. Returns `f` unchanged; the
C bridge binds the SAME closure object it hands back as a handle.
"""
function bind_callback(f)
    Core.eval(Main, Expr(:(=), :FJ_CALLBACK, f))
    return f
end

end # module
