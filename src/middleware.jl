module FortranBridge

using Base.Libc.Libdl

export retain_obj, release_obj, print_array_info, print_matrix_info, register_f2, register_f2_string, helper_getfield, helper_setfield, helper_getindex, helper_setindex, helper_call_kwargs, helper_getindex_2d, helper_setindex_2d, helper_getindex_3d, helper_setindex_3d, helper_getindex_string, helper_setindex_string, helper_length, helper_ndims, helper_size, helper_make_unitrange

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

# --- Accessors (Field & Index) ---

function helper_getfield(obj::Any, name::String)
    # Support both struct fields and NamedTuple keys via getproperty
    sym = Symbol(name)
    return getproperty(obj, sym)
end

function helper_setfield(obj::Any, name::String, val::Any)
    sym = Symbol(name)
    setproperty!(obj, sym, val)
    return nothing
end

function helper_getindex(obj::Any, idx::Int64)
    return getindex(obj, idx)
end

function helper_setindex(obj::Any, idx::Int64, val::Any)
    setindex!(obj, val, idx)
    return nothing
end

# --- Keyword Arguments Support ---

function helper_call_kwargs(func_name::String, args::Vector{Any}, kw_keys::Vector{String}, kw_vals::Vector{Any})
    if !isdefined(Main, Symbol(func_name))
        error("Function $func_name not found")
    end
    func = getfield(Main, Symbol(func_name))
    
    # Construct NamedTuple for kwargs
    # 1. Convert keys to Symbols
    syms = Tuple(Symbol.(kw_keys))
    # 2. Convert values to Tuple
    vals = Tuple(kw_vals)
    # 3. Create NamedTuple
    kw_nt = NamedTuple{syms}(vals)
    
    # Call
    return func(args...; kw_nt...)
end

# --- Extended Accessors (2D/3D/String) ---

function helper_getindex_2d(obj::Any, i::Int64, j::Int64)
    return getindex(obj, i, j)
end

function helper_setindex_2d(obj::Any, i::Int64, j::Int64, val::Any)
    setindex!(obj, val, i, j)
    return nothing
end

function helper_getindex_3d(obj::Any, i::Int64, j::Int64, k::Int64)
    return getindex(obj, i, j, k)
end

function helper_setindex_3d(obj::Any, i::Int64, j::Int64, k::Int64, val::Any)
    setindex!(obj, val, i, j, k)
    return nothing
end

function helper_getindex_string(obj::Any, key::String)
    return getindex(obj, key)
end

function helper_setindex_string(obj::Any, key::String, val::Any)
    setindex!(obj, val, key)
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