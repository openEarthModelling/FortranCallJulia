program main
    use iso_c_binding
    use julia_library_interface ! 引入标准生命周期接口
    implicit none

    ! ==================================================================
    ! 业务接口声明 (MyLib Specific)
    ! ==================================================================
    ! 注意：init_julia 和 shutdown_julia 已经通过 use 引入了，这里不需要再写
    interface
        ! MyLib: Init
        function my_lib_init() bind(C, name="my_lib_init") result(res)
            import :: c_int
            integer(c_int) :: res
        end function my_lib_init

        ! MyLib: Add
        function my_add(a, b) bind(C, name="my_add") result(res)
            import :: c_int
            integer(c_int), value :: a, b
            integer(c_int) :: res
        end function my_add

        ! MyLib: Sum Array
        function my_sum_array(ptr, len) bind(C, name="my_sum_array") result(res)
            import :: c_double, c_int, c_ptr
            type(c_ptr), value :: ptr
            integer(c_int), value :: len
            real(c_double) :: res
        end function my_sum_array
    end interface

    ! ==================================================================
    ! 主程序逻辑
    ! ==================================================================
    integer(c_int) :: ret
    integer(c_int) :: a, b, sum_val
    real(c_double), target :: data_array(5)
    real(c_double) :: array_sum
    integer :: i

    print *, "[Fortran] Starting Compiled Library Demo (with Shared Modules)..."

    ! 1. 初始化 Julia 运行时 (来自 julia_library_interface)
    call init_julia(0_c_int, c_null_ptr)
    print *, "[Fortran] Julia runtime initialized."

    ! 2. 调用业务初始化
    ret = my_lib_init()
    if (ret /= 1) then
        print *, "[Fortran] Error: MyLib init failed!"
        stop
    end if

    ! 3. 测试整数加法
    a = 10
    b = 32
    sum_val = my_add(a, b)
    print *, "[Fortran] 10 + 32 =", sum_val
    if (sum_val /= 42) then
        print *, "[Fortran] Math check failed!"
    else
        print *, "[Fortran] Math check passed."
    end if

    ! 4. 测试数组传递
    do i = 1, 5
        data_array(i) = real(i, c_double) * 1.5d0 
    end do

    print *, "[Fortran] Calculating array sum (passing pointer)..."
    array_sum = my_sum_array(c_loc(data_array), 5_c_int)
    print *, "[Fortran] Sum result:", array_sum

    if (abs(array_sum - 22.5d0) < 1.0d-6) then
        print *, "[Fortran] Array check passed."
    else
        print *, "[Fortran] Array check failed!"
    end if

    ! 5. 关闭运行时 (来自 julia_library_interface)
    call shutdown_julia(0_c_int)
    print *, "[Fortran] Shutdown complete."

end program main