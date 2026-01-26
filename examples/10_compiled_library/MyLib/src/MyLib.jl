module MyLib

using CEnum

# 1. 简单的健康检查/初始化函数
Base.@ccallable function my_lib_init()::Cint
    println("[Julia] MyLib initialized successfully.")
    return 1
end

# 2. 基础类型传递 (Integer)
Base.@ccallable function my_add(a::Cint, b::Cint)::Cint
    # println("[Julia] Calculating ", a, " + ", b)
    return a + b
end

# 3. 数组传递 (Pointer + Length)
# 接收 C 指针和长度，计算数组元素的和
Base.@ccallable function my_sum_array(ptr::Ptr{Cdouble}, len::Cint)::Cdouble
    # 使用 unsafe_wrap 将 C 指针包装为 Julia Array
    # own=false 表示 Julia 不管理这块内存的释放
    arr = unsafe_wrap(Array, ptr, (len,); own=false)
    
    s = 0.0
    for x in arr
        s += x
    end
    
    # println("[Julia] Array sum calculated: ", s)
    return s
end

end # module MyLib