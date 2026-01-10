module julia_low_level
    use iso_c_binding
    implicit none

    ! --- C Interface Definitions ---
    interface
        ! void fj_init(const char* image_path);
        subroutine fj_init(image_path) bind(c, name="fj_init")
            import :: c_char, c_ptr
            type(c_ptr), value :: image_path
        end subroutine fj_init

        ! void fj_shutdown();
        subroutine fj_shutdown() bind(c, name="fj_shutdown")
        end subroutine fj_shutdown

        ! void* fj_retain(jl_value_t* val);
        function fj_retain(val) bind(c, name="fj_retain") result(ptr)
            import :: c_ptr
            type(c_ptr), value :: val
            type(c_ptr) :: ptr
        end function fj_retain

        ! void fj_release(void* ptr);
        subroutine fj_release(ptr) bind(c, name="fj_release")
            import :: c_ptr
            type(c_ptr), value :: ptr
        end subroutine fj_release

        ! jl_value_t* fj_call0(const char* func_name);
        function fj_call0(func_name) bind(c, name="fj_call0") result(res)
            import :: c_char, c_ptr
            character(kind=c_char), dimension(*), intent(in) :: func_name
            type(c_ptr) :: res
        end function fj_call0

        ! jl_value_t* fj_call1_float64(const char* func_name, double arg1);
        function fj_call1_float64(func_name, arg1) bind(c, name="fj_call1_float64") result(res)
            import :: c_char, c_double, c_ptr
            character(kind=c_char), dimension(*), intent(in) :: func_name
            real(kind=c_double), value :: arg1
            type(c_ptr) :: res
        end function fj_call1_float64

        ! jl_value_t* fj_call1_obj(const char* func_name, void* arg_obj);
        function fj_call1_obj(func_name, arg_obj) bind(c, name="fj_call1_obj") result(res)
            import :: c_char, c_ptr
            character(kind=c_char), dimension(*), intent(in) :: func_name
            type(c_ptr), value :: arg_obj
            type(c_ptr) :: res
        end function fj_call1_obj

        ! jl_value_t* fj_call2_obj_double(const char* func_name, void* arg_obj, double arg2);
        function fj_call2_obj_double(func_name, arg_obj, arg2) bind(c, name="fj_call2_obj_double") result(res)
            import :: c_char, c_ptr, c_double
            character(kind=c_char), dimension(*), intent(in) :: func_name
            type(c_ptr), value :: arg_obj
            real(kind=c_double), value :: arg2
            type(c_ptr) :: res
        end function fj_call2_obj_double

        ! jl_value_t* fj_call_general(const char* func_name, void** args, int32_t nargs);
        function fj_call_general(func_name, args, nargs) bind(c, name="fj_call_general") result(res)
            import :: c_char, c_ptr, c_int32_t
            character(kind=c_char), dimension(*), intent(in) :: func_name
            type(c_ptr), dimension(*), intent(in) :: args
            integer(kind=c_int32_t), value :: nargs
            type(c_ptr) :: res
        end function fj_call_general

        ! jl_value_t* fj_eval_string(const char* cmd);
        function fj_eval_string(cmd) bind(c, name="fj_eval_string") result(res)
            import :: c_char, c_ptr
            character(kind=c_char), dimension(*), intent(in) :: cmd
            type(c_ptr) :: res
        end function fj_eval_string

        ! void* fj_get_function_pointer(const char* func_name, const char* ret_type, const char* arg_types);
        function fj_get_function_pointer(func_name, ret_type, arg_types) bind(c, name="fj_get_function_pointer") result(funptr)
            import :: c_char, c_funptr
            character(kind=c_char), dimension(*), intent(in) :: func_name
            character(kind=c_char), dimension(*), intent(in) :: ret_type
            character(kind=c_char), dimension(*), intent(in) :: arg_types
            type(c_funptr) :: funptr
        end function fj_get_function_pointer
        
        ! const char* fj_get_last_error();
        function fj_get_last_error() bind(c, name="fj_get_last_error") result(c_str)
            import :: c_ptr
            type(c_ptr) :: c_str
        end function fj_get_last_error
        
        ! jl_value_t* fj_wrap_array_1d(void* data, int64_t length);
        function fj_wrap_array_1d(data, length) bind(c, name="fj_wrap_array_1d") result(res)
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: data
            integer(kind=c_int64_t), value :: length
            type(c_ptr) :: res
        end function fj_wrap_array_1d

        ! jl_value_t* fj_wrap_array_2d(void* data, int64_t rows, int64_t cols);
        function fj_wrap_array_2d(data, rows, cols) bind(c, name="fj_wrap_array_2d") result(res)
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: data
            integer(kind=c_int64_t), value :: rows, cols
            type(c_ptr) :: res
        end function fj_wrap_array_2d

        ! jl_value_t* fj_box_float64(double val);
        function fj_box_float64(val) bind(c, name="fj_box_float64") result(res)
            import :: c_ptr, c_double
            real(kind=c_double), value :: val
            type(c_ptr) :: res
        end function fj_box_float64

    end interface

    ! --- Helpers for Strings ---
    contains
        
    function to_c_string(str) result(c_str)
        character(len=*), intent(in) :: str
        character(kind=c_char, len=len_trim(str)+1) :: c_str
        c_str = trim(str) // c_null_char
    end function to_c_string

end module julia_low_level


module julia_high_level
    use iso_c_binding
    use julia_low_level
    implicit none

    ! --- The Julia Object Wrapper (OOP) ---
    type :: JuliaValue
        type(c_ptr) :: ptr = c_null_ptr
    contains
        procedure :: is_valid
        procedure :: call_method_0
        procedure :: call_method_1_real
        procedure :: call_method_1_obj
        procedure :: call_method_2_obj_real
        procedure :: call_method_generic
        ! procedure :: to_real
        final :: destructor
    end type JuliaValue

    interface
        function strlen(s) bind(c, name="strlen")
            import :: c_ptr, c_size_t
            type(c_ptr), value :: s
            integer(kind=c_size_t) :: strlen
        end function strlen
    end interface

contains

    ! --- Implementation ---
    
    subroutine destructor(self)
        type(JuliaValue), intent(inout) :: self
        if (c_associated(self%ptr)) then
            call fj_release(self%ptr)
            self%ptr = c_null_ptr
        end if
    end subroutine destructor

    function call_method_generic(self, func_name, args) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: func_name
        type(JuliaValue), dimension(:), intent(in) :: args
        type(JuliaValue) :: res
        type(c_ptr), allocatable :: ptrs(:)
        type(c_ptr) :: raw_res
        integer :: i, n
        
        n = size(args)
        allocate(ptrs(n))
        do i = 1, n
            ptrs(i) = args(i)%ptr
        end do
        
        raw_res = fj_call_general(to_c_string(func_name), ptrs, int(n, c_int32_t))
        res%ptr = fj_retain(raw_res)
    end function call_method_generic

    function is_valid(self)
        class(JuliaValue), intent(in) :: self
        logical :: is_valid
        is_valid = c_associated(self%ptr)
    end function is_valid

    ! --- High-Level Initialization ---
    
    subroutine julia_init()
        call fj_init(c_null_ptr)
    end subroutine julia_init

    subroutine julia_init_with_image(image_path)
        character(len=*), intent(in) :: image_path
        character(kind=c_char, len=len_trim(image_path)+1), target :: c_path
        
        c_path = trim(image_path) // c_null_char
        call fj_init(c_loc(c_path))
    end subroutine julia_init_with_image

    subroutine julia_shutdown()
        call fj_shutdown()
    end subroutine julia_shutdown

    subroutine julia_eval_string(cmd)
        character(len=*), intent(in) :: cmd
        type(c_ptr) :: raw_res
        
        raw_res = fj_eval_string(to_c_string(cmd))
    end subroutine julia_eval_string

    ! --- Error Handling ---

    function get_last_error_message() result(msg)
        character(len=:), allocatable :: msg
        type(c_ptr) :: c_str
        character(kind=c_char), pointer :: f_char_ptr(:)
        integer :: i, length
        
        c_str = fj_get_last_error()
        if (.not. c_associated(c_str)) then
             msg = "Unknown Error (NULL)"
             return
        end if
        
        call c_f_pointer(c_str, f_char_ptr, [2048]) 
        
        length = 0
        do i = 1, 2048
            if (f_char_ptr(i) == c_null_char) then
                length = i - 1
                exit
            end if
        end do
        
        allocate(character(len=length) :: msg)
        do i = 1, length
            msg(i:i) = f_char_ptr(i)
        end do
    end function get_last_error_message

    ! --- Fast Path Wrapper ---

    function get_function_pointer(func_name, ret_type, arg_types) result(funptr)
        character(len=*), intent(in) :: func_name, ret_type, arg_types
        type(c_funptr) :: funptr
        
        funptr = fj_get_function_pointer(to_c_string(func_name), &
                                         to_c_string(ret_type), &
                                         to_c_string(arg_types))
    end function get_function_pointer

    ! --- Generic Call Methods (Simplified Prototypes) ---

    function call_method_0(self, func_name) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: func_name
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        
        raw_res = fj_call0(to_c_string(func_name))
        res%ptr = fj_retain(raw_res)
    end function call_method_0

    function call_method_1_real(self, func_name, arg1) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: func_name
        real(kind=c_double), intent(in) :: arg1
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        
        raw_res = fj_call1_float64(to_c_string(func_name), arg1)
        res%ptr = fj_retain(raw_res)
    end function call_method_1_real

    function call_method_1_obj(self, func_name, arg_obj) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: func_name
        type(JuliaValue), intent(in) :: arg_obj
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        
        raw_res = fj_call1_obj(to_c_string(func_name), arg_obj%ptr)
        res%ptr = fj_retain(raw_res)
    end function call_method_1_obj

    function call_method_2_obj_real(self, func_name, arg_obj, arg2) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: func_name
        type(JuliaValue), intent(in) :: arg_obj
        real(kind=c_double), intent(in) :: arg2
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        
        raw_res = fj_call2_obj_double(to_c_string(func_name), arg_obj%ptr, arg2)
        res%ptr = fj_retain(raw_res)
    end function call_method_2_obj_real

    function julia_box_real(val) result(res)
        real(kind=c_double), intent(in) :: val
        type(JuliaValue) :: res
        type(c_ptr) :: raw_ptr
        raw_ptr = fj_box_float64(val)
        res%ptr = fj_retain(raw_ptr)
    end function julia_box_real

end module julia_high_level