module AdvancedDemo

using LinearAlgebra
using Pkg

# --- Special Functions Logic ---

const SpecialFuncsLoaded = Ref{Bool}(false)

function ensure_special_functions()
    if SpecialFuncsLoaded[]
        return nothing
    end
    try
        @eval import SpecialFunctions
        SpecialFuncsLoaded[] = true
        println("[AdvancedDemo] SpecialFunctions loaded.")
    catch
        println("[AdvancedDemo] SpecialFunctions not found. Installing...")
        try
            Pkg.add("SpecialFunctions")
            @eval import SpecialFunctions
            SpecialFuncsLoaded[] = true
        catch e
            println("[AdvancedDemo] Error installing packages: ", e)
        end
    end
    return nothing
end

function calc_bessel_j(nu::Float64, x::Float64)
    if !SpecialFuncsLoaded[]
        ensure_special_functions()
    end
    sf = getfield(@__MODULE__, :SpecialFunctions)
    return Base.invokelatest(getfield(sf, :besselj), nu, x)
end

# --- Linear Algebra Wrappers ---

function calc_inv(A::Matrix{Float64})::Matrix{Float64}
    return inv(A)
end

function calc_eigen(A::Matrix{Float64})
    return eigen(A)
end

# --- Complex Workflow ---

function complex_demo_func(A::Matrix{Float64}, x::Float64)
    if !SpecialFuncsLoaded[]
        ensure_special_functions()
    end
    sf = getfield(@__MODULE__, :SpecialFunctions)
    besselj = getfield(sf, :besselj)
    
    j0_val = Base.invokelatest(besselj, 0.0, x)
    println("[AdvancedDemo] J0(", x, ") = ", j0_val)
    
    B = j0_val * A + inv(A)
    F = eigen(B)
    return F.values
end

end # module
