module FunctionRegistry

export register_f2, register_f2_string, helper_call_kwargs

# Root the CFunction objects created by the runtime @cfunction path so that
# the GC cannot collect them while Fortran still holds their addresses.
const CFUNCS = Dict{String, Any}()

# --- Fast Path Registration Helpers ---

function register_f2(func::Function, name::String)
ptr = @cfunction($func, Float64, (Float64, Float64))
println("[FortranBridge] Registered ", name, " at ", ptr)
CFUNCS[String(name)] = (func, ptr)   # keep the source function alive
return ptr
end

function register_f2_string(func_name::String, ret_type_str::String, arg_types_str::String)
# 1. Lookup Function using eval to support "Mod.func"
func = nothing
try
func = Main.eval(Meta.parse(func_name))
catch
end
if func === nothing
println("[FortranBridge] Error: Function '$func_name' not found.")
return C_NULL
end
try
# 2. Dynamic Type Parsing
RetTypeExpr = Meta.parse(ret_type_str)
ArgTypesExpr = Meta.parse(arg_types_str)
if !isa(ArgTypesExpr, Expr) || ArgTypesExpr.head != :tuple
ArgTypesExpr = Expr(:tuple, ArgTypesExpr)
end
# 3. Dynamic @cfunction generation, rooted in Main. The @cfunction result
# must live in a real global binding: the raw trampoline address is not a
# Julia object, and a raw pointer-to-objref reinterpretation manufactures a corrupt
# object that crashes the GC / type cache (SIGSEGV in jl_inst_arg_tuple_type).
root_sym = Symbol("#fj_cfunc#", func_name)
cfunc_ptr = Main.eval(quote
global $root_sym = @cfunction($func, $RetTypeExpr, $ArgTypesExpr)
Base.unsafe_convert(Ptr{Cvoid}, $root_sym)
end)
CFUNCS[String(func_name)] = (func, cfunc_ptr)
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