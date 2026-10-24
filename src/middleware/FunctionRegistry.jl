module FunctionRegistry

export register_f2, register_f2_string, helper_call_kwargs

# Root the CFunction objects created by the runtime @cfunction path so that
# the GC cannot collect them while Fortran still holds their addresses.
const CFUNCS = Dict{String, Any}()

# --- Fast Path Registration Helpers ---

function register_f2(func::Function, name::String)
    ptr = @cfunction($func, Float64, (Float64, Float64))
    println("[FortranBridge] Registered ", name, " at ", ptr)
    try
        cf_obj = unsafe_pointer_to_objref(ptr)
        CFUNCS[String(name)] = (func, cf_obj)   # keep both the function and the trampoline alive
    catch
        println("[FortranBridge] Warning: could not root CFunction object for ", name)
    end
    return ptr
end

function register_f2_string(func_name::String, ret_type_str::String, arg_types_str::String)
    # 1. Lookup Function using eval to support "Mod.func"
    func = nothing
    try
        # Evaluate in Main scope so that 'using' in Main works, 
        # and 'Mod.func' also works.
        func = Main.eval(Meta.parse(func_name))
    catch
    end

    if func === nothing
        println("[FortranBridge] Error: Function '$func_name' not found.")
        return C_NULL
    end

    # 2. Dynamic Type Parsing & AST Construction
    try
        # We parse the strings into AST expressions (Expr), but we DO NOT eval them yet.
        # @cfunction macro expects the type arguments to be expressions that look like types/tuples.
        
        RetTypeExpr = Meta.parse(ret_type_str)
        ArgTypesExpr = Meta.parse(arg_types_str)
        
        # Ensure ArgTypes is a tuple expression (e.g., if user passed "Float64", make it "(Float64,)")
        if !isa(ArgTypesExpr, Expr) || ArgTypesExpr.head != :tuple
            ArgTypesExpr = Expr(:tuple, ArgTypesExpr)
        end
        
        # 3. Dynamic @cfunction Generation
        # We construct the expression: @cfunction(func_val, RetTypeExpr, ArgTypesExpr)
        # Note: We must interpolate the *value* of func, but the *expressions* of the types.
        
        # We use a let block or direct interpolation. 
        # Construction:
        cfunc_expr = :( @cfunction($func, $RetTypeExpr, $ArgTypesExpr) )
        
        # 4. Evaluate the constructed expression in the module scope
        cfunc_ptr = eval(cfunc_expr)

        try
            cf_obj = unsafe_pointer_to_objref(cfunc_ptr)
            CFUNCS[String(func_name)] = (func, cf_obj)   # keep both the function and the trampoline alive
        catch
            println("[FortranBridge] Warning: could not root CFunction object for ", func_name)
        end

        return cfunc_ptr

    catch e
        println("[FortranBridge] Error generating cfunction: ", e)
        return C_NULL
    end
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

end # module