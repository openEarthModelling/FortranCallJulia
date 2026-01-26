module GCManager

export retain_obj, release_obj

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

end # module