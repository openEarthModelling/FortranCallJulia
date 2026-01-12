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

function register_f2_string(func_name::String, ret_type_str::String, arg_types_str::String)
    # 1. Lookup Function
    if !isdefined(Main, Symbol(func_name))
        println("[FortranBridge] Error: Function '$func_name' not found in Main.")
        return C_NULL
    end
    func = getfield(Main, Symbol(func_name))

    # 2. Dynamic Type Parsing & AST Construction
    try
        # We parse the strings into AST expressions (Expr), but we DO NOT eval them yet.
        # @cfunction macro expects the type arguments to be expressions that look like types/tuples.
        
        RetTypeExpr = Meta.parse(ret_type_str)
        ArgTypesExpr = Meta.parse(arg_types_str) # e.g., returns the Expr: :( (Float64, Int64) )
        
        # 3. Dynamic @cfunction Generation
        # We construct the expression: @cfunction(func_val, RetTypeExpr, ArgTypesExpr)
        # Note: We must interpolate the *value* of func, but the *expressions* of the types.
        
        # We use a let block or direct interpolation. 
        # Construction:
        cfunc_expr = :( @cfunction($func, $RetTypeExpr, $ArgTypesExpr) )
        
        # 4. Evaluate the constructed expression in the module scope
        cfunc_ptr = eval(cfunc_expr)
        
        return cfunc_ptr

    catch e
        println("[FortranBridge] Error generating cfunction: ", e)
        return C_NULL
    end
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
