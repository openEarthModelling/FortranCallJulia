module ExamplesLib

using LinearAlgebra
using Base.Threads

# ==============================================================================
# 0. Quickstart Helpers (For Ex 01)
# ==============================================================================

function greet(name::String)
    println("Julia says: Hello, $name!")
    return "Greeting received"
end

function add_numbers(x::Float64, y::Float64)
    return x + y
end

# ==============================================================================
# 1. Basic Scalar & Array Logic (For Ex 02)
# ==============================================================================

# For Zero-Copy Example: Simulates updating a physics state array in-place
function update_simulation_state!(state::Matrix{Float64}, dt::Float64)
    # state is passed by reference (zero-copy)
    rows, cols = size(state)
    for j in 1:cols
        for i in 1:rows
            # Simple diffusion-like update
            state[i,j] += 0.1 * dt * (i + j)
        end
    end
    # println("[Julia] State updated with dt=$dt")
end

function process_primitives(i::Int64, b::Bool, s::String, c::ComplexF64)
    if b
        return c + i + length(s)
    else
        return c - i
    end
end

function modify_vector!(v::Vector{Float64})
    if length(v) > 0
        v[1] *= -1.0
    end
    return nothing
end

function modify_matrix!(m::Matrix{Float64})
    n = min(size(m)...)
    for i in 1:n
        m[i,i] += 100.0
    end
    return nothing
end

function inspect_3d_array(arr::Array{Float64, 3})
    return arr[1,1,1]
end

# ==============================================================================
# 2. Linear Algebra Core (The "Standard Payload")
# ==============================================================================

# A. Standard Zero-Copy Inverse (For Ex 03, 04, 05, 07)
function calc_inverse(A::Matrix{Float64})
    return inv(A)
end

function calc_eigenvalues(A::Matrix{Float64})
    return eigen(A).values
end

# B. Deep Copy Inverse (For Ex 04 Test A - "Slow Way")
function calc_inverse_copy(A::Matrix{Float64})
    # Simulate overhead of non-zero-copy transfer by explicit copying
    A_copy = copy(A)
    return inv(A_copy)
end

# C. Batch Inverse (For Ex 04 Test C - "Batching")
# Takes a 3D array (N, N, K) and returns a 3D array of inverses
function calc_inverse_batch(stack::Array{Float64, 3})
    N, M, K = size(stack)
    if N != M
        error("Matrices must be square")
    end
    
    # Pre-allocate result stack
    res_stack = similar(stack)
    
    # Serial Loop
    for k in 1:K
        # Extract slice (view), compute inv, assign back
        # Note: inv() allocates, but here we focus on call overhead reduction
        mat = view(stack, :, :, k)
        res_stack[:, :, k] = inv(mat)
    end
    
    return res_stack
end

# D. Parallel Batch Inverse (For Ex 06 - "Multithreading")
function calc_inverse_batch_parallel(stack::Array{Float64, 3})
    N, M, K = size(stack)
    res_stack = similar(stack)
    
    # Parallel Loop
    Threads.@threads for k in 1:K
        mat = view(stack, :, :, k)
        res_stack[:, :, k] = inv(mat)
    end
    
    return res_stack
end

# ==============================================================================
# 3. Fast Path Benchmarks (For Ex 04 Test A - CPU Bound)
# ==============================================================================
function fast_add(a::Float64, b::Float64)::Float64
    return a + b
end

# F. Fast Path Array (Ptr + Zero-Copy)
function calc_inverse_ptr_entry(ptr::Ptr{Float64}, n::Int64)::Cvoid
    # Create a temporary Julia array view over the raw C pointer (Zero allocation of data)
    arr = unsafe_wrap(Array, ptr, (n, n), own=false)
    inv(arr)
    return nothing
end

# G. Trace (O(N) - Light computation to expose Memory Copy cost)
function calc_trace(A::Matrix{Float64})
    return tr(A)
end

function calc_trace_copy(A::Matrix{Float64})
    B = copy(A)
    return tr(B)
end

function calc_trace_ptr_entry(ptr::Ptr{Float64}, n::Int64)::Cvoid
    arr = unsafe_wrap(Array, ptr, (n, n), own=false)
    tr(arr)
    return nothing
end

# H. Polymorphism (The OOP Advantage)
function polymorphic_func(x::Any)
    # Julia automatically handles dispatch based on runtime type
    if x isa Real
        return x * 2.0
    elseif x isa Complex
        return conj(x)
    elseif x isa AbstractString
        return "Hello " * x
    else
        return "Unknown Type"
    end
end

end # module