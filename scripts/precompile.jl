# scripts/precompile.jl

# Ensure module is loaded (if running standalone)
if !isdefined(Main, :FortranBridge)
    # Assuming running from project root or scripts dir
    path = joinpath(@__DIR__, "..", "src", "middleware.jl")
    if isfile(path)
        include(path)
    else
        include("../src/middleware.jl")
    end
end

using Main.FortranBridge

# 1. Exercise Fast Path Registration
# This triggers compilation of the @cfunction wrapper
c_ptr = register_f2(:julia_add, Float64, (Float64, Float64))

# 2. Exercise Object Management
# We use a mutable struct to be safe with pointer conversion if needed, 
# though String is usually okay for testing.
mutable struct TestType
    x::Int
end
obj = TestType(42)

retain_obj(obj)
# We simulate what C would pass back: the pointer to the object
ptr = pointer_from_objref(obj)
release_obj(ptr)

# 3. Exercise Array Utils
print_array_info([1.0, 2.0, 3.0])

# 4. Exercise the math function
julia_add(10.0, 20.0)

println("Precompilation complete.")
