module FortranBridge

using Base.Libc.Libdl

export retain_obj, release_obj, print_array_info, print_matrix_info, register_f2, register_f2_string

# --- Global Reference Management (GC Protection) ---
# Prevents Julia objects held by Fortran/C from being garbage collected.
const REF_HOLDER = IdDict{Any, Nothing}()
const REF_LOCK = ReentrantLock()

function retain_obj(obj::Any)::Ptr{Cvoid}
    lock(REF_LOCK) do
        REF_HOLDER[obj] = nothing
    end
    # Return pointer to object itself (as handle)
    return pointer_from_objref(obj)
end

function release_obj(ptr::Ptr{Cvoid})
    if ptr == C_NULL
        return
    end
    # We need to find the object corresponding to this pointer to remove it from IdDict.
    # Unsafe pointer conversion:
    try
        obj = unsafe_pointer_to_objref(ptr)
        lock(REF_LOCK) do
            delete!(REF_HOLDER, obj)
        end
    catch e
        println("[FortranBridge] Warning: Failed to release object at ", ptr)
    end
    return nothing
end

# --- Fast Path Registration Helpers ---

function register_f2(func::Function, name::String)
    # Get function pointer for a standard (Float64, Float64) -> Float64 function
    # Note: This requires @cfunction which needs concrete types at compile time usually.
    # For dynamic functions, we might need a trampoline or just use the generic jl_call path.
    
    # For the purpose of this demo, we assume the user provides a C-compatible function pointer
    # or we use the slower jl_call path. 
    # But if we want to expose a function pointer to C:
    ptr = @cfunction($func, Float64, (Float64, Float64))
    println("[FortranBridge] Registered ", name, " at ", ptr)
    return ptr
end

function register_f2_string(func_name::String, ret_type::String, arg_types::String)
    # This function is called by C to resolve a function pointer.
    # In a real middleware, we would parse types and generate @cfunction.
    # For now, we return a pointer if it's a known optimized path, or NULL.
    # Real implementation would use RuntimeGeneratedFunctions or similar.
    return C_NULL
end

# --- Inspection Tools ---

function print_array_info(arr::Array)
    println("[Julia] Array Info:")
    println("  Type: ", typeof(arr))
    println("  Size: ", size(arr))
    println("  Data: ", arr)
    return nothing
end

function print_matrix_info(mat::Matrix)
    println("[Julia] Matrix Info:")
    println("  Type: ", typeof(mat))
    println("  Size: ", size(mat))
    if !isempty(mat)
        println("  Corner (1,1): ", mat[1,1])
        println("  Corner (end,end): ", mat[end,end])
    end
    return nothing
end

end # module
