module julia_low_level
    use iso_c_binding
    implicit none

    ! Mirrors C struct fcj_options_t (bridge.h); field order and types must match.
    ! handle_signals: 0 = "no takeover" (the C-side DEFAULT; after init
    !   SIGINT/SIGTERM are reset to SIG_DFL, GC-critical handlers stay
    !   intact), nonzero = leave Julia's signal handlers in place
    !   (historical behavior). jl_options.handle_signals is never touched.
    type, bind(c) :: FjOptions
        type(c_ptr) :: sysimage_path
        type(c_ptr) :: project_path
        integer(kind=c_int) :: nthreads
        integer(kind=c_int) :: handle_signals
    end type FjOptions

    ! --- C Interface Definitions ---
    interface
        subroutine fcj_init(image_path) bind(c, name="fcj_init")
            import :: c_char, c_ptr
            type(c_ptr), value :: image_path
        end subroutine fcj_init

        subroutine fcj_init_ex(opts) bind(c, name="fcj_init_ex")
            import :: c_ptr
            type(c_ptr), value :: opts
        end subroutine fcj_init_ex

        subroutine fcj_shutdown() bind(c, name="fcj_shutdown")
        end subroutine fcj_shutdown

        function fcj_retain(val) bind(c, name="fcj_retain") result(ptr)
            import :: c_ptr
            type(c_ptr), value :: val
            type(c_ptr) :: ptr
        end function fcj_retain

        subroutine fcj_release(ptr) bind(c, name="fcj_release")
            import :: c_ptr
            type(c_ptr), value :: ptr
        end subroutine fcj_release

        function fcj_call0(func_name) bind(c, name="fcj_call0") result(res)
            import :: c_char, c_ptr
            character(kind=c_char), dimension(*), intent(in) :: func_name
            type(c_ptr) :: res
        end function fcj_call0

        function fcj_call1_float64(func_name, arg1) bind(c, name="fcj_call1_float64") result(res)
            import :: c_char, c_double, c_ptr
            character(kind=c_char), dimension(*), intent(in) :: func_name
            real(kind=c_double), value :: arg1
            type(c_ptr) :: res
        end function fcj_call1_float64

        function fcj_call1_obj(func_name, arg_obj) bind(c, name="fcj_call1_obj") result(res)
            import :: c_char, c_ptr
            character(kind=c_char), dimension(*), intent(in) :: func_name
            type(c_ptr), value :: arg_obj
            type(c_ptr) :: res
        end function fcj_call1_obj

        function fcj_call2_obj_double(func_name, arg_obj, arg2) bind(c, name="fcj_call2_obj_double") result(res)
            import :: c_char, c_ptr, c_double
            character(kind=c_char), dimension(*), intent(in) :: func_name
            type(c_ptr), value :: arg_obj
            real(kind=c_double), value :: arg2
            type(c_ptr) :: res
        end function fcj_call2_obj_double

        function fcj_call_general(func_name, args, nargs) bind(c, name="fcj_call_general") result(res)
            import :: c_char, c_ptr, c_int32_t
            character(kind=c_char), dimension(*), intent(in) :: func_name
            type(c_ptr), dimension(*), intent(in) :: args
            integer(kind=c_int32_t), value :: nargs
            type(c_ptr) :: res
        end function fcj_call_general

        function fcj_call_kwargs(func_name, args, nargs, kw_keys, kw_vals, nkw) bind(c, name="fcj_call_kwargs") result(res)
            import :: c_char, c_ptr, c_int32_t
            character(kind=c_char), dimension(*), intent(in) :: func_name
            type(c_ptr), dimension(*), intent(in) :: args
            integer(kind=c_int32_t), value :: nargs
            type(c_ptr), dimension(*), intent(in) :: kw_keys
            type(c_ptr), dimension(*), intent(in) :: kw_vals
            integer(kind=c_int32_t), value :: nkw
            type(c_ptr) :: res
        end function fcj_call_kwargs

        ! --- Cached Function Handles ---
        function fcj_resolve_function(name) bind(c, name="fcj_resolve_function") result(res)
            import :: c_char, c_ptr
            character(kind=c_char), dimension(*), intent(in) :: name
            type(c_ptr) :: res
        end function fcj_resolve_function

        function fcj_call_function(func, args, nargs) bind(c, name="fcj_call_function") result(res)
            import :: c_ptr, c_int32_t
            type(c_ptr), value :: func
            type(c_ptr), dimension(*), intent(in) :: args
            integer(kind=c_int32_t), value :: nargs
            type(c_ptr) :: res
        end function fcj_call_function

        function fcj_is_function(handle) bind(c, name="fcj_is_function") result(is)
            import :: c_ptr, c_int
            type(c_ptr), value :: handle
            integer(kind=c_int) :: is
        end function fcj_is_function

        ! Drops the C-side function-name cache (freeing its keys and
        ! releasing its GC roots) and tombstones the Julia-side kwargs
        ! cache hook. fcj_eval_string does this automatically after every
        ! successful eval; this binding exists for explicit control.
        subroutine fcj_clear_function_cache() bind(c, name="fcj_clear_function_cache")
        end subroutine fcj_clear_function_cache

        function fcj_eval_string(cmd) bind(c, name="fcj_eval_string") result(res)
            import :: c_char, c_ptr
            character(kind=c_char), dimension(*), intent(in) :: cmd
            type(c_ptr) :: res
        end function fcj_eval_string

        function fcj_get_function_pointer(func_name, ret_type, arg_types) bind(c, name="fcj_get_function_pointer") result(funptr)
            import :: c_char, c_funptr
            character(kind=c_char), dimension(*), intent(in) :: func_name
            character(kind=c_char), dimension(*), intent(in) :: ret_type
            character(kind=c_char), dimension(*), intent(in) :: arg_types
            type(c_funptr) :: funptr
        end function fcj_get_function_pointer
        
        function fcj_get_last_error() bind(c, name="fcj_get_last_error") result(c_str)
            import :: c_ptr
            type(c_ptr) :: c_str
        end function fcj_get_last_error

        function fcj_get_executable_dir(buf, bufsize) bind(c, name="fcj_get_executable_dir") result(res)
            import :: c_char, c_size_t, c_ptr
            character(kind=c_char), dimension(*), intent(out) :: buf
            integer(kind=c_size_t), value :: bufsize
            type(c_ptr) :: res
        end function fcj_get_executable_dir
        
        ! --- Array Wrapper & Deep Copy (rank-generic) ---
        ! dims holds ndim extents in Fortran dimension order; assumed-size so
        ! any actual argument section dims(1:nd) matches.
        function fcj_wrap_array(data, ndim, dims) bind(c, name="fcj_wrap_array") result(res)
            import :: c_ptr, c_long
            type(c_ptr), value :: data
            integer(kind=c_long), value :: ndim
            integer(kind=c_long), intent(in) :: dims(*)
            type(c_ptr) :: res
        end function fcj_wrap_array

        function fcj_copy_array(data, ndim, dims) bind(c, name="fcj_copy_array") result(res)
            import :: c_ptr, c_long
            type(c_ptr), value :: data
            integer(kind=c_long), value :: ndim
            integer(kind=c_long), intent(in) :: dims(*)
            type(c_ptr) :: res
        end function fcj_copy_array

        ! --- Accessors ---
        function fcj_box_float64(val) bind(c, name="fcj_box_float64") result(res)
            import :: c_ptr, c_double
            real(kind=c_double), value :: val
            type(c_ptr) :: res
        end function fcj_box_float64

        function fcj_box_int64(val) bind(c, name="fcj_box_int64") result(res)
            import :: c_ptr, c_int64_t
            integer(kind=c_int64_t), value :: val
            type(c_ptr) :: res
        end function fcj_box_int64

        function fcj_box_int32(val) bind(c, name="fcj_box_int32") result(res)
            import :: c_ptr, c_int32_t
            integer(kind=c_int32_t), value :: val
            type(c_ptr) :: res
        end function fcj_box_int32

        function fcj_box_bool(val) bind(c, name="fcj_box_bool") result(res)
            import :: c_ptr, c_int
            integer(kind=c_int), value :: val
            type(c_ptr) :: res
        end function fcj_box_bool

        function fcj_box_string(val) bind(c, name="fcj_box_string") result(res)
            import :: c_ptr, c_char
            character(kind=c_char), dimension(*), intent(in) :: val
            type(c_ptr) :: res
        end function fcj_box_string

        function fcj_box_complex(re, im) bind(c, name="fcj_box_complex") result(res)
            import :: c_ptr, c_double
            real(kind=c_double), value :: re, im
            type(c_ptr) :: res
        end function fcj_box_complex

        ! --- Unboxing ---
        function fcj_unbox_float64(obj) bind(c, name="fcj_unbox_float64") result(val)
            import :: c_ptr, c_double
            type(c_ptr), value :: obj
            real(kind=c_double) :: val
        end function fcj_unbox_float64

        function fcj_unbox_int64(obj) bind(c, name="fcj_unbox_int64") result(val)
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: obj
            integer(kind=c_int64_t) :: val
        end function fcj_unbox_int64

        function fcj_unbox_int32(obj) bind(c, name="fcj_unbox_int32") result(val)
            import :: c_ptr, c_int32_t
            type(c_ptr), value :: obj
            integer(kind=c_int32_t) :: val
        end function fcj_unbox_int32

        function fcj_unbox_bool(obj) bind(c, name="fcj_unbox_bool") result(val)
            import :: c_ptr, c_int
            type(c_ptr), value :: obj
            integer(kind=c_int) :: val
        end function fcj_unbox_bool

        function fcj_unbox_string(obj) bind(c, name="fcj_unbox_string") result(c_str)
            import :: c_ptr
            type(c_ptr), value :: obj
            type(c_ptr) :: c_str
        end function fcj_unbox_string

        function fcj_unbox_complex_real(obj) bind(c, name="fcj_unbox_complex_real") result(val)
            import :: c_ptr, c_double
            type(c_ptr), value :: obj
            real(kind=c_double) :: val
        end function fcj_unbox_complex_real

        function fcj_unbox_complex_imag(obj) bind(c, name="fcj_unbox_complex_imag") result(val)
            import :: c_ptr, c_double
            type(c_ptr), value :: obj
            real(kind=c_double) :: val
        end function fcj_unbox_complex_imag

        ! --- Accessors ---
        function fcj_get_field(obj, name) bind(c, name="fcj_get_field") result(res)
            import :: c_ptr, c_char
            type(c_ptr), value :: obj
            character(kind=c_char), dimension(*), intent(in) :: name
            type(c_ptr) :: res
        end function fcj_get_field

        subroutine fcj_set_field(obj, name, val) bind(c, name="fcj_set_field")
            import :: c_ptr, c_char
            type(c_ptr), value :: obj
            character(kind=c_char), dimension(*), intent(in) :: name
            type(c_ptr), value :: val
        end subroutine fcj_set_field

        function fcj_get_index_i(obj, idx) bind(c, name="fcj_get_index_i") result(res)
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: idx
            type(c_ptr) :: res
        end function fcj_get_index_i

        subroutine fcj_set_index_i(obj, idx, val) bind(c, name="fcj_set_index_i")
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: idx
            type(c_ptr), value :: val
        end subroutine fcj_set_index_i

        ! --- Extended Accessors ---
        function fcj_get_index_ii(obj, i, j) bind(c, name="fcj_get_index_ii") result(res)
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: i, j
            type(c_ptr) :: res
        end function fcj_get_index_ii

        subroutine fcj_set_index_ii(obj, i, j, val) bind(c, name="fcj_set_index_ii")
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: i, j
            type(c_ptr), value :: val
        end subroutine fcj_set_index_ii

        function fcj_get_index_iii(obj, i, j, k) bind(c, name="fcj_get_index_iii") result(res)
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: i, j, k
            type(c_ptr) :: res
        end function fcj_get_index_iii

        subroutine fcj_set_index_iii(obj, i, j, k, val) bind(c, name="fcj_set_index_iii")
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: i, j, k
            type(c_ptr), value :: val
        end subroutine fcj_set_index_iii

        function fcj_get_index_s(obj, key) bind(c, name="fcj_get_index_s") result(res)
            import :: c_ptr, c_char
            type(c_ptr), value :: obj
            character(kind=c_char), dimension(*), intent(in) :: key
            type(c_ptr) :: res
        end function fcj_get_index_s

        subroutine fcj_set_index_s(obj, key, val) bind(c, name="fcj_set_index_s")
            import :: c_ptr, c_char
            type(c_ptr), value :: obj
            character(kind=c_char), dimension(*), intent(in) :: key
            type(c_ptr), value :: val
        end subroutine fcj_set_index_s

        ! --- Fast Real Element Accessors ---
        function fcj_get_real(obj, idx) bind(c, name="fcj_get_real") result(val)
            import :: c_ptr, c_int64_t, c_double
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: idx
            real(kind=c_double) :: val
        end function fcj_get_real

        subroutine fcj_set_real(obj, idx, val) bind(c, name="fcj_set_real")
            import :: c_ptr, c_int64_t, c_double
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: idx
            real(kind=c_double), value :: val
        end subroutine fcj_set_real

        function fcj_get_real2(obj, i, j) bind(c, name="fcj_get_real2") result(val)
            import :: c_ptr, c_int64_t, c_double
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: i, j
            real(kind=c_double) :: val
        end function fcj_get_real2

        subroutine fcj_set_real2(obj, i, j, val) bind(c, name="fcj_set_real2")
            import :: c_ptr, c_int64_t, c_double
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: i, j
            real(kind=c_double), value :: val
        end subroutine fcj_set_real2

        function fcj_get_real3(obj, i, j, k) bind(c, name="fcj_get_real3") result(val)
            import :: c_ptr, c_int64_t, c_double
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: i, j, k
            real(kind=c_double) :: val
        end function fcj_get_real3

        subroutine fcj_set_real3(obj, i, j, k, val) bind(c, name="fcj_set_real3")
            import :: c_ptr, c_int64_t, c_double
            type(c_ptr), value :: obj
            integer(kind=c_int64_t), value :: i, j, k
            real(kind=c_double), value :: val
        end subroutine fcj_set_real3

        ! --- Introspection ---
        function fcj_length(obj) bind(c, name="fcj_length") result(res)
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: obj
            integer(kind=c_int64_t) :: res
        end function fcj_length

        function fcj_ndims(obj) bind(c, name="fcj_ndims") result(res)
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: obj
            integer(kind=c_int64_t) :: res
        end function fcj_ndims

        function fcj_size(obj, dim) bind(c, name="fcj_size") result(res)
            import :: c_ptr, c_int64_t, c_int
            type(c_ptr), value :: obj
            integer(kind=c_int), value :: dim
            integer(kind=c_int64_t) :: res
        end function fcj_size

        function fcj_make_unitrange(start, stop) bind(c, name="fcj_make_unitrange") result(res)
            import :: c_ptr, c_int64_t
            integer(kind=c_int64_t), value :: start, stop
            type(c_ptr) :: res
        end function fcj_make_unitrange

        ! --- SciML Callbacks (Wave B) ---
        ! Wraps a Fortran bind(c) RHS into a Julia callable
        ! f(du, u, p, t) that ignores p and invokes the Fortran RHS
        ! through ccall (zero-copy raw element pointers; err /= 0
        ! throws on the Julia side). The result is routed through
        ! fcj_retain (C-side root set) and also bound to global
        ! Main.FJ_CALLBACK (latest created wins). NULL + last_error on
        ! failure.
        function fcj_create_callback(fnptr, ctx) bind(c, name="fcj_create_callback") result(res)
            import :: c_ptr
            type(c_ptr), value :: fnptr
            type(c_ptr), value :: ctx
            type(c_ptr) :: res
        end function fcj_create_callback

        ! --- Bulk Extraction (Wave B) ---
        ! Copies n elements of a dense Array{Float64} or
        ! Array{ComplexF64} (any rank) into dest (interpreted as a
        ! double / double-complex buffer of size n). Returns 0 on
        ! success; -1 + last_error if handle is not such an array or
        ! n /= length.
        function fcj_to_fortran(handle, dest, n) bind(c, name="fcj_to_fortran") result(rc)
            import :: c_ptr, c_int64_t, c_int
            type(c_ptr), value :: handle
            type(c_ptr), value :: dest
            integer(kind=c_int64_t), value :: n
            integer(kind=c_int) :: rc
        end function fcj_to_fortran

        ! 1-based array indexing; returns a RETAINED handle (jl_arrayref
        ! boxes numerics; retain through fcj_retain before it becomes
        ! reachable). NULL + last_error if not an array or idx out of
        ! bounds.
        function fcj_get_element(handle, idx) bind(c, name="fcj_get_element") result(res)
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: handle
            integer(kind=c_int64_t), value :: idx
            type(c_ptr) :: res
        end function fcj_get_element

        ! getproperty on the object; returns a RETAINED handle or
        ! NULL + last_error.
        function fcj_get_property(handle, name) bind(c, name="fcj_get_property") result(res)
            import :: c_ptr, c_char
            type(c_ptr), value :: handle
            character(kind=c_char), dimension(*), intent(in) :: name
            type(c_ptr) :: res
        end function fcj_get_property

    end interface

    contains
        
    function to_c_string(str) result(c_str)
        character(len=*), intent(in) :: str
        character(kind=c_char, len=len_trim(str)+1) :: c_str
        c_str = trim(str) // c_null_char
    end function to_c_string

end module julia_low_level
