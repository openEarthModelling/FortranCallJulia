module FortranBridge

using Base.Libc.Libdl

export retain_obj, release_obj, print_array_info, print_matrix_info, register_f2, register_f2_string

# --- Global Reference Management (GC Protection) ---
# We map the Raw Pointer Address -> Object.
# This ensures that even for identical immutable values (like two 42s), 
# we protect the specific boxed instance that Fortran holds a pointer to.
const PTR_CACHE = Dict{Ptr{Cvoid}, Any}()
const REF_COUNTS = Dict{Ptr{Cvoid}, Int}()
const REF_LOCK = ReentrantLock()

function retain_obj(ptr::Ptr{Cvoid}, obj::Any)::Nothing
    lock(REF_LOCK) do
        count = get(REF_COUNTS, ptr, 0)
        REF_COUNTS[ptr] = count + 1
        if count == 0
            PTR_CACHE[ptr] = obj
        end
    end
    return nothing
end

function release_obj(ptr::Ptr{Cvoid})
    if ptr == C_NULL
        return
    end
    lock(REF_LOCK) do
        count = get(REF_COUNTS, ptr, 0)
        if count > 1
            REF_COUNTS[ptr] = count - 1
        elseif count == 1
            delete!(REF_COUNTS, ptr)
            delete!(PTR_CACHE, ptr)
        else
            # count 0, already deleted or error
        end
    end
    return nothing
end

# --- Fast Path Registration Helpers ---

function register_f2(func::Function, name::String)
    ptr = @cfunction($func, Float64, (Float64, Float64))
    println("[FortranBridge] Registered ", name, " at ", ptr)
    return ptr
end

function register_f2_string(func_name::String, ret_type::String, arg_types::String)
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
