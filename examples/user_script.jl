module UserLogic

using LinearAlgebra
using Pkg

function ensure_dependencies()
    try
        @eval import SpecialFunctions
    catch
        println("[UserLogic] Installing SpecialFunctions...")
        try
            Pkg.add("SpecialFunctions")
            @eval import SpecialFunctions
        catch e
             println("[UserLogic] Error installing packages: ", e)
        end
    end
end

"""
    run_simulation(A::Matrix{Float64}, scalar::Float64)

Calculates J1(scalar) * A^2.
"""
function run_simulation(A::Matrix{Float64}, scalar::Float64)
    println("[UserLogic] --- External Script Started ---")
    ensure_dependencies()
    
    # Use dynamic dispatch for SpecialFunctions (safe import)
    sf = getfield(@__MODULE__, :SpecialFunctions)
    besselj = getfield(sf, :besselj)
    
    println("[UserLogic] Calculating BesselJ(1, ", scalar, ")...")
    j1_val = Base.invokelatest(besselj, 1.0, scalar)
    
    println("[UserLogic] J1 Result: ", j1_val)
    println("[UserLogic] Calculating A * A...")
    
    A_sq = A * A
    
    println("[UserLogic] Scaling Matrix by J1...")
    result_mat = j1_val * A_sq
    
    println("[UserLogic] --- External Script Finished ---")
    return result_mat
end

end # module
