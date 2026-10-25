module Utilities

export print_array_info, print_matrix_info, helper_length, helper_ndims, helper_size, helper_make_unitrange

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

# --- Introspection & Util ---

function helper_length(obj::Any)
    return length(obj)
end

function helper_ndims(obj::Any)
    return ndims(obj)
end

function helper_size(obj::Any, dim::Int64)
    return size(obj, dim)
end

function helper_make_unitrange(start::Int64, stop::Int64)
    return start:stop
end

end # module