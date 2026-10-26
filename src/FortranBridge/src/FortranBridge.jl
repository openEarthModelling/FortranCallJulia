module FortranBridge

using Base.Libc.Libdl

# Include submodules
include("GCManager.jl")
include("FunctionRegistry.jl")
include("Accessors.jl")
include("Utilities.jl")
include("Callbacks.jl")

# Re-export symbols so the interface remains unchanged for the Fortran side and C bridge

# GC Manager
using .GCManager
export retain_obj, release_obj

# Function Registry
using .FunctionRegistry
export register_f2, register_f2_string, helper_call_kwargs, clear_kw_cache!

# Accessors
using .Accessors
export helper_getfield, helper_setfield, helper_getindex, helper_setindex
export helper_getindex_2d, helper_setindex_2d, helper_getindex_3d, helper_setindex_3d
export helper_getindex_string, helper_setindex_string

# Utilities
using .Utilities
export print_array_info, print_matrix_info, helper_length, helper_ndims, helper_size, helper_make_unitrange

# Callbacks
using .Callbacks
export create_callback, bind_callback

end # module
