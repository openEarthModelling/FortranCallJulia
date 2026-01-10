module FortranBridge

using Base.Libc.Libdl

export julia_add, print_array_info, retain_obj, release_obj, register_f2

# --- Global Reference Management (GC Protection) ---
# Prevents Julia objects held by Fortran/C from being garbage collected.
const GlobalRef = IdDict{Any, Nothing}()
const GlobalRefLock = ReentrantLock()

"""
    retain_obj(obj::Any)

Adds the object to the global reference dictionary to prevent GC.
"""
function retain_obj(obj::Any)
    lock(GlobalRefLock) do
        GlobalRef[obj] = nothing
    end
    return nothing
end

"""
    release_obj(ptr::Ptr{Cvoid})

Removes the object (identified by its pointer) from the global reference dictionary,
allowing it to be garbage collected if no other references exist.
"""
function release_obj(ptr::Ptr{Cvoid})
    # We need to recover the object from the pointer to remove it from the Dict.
    # CAUTION: unsafe_pointer_to_objref is unsafe if the object is already GC'd,
    # but here we assume it's still in GlobalRef.
    try
        # Note: unsafe_pointer_to_objref is strictly for mutable objects.
        # For immutables, this entire mechanism of "release by pointer" is tricky
        # because we don't really have a pointer to the *boxed* object in Julia easily 
        # unless we pass it from C.
        
        # But wait, C passes 'ptr' which IS the jl_value_t*.
        # unsafe_pointer_to_objref(ptr) basically casts void* to Any.
        # It SHOULD work for boxed immutables too if ptr is the jl_value_t*.
        
        obj = unsafe_pointer_to_objref(ptr)
        lock(GlobalRefLock) do
            delete!(GlobalRef, obj)
        end
    catch e
        @error "Failed to release object: invalid pointer or already freed." exception=e
    end
    return nothing
end


# --- Fast Path Registration (Function Pointers) ---

const FunctionCache = Dict{Symbol, Ptr{Cvoid}}()

"""
    register_f2(func_name::Symbol, return_type::Type, arg_types::Tuple) -> Ptr{Cvoid}

Generates a C-callable function pointer for a given Julia function.
This is used for the "Fast Path" where Fortran calls Julia via a function pointer.
"""
function register_f2(func_name::Symbol, return_type::Type, arg_types::Tuple)
    # Check cache first
    if haskey(FunctionCache, func_name)
        return FunctionCache[func_name]
    end
    
    # Get the function object
    func = nothing
    if isdefined(Main, func_name)
        func = getfield(Main, func_name)
    elseif isdefined(@__MODULE__, func_name)
        func = getfield(@__MODULE__, func_name)
    else
        error("Function '$func_name' not defined in Main or FortranBridge.")
    end

    # Compile a C-callable wrapper
    # @cfunction requires literal types in the macro, so we use eval to construct it.
    
    # We need to ensure the third argument is an Expr(:tuple, ...), not just the tuple value.
    arg_types_expr = Expr(:tuple, arg_types...)
    
    # Construct the expression: @cfunction(func, ReturnType, (ArgTypes...))
    cfunc_expr = :(@cfunction($func, $return_type, $arg_types_expr))
    
    try
        c_ptr = eval(cfunc_expr)
        FunctionCache[func_name] = c_ptr
        return c_ptr
    catch e
        @error "Failed to register C function for $func_name" exception=e
        rethrow(e)
    end
end

# --- Array Handling Utilities ---

"""
    print_array_info(arr::Array)

Helper to verify array data passing.
"""
function print_array_info(arr::Array)
    println("[Julia] Array Info:")
    println("  Type: ", typeof(arr))
    println("  Size: ", size(arr))
    println("  First Element: ", isempty(arr) ? "empty" : arr[1])
    return nothing
end

# --- Example Mathematical Function for Testing ---

function julia_add(a::Float64, b::Float64)::Float64
    return a + b
end

end # module
