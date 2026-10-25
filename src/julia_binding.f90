module julia_low_level
    use iso_c_binding
    implicit none

    ! Mirrors C struct fj_options_t (bridge.h); field order and types must match.
    type, bind(c) :: FjOptions
        type(c_ptr) :: sysimage_path
        type(c_ptr) :: project_path
        integer(kind=c_int) :: nthreads
        integer(kind=c_int) :: handle_signals
    end type FjOptions

    ! --- C Interface Definitions ---
    interface
        subroutine fj_init(image_path) bind(c, name="fj_init")
            import :: c_char, c_ptr
            type(c_ptr), value :: image_path
        end subroutine fj_init

        subroutine fj_init_ex(opts) bind(c, name="fj_init_ex")
            import :: c_ptr
            type(c_ptr), value :: opts
        end subroutine fj_init_ex

        subroutine fj_shutdown() bind(c, name="fj_shutdown")
        end subroutine fj_shutdown

        function fj_retain(val) bind(c, name="fj_retain") result(ptr)
            import :: c_ptr
            type(c_ptr), value :: val
            type(c_ptr) :: ptr
        end function fj_retain

        subroutine fj_release(ptr) bind(c, name="fj_release")
            import :: c_ptr
            type(c_ptr), value :: ptr
        end subroutine fj_release

        function fj_call0(func_name) bind(c, name="fj_call0") result(res)
            import :: c_char, c_ptr
            character(kind=c_char), dimension(*), intent(in) :: func_name
            type(c_ptr) :: res
        end function fj_call0

        function fj_call1_float64(func_name, arg1) bind(c, name="fj_call1_float64") result(res)
            import :: c_char, c_double, c_ptr
            character(kind=c_char), dimension(*), intent(in) :: func_name
            real(kind=c_double), value :: arg1
            type(c_ptr) :: res
        end function fj_call1_float64

        function fj_call1_obj(func_name, arg_obj) bind(c, name="fj_call1_obj") result(res)
            import :: c_char, c_ptr
            character(kind=c_char), dimension(*), intent(in) :: func_name
            type(c_ptr), value :: arg_obj
            type(c_ptr) :: res
        end function fj_call1_obj

        function fj_call2_obj_double(func_name, arg_obj, arg2) bind(c, name="fj_call2_obj_double") result(res)
            import :: c_char, c_ptr, c_double
            character(kind=c_char), dimension(*), intent(in) :: func_name
            type(c_ptr), value :: arg_obj
            real(kind=c_double), value :: arg2
            type(c_ptr) :: res
        end function fj_call2_obj_double

        function fj_call_general(func_name, args, nargs) bind(c, name="fj_call_general") result(res)
            import :: c_char, c_ptr, c_int32_t
            character(kind=c_char), dimension(*), intent(in) :: func_name
            type(c_ptr), dimension(*), intent(in) :: args
            integer(kind=c_int32_t), value :: nargs
            type(c_ptr) :: res
        end function fj_call_general

        function fj_call_kwargs(func_name, args, nargs, kw_keys, kw_vals, nkw) bind(c, name="fj_call_kwargs") result(res)
            import :: c_char, c_ptr, c_int32_t
            character(kind=c_char), dimension(*), intent(in) :: func_name
            type(c_ptr), dimension(*), intent(in) :: args
            integer(kind=c_int32_t), value :: nargs
            type(c_ptr), dimension(*), intent(in) :: kw_keys
            type(c_ptr), dimension(*), intent(in) :: kw_vals
            integer(kind=c_int32_t), value :: nkw
            type(c_ptr) :: res
        end function fj_call_kwargs

        ! --- Cached Function Handles ---
        function fj_resolve_function(name) bind(c, name="fj_resolve_function") result(res)
            import :: c_char, c_ptr
            character(kind=c_char), dimension(*), intent(in) :: name
            type(c_ptr) :: res
        end function fj_resolve_function

        function fj_call_function(func, args, nargs) bind(c, name="fj_call_function") result(res)
            import :: c_ptr, c_int32_t
            type(c_ptr), value :: func
            type(c_ptr), dimension(*), intent(in) :: args
            integer(kind=c_int32_t), value :: nargs
            type(c_ptr) :: res
        end function fj_call_function

        function fj_eval_string(cmd) bind(c, name="fj_eval_string") result(res)
            import :: c_char, c_ptr
            character(kind=c_char), dimension(*), intent(in) :: cmd
            type(c_ptr) :: res
        end function fj_eval_string

        function fj_get_function_pointer(func_name, ret_type, arg_types) bind(c, name="fj_get_function_pointer") result(funptr)
            import :: c_char, c_funptr
            character(kind=c_char), dimension(*), intent(in) :: func_name
            character(kind=c_char), dimension(*), intent(in) :: ret_type
            character(kind=c_char), dimension(*), intent(in) :: arg_types
            type(c_funptr) :: funptr
        end function fj_get_function_pointer
        
        function fj_get_last_error() bind(c, name="fj_get_last_error") result(c_str)
            import :: c_ptr
            type(c_ptr) :: c_str
        end function fj_get_last_error
        
        ! --- Array Wrappers ---
        function fj_wrap_array_1d(data, length) bind(c, name="fj_wrap_array_1d") result(res)
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: data
            integer(kind=c_int64_t), value :: length
            type(c_ptr) :: res
        end function fj_wrap_array_1d

        function fj_wrap_array_2d(data, rows, cols) bind(c, name="fj_wrap_array_2d") result(res)
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: data
            integer(kind=c_int64_t), value :: rows, cols
            type(c_ptr) :: res
        end function fj_wrap_array_2d

        function fj_wrap_array_3d(data, dim1, dim2, dim3) bind(c, name="fj_wrap_array_3d") result(res)
            import :: c_ptr, c_long
            type(c_ptr), value :: data
            integer(kind=c_long), value :: dim1, dim2, dim3
            type(c_ptr) :: res
        end function fj_wrap_array_3d

        ! --- Array Deep Copies ---
        function fj_copy_array_1d(data, dim1) bind(c, name="fj_copy_array_1d") result(res)
            import :: c_ptr, c_long
            type(c_ptr), value :: data
            integer(kind=c_long), value :: dim1
            type(c_ptr) :: res
        end function fj_copy_array_1d

        function fj_copy_array_2d(data, dim1, dim2) bind(c, name="fj_copy_array_2d") result(res)
            import :: c_ptr, c_long
            type(c_ptr), value :: data
            integer(kind=c_long), value :: dim1, dim2
            type(c_ptr) :: res
        end function fj_copy_array_2d

        function fj_copy_array_3d(data, dim1, dim2, dim3) bind(c, name="fj_copy_array_3d") result(res)
            import :: c_ptr, c_long
            type(c_ptr), value :: data
            integer(kind=c_long), value :: dim1, dim2, dim3
            type(c_ptr) :: res
        end function fj_copy_array_3d

        ! --- Accessors ---
        function fj_box_float64(val) bind(c, name="fj_box_float64") result(res)
            import :: c_ptr, c_double
            real(kind=c_double), value :: val
            type(c_ptr) :: res
        end function fj_box_float64

        function fj_box_int64(val) bind(c, name="fj_box_int64") result(res)
            import :: c_ptr, c_int64_t
            integer(kind=c_int64_t), value :: val
            type(c_ptr) :: res
        end function fj_box_int64

        function fj_box_int32(val) bind(c, name="fj_box_int32") result(res)
            import :: c_ptr, c_int32_t
            integer(kind=c_int32_t), value :: val
            type(c_ptr) :: res
        end function fj_box_int32

        function fj_box_bool(val) bind(c, name="fj_box_bool") result(res)
            import :: c_ptr, c_int
            integer(kind=c_int), value :: val
            type(c_ptr) :: res
        end function fj_box_bool

        function fj_box_string(val) bind(c, name="fj_box_string") result(res)
            import :: c_ptr, c_char
            character(kind=c_char), dimension(*), intent(in) :: val
            type(c_ptr) :: res
        end function fj_box_string

        function fj_box_complex(re, im) bind(c, name="fj_box_complex") result(res)
            import :: c_ptr, c_double
            real(kind=c_double), value :: re, im
            type(c_ptr) :: res
        end function fj_box_complex

        ! --- Unboxing ---
        function fj_unbox_float64(obj) bind(c, name="fj_unbox_float64") result(val)
            import :: c_ptr, c_double
            type(c_ptr), value :: obj
            real(kind=c_double) :: val
        end function fj_unbox_float64

        function fj_unbox_int64(obj) bind(c, name="fj_unbox_int64") result(val)
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: obj
            integer(kind=c_int64_t) :: val
        end function fj_unbox_int64

        function fj_unbox_int32(obj) bind(c, name="fj_unbox_int32") result(val)
            import :: c_ptr, c_int32_t
            type(c_ptr), value :: obj
            integer(kind=c_int32_t) :: val
        end function fj_unbox_int32

        function fj_unbox_bool(obj) bind(c, name="fj_unbox_bool") result(val)
            import :: c_ptr, c_int
            type(c_ptr), value :: obj
            integer(kind=c_int) :: val
        end function fj_unbox_bool

        function fj_unbox_string(obj) bind(c, name="fj_unbox_string") result(c_str)
            import :: c_ptr
            type(c_ptr), value :: obj
            type(c_ptr) :: c_str
        end function fj_unbox_string

        function fj_unbox_complex_real(obj) bind(c, name="fj_unbox_complex_real") result(val)
            import :: c_ptr, c_double
            type(c_ptr), value :: obj
            real(kind=c_double) :: val
        end function fj_unbox_complex_real

        function fj_unbox_complex_imag(obj) bind(c, name="fj_unbox_complex_imag") result(val)
            import :: c_ptr, c_double
            type(c_ptr), value :: obj
            real(kind=c_double) :: val
        end function fj_unbox_complex_imag

        ! --- Accessors ---
        function fj_get_field(obj, name) bind(c, name="fj_get_field") result(res)
            import :: c_ptr, c_char
            type(c_ptr), value :: obj
            character(kind=c_char), dimension(*), intent(in) :: name
            type(c_ptr) :: res
        end function fj_get_field

        subroutine fj_set_field(obj, name, val) bind(c, name="fj_set_field")
            import :: c_ptr, c_char
            type(c_ptr), value :: obj
            character(kind=c_char), dimension(*), intent(in) :: name
            type(c_ptr), value :: val
        end subroutine fj_set_field

        function fj_get_index_i(obj, idx) bind(c, name="fj_get_index_i") result(res)
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: idx
            type(c_ptr) :: res
        end function fj_get_index_i

        subroutine fj_set_index_i(obj, idx, val) bind(c, name="fj_set_index_i")
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: idx
            type(c_ptr), value :: val
        end subroutine fj_set_index_i

        ! --- Extended Accessors ---
        function fj_get_index_ii(obj, i, j) bind(c, name="fj_get_index_ii") result(res)
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: i, j
            type(c_ptr) :: res
        end function fj_get_index_ii

        subroutine fj_set_index_ii(obj, i, j, val) bind(c, name="fj_set_index_ii")
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: i, j
            type(c_ptr), value :: val
        end subroutine fj_set_index_ii

        function fj_get_index_iii(obj, i, j, k) bind(c, name="fj_get_index_iii") result(res)
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: i, j, k
            type(c_ptr) :: res
        end function fj_get_index_iii

        subroutine fj_set_index_iii(obj, i, j, k, val) bind(c, name="fj_set_index_iii")
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: i, j, k
            type(c_ptr), value :: val
        end subroutine fj_set_index_iii

        function fj_get_index_s(obj, key) bind(c, name="fj_get_index_s") result(res)
            import :: c_ptr, c_char
            type(c_ptr), value :: obj
            character(kind=c_char), dimension(*), intent(in) :: key
            type(c_ptr) :: res
        end function fj_get_index_s

        subroutine fj_set_index_s(obj, key, val) bind(c, name="fj_set_index_s")
            import :: c_ptr, c_char
            type(c_ptr), value :: obj
            character(kind=c_char), dimension(*), intent(in) :: key
            type(c_ptr), value :: val
        end subroutine fj_set_index_s

        ! --- Fast Real Element Accessors ---
        function fj_get_real(obj, idx) bind(c, name="fj_get_real") result(val)
            import :: c_ptr, c_int64_t, c_double
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: idx
            real(kind=c_double) :: val
        end function fj_get_real

        subroutine fj_set_real(obj, idx, val) bind(c, name="fj_set_real")
            import :: c_ptr, c_int64_t, c_double
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: idx
            real(kind=c_double), value :: val
        end subroutine fj_set_real

        function fj_get_real2(obj, i, j) bind(c, name="fj_get_real2") result(val)
            import :: c_ptr, c_int64_t, c_double
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: i, j
            real(kind=c_double) :: val
        end function fj_get_real2

        subroutine fj_set_real2(obj, i, j, val) bind(c, name="fj_set_real2")
            import :: c_ptr, c_int64_t, c_double
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: i, j
            real(kind=c_double), value :: val
        end subroutine fj_set_real2

        function fj_get_real3(obj, i, j, k) bind(c, name="fj_get_real3") result(val)
            import :: c_ptr, c_int64_t, c_double
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: i, j, k
            real(kind=c_double) :: val
        end function fj_get_real3

        subroutine fj_set_real3(obj, i, j, k, val) bind(c, name="fj_set_real3")
            import :: c_ptr, c_int64_t, c_double
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: i, j, k
            real(kind=c_double), value :: val
        end subroutine fj_set_real3

        ! --- Introspection ---
        function fj_length(obj) bind(c, name="fj_length") result(res)
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: obj
            integer(kind=c_int64_t) :: res
        end function fj_length

        function fj_ndims(obj) bind(c, name="fj_ndims") result(res)
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: obj
            integer(kind=c_int64_t) :: res
        end function fj_ndims

        function fj_size(obj, dim) bind(c, name="fj_size") result(res)
            import :: c_ptr, c_int64_t, c_int
            type(c_ptr), value :: obj
            integer(kind=c_int), value :: dim
            integer(kind=c_int64_t) :: res
        end function fj_size

        function fj_make_unitrange(start, stop) bind(c, name="fj_make_unitrange") result(res)
            import :: c_ptr, c_int64_t
            integer(kind=c_int64_t), value :: start, stop
            type(c_ptr) :: res
        end function fj_make_unitrange

    end interface

    contains
        
    function to_c_string(str) result(c_str)
        character(len=*), intent(in) :: str
        character(kind=c_char, len=len_trim(str)+1) :: c_str
        c_str = trim(str) // c_null_char
    end function to_c_string

end module julia_low_level
