module julia_library_interface
    use julia_types
    implicit none

    ! 定义 PackageCompiler 生成的库的标准生命周期函数
    interface
        ! void init_julia(int argc, char **argv)
        subroutine init_julia(argc, argv) bind(C, name="init_julia")
            import :: c_int, c_ptr
            integer(c_int), value :: argc
            type(c_ptr), value :: argv
        end subroutine init_julia

        ! void shutdown_julia(int retcode)
        subroutine shutdown_julia(retcode) bind(C, name="shutdown_julia")
            import :: c_int
            integer(c_int), value :: retcode
        end subroutine shutdown_julia
    end interface

end module julia_library_interface
