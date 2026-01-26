module Accessors

export helper_getfield, helper_setfield, helper_getindex, helper_setindex
export helper_getindex_2d, helper_setindex_2d, helper_getindex_3d, helper_setindex_3d
export helper_getindex_string, helper_setindex_string

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

end # module