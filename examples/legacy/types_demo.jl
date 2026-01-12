module TypesDemo

export process_primitive_types, process_vector, process_3d_array

function process_primitive_types(i::Int64, b::Bool, s::String, c::ComplexF64)
    println("[Julia] Received Integer: ", i)
    println("[Julia] Received Bool:    ", b)
    println("[Julia] Received String:  ", s)
    println("[Julia] Received Complex: ", c)
    
    # Return a tuple or array? Generic call returns one object.
    # Let's return a complex result derived from inputs.
    if b
        return c + i + length(s)
    else
        return c - i
    end
end

function process_vector(v::Vector{Float64})
    println("[Julia] Received Vector, size: ", size(v))
    println("[Julia] First element: ", v[1])
    # Modify in place
    v[1] = v[1] * 100.0
    return nothing
end

function process_3d_array(arr::Array{Float64, 3})
    println("[Julia] Received 3D Array, size: ", size(arr))
    println("[Julia] Corner (1,1,1): ", arr[1,1,1])
    # Modify
    arr[1,1,1] = 999.0
    return nothing
end

end # module
