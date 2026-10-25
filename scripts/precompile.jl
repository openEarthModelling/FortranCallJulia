# scripts/precompile.jl

# Load the FortranBridge package from its project environment. Run with the
# package project active, e.g. julia --project=src/FortranBridge, or via
# scripts/build_sysimage.jl (which activates the project for the build).
using FortranBridge

# 1. Exercise Fast Path Registration
# This triggers compilation of the @cfunction wrapper.
# register_f2 takes the function itself plus its lookup name; the old script
# called it with (:julia_add, Float64, (Float64, Float64)) and never defined
# julia_add at all, so it could not have run as written.
julia_add(a, b) = a + b
c_ptr = register_f2(julia_add, "julia_add")

# 2. Exercise Object Management
# We use a mutable struct to be safe with pointer conversion if needed, 
# though String is usually okay for testing.
mutable struct TestType
    x::Int
end
obj = TestType(42)

# The GC manager keys on the raw pointer address (what C passes back), so
# retention takes the pointer together with the object it protects.
ptr = pointer_from_objref(obj)
retain_obj(ptr, obj)
release_obj(ptr)

# 3. Exercise Array Utils
print_array_info([1.0, 2.0, 3.0])

# 4. Exercise the math function
julia_add(10.0, 20.0)

println("Precompilation complete.")
