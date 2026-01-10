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

        ! void* fj_get_function_pointer(const char* func_name);
        function fj_get_function_pointer(func_name) bind(c, name="fj_get_function_pointer") result(funptr)
            import :: c_char, c_funptr
            character(kind=c_char), dimension(*), intent(in) :: func_name
            type(c_funptr) :: funptr
        end function fj_get_function_pointer
        
        ! jl_value_t* fj_wrap_array_1d(void* data, int64_t length);
        function fj_wrap_array_1d(data, length) bind(c, name="fj_wrap_array_1d") result(res)
            import :: c_ptr, c_int64_t
            type(c_ptr), value :: data
            integer(kind=c_int64_t), value :: length
            type(c_ptr) :: res
        end function fj_wrap_array_1d

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
        ! procedure :: to_real
        final :: destructor
    end type JuliaValue

contains

    ! --- Lifecycle Management ---

    subroutine destructor(this)
        type(JuliaValue), intent(inout) :: this
        if (c_associated(this%ptr)) then
            ! print *, "[Fortran] Releasing Julia object..."
            call fj_release(this%ptr)
            this%ptr = c_null_ptr
        end if
    end subroutine destructor

    logical function is_valid(this)
        class(JuliaValue), intent(in) :: this
        is_valid = c_associated(this%ptr)
    end function is_valid

    ! --- High-Level Initialization ---
    
    subroutine julia_init()
        call fj_init(c_null_ptr)
    end subroutine julia_init

    subroutine julia_shutdown()
        call fj_shutdown()
    end subroutine julia_shutdown

    ! --- Generic Call Methods (Simplified Prototypes) ---

    ! Call a function that returns a new JuliaValue
    function call_method_0(self, func_name) result(res)
        class(JuliaValue), intent(in) :: self ! 'self' implies method call, but here we invoke global functions for now
        character(len=*), intent(in) :: func_name
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        
        ! Note: Self is unused here if we just call global functions, 
        ! but in real OOP, self would be the object to call method on.
        ! For this demo, we just wrap global calls.
        
        raw_res = fj_call0(to_c_string(func_name))
        
        ! Important: The result from C is a raw jl_value_t*.
        ! We must RETAIN it to make it a persistent Fortran-owned object.
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

end module julia_high_level
