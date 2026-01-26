module julia_types
    use iso_c_binding
    implicit none

    ! 这里目前主要作为 iso_c_binding 的透传
    ! 未来可以添加：
    ! - String conversion helpers (Fortran string <-> C pointer)
    ! - Array descriptor helpers
    
    ! 重新导出常用类型，方便用户只 use 这一个模块
    public :: c_int, c_double, c_float, c_ptr, c_null_ptr, c_char, c_loc, c_f_pointer

end module julia_types
