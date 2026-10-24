module julia_high_level
    use iso_c_binding
    use, intrinsic :: iso_fortran_env, only: error_unit
    use julia_low_level
    implicit none

    type :: JuliaKwargs
        integer :: n = 0
        character(len=64), allocatable :: keys(:)
        type(JuliaValue), allocatable :: values(:)
    contains
        procedure :: add => add_kwarg
        final :: kw_destructor
    end type JuliaKwargs

    type :: JuliaValue
        type(c_ptr) :: ptr = c_null_ptr
    contains
        procedure :: is_valid
        procedure :: call_method_generic
        procedure :: call_with_kwargs
        ! Deprecated / Convenience methods
        procedure :: call_method_0
        procedure :: call_method_1_real
        procedure :: call_method_1_obj
        procedure :: call_method_2_obj_real
        ! Converters
        procedure :: as_integer => julia_to_integer
        procedure :: as_real => julia_to_real
        procedure :: as_logical => julia_to_logical
        procedure :: as_complex => julia_to_complex
        procedure :: as_string => julia_to_string
        ! Accessors
        procedure :: get_field
        procedure :: set_field
        
        procedure :: at_1d => at
        procedure :: set_at_1d => set_at
        
        procedure :: at_2d
        procedure :: set_at_2d
        procedure :: at_3d
        procedure :: set_at_3d
        procedure :: at_string
        procedure :: set_at_string
        
        generic :: at => at_1d, at_2d, at_3d, at_string
        generic :: set_at => set_at_1d, set_at_2d, set_at_3d, set_at_string

        ! Generic Call Interface (Modern Fortran)
        generic :: call => call_method_generic_dispatch_0, &
                           call_method_generic_dispatch_1, &
                           call_method_generic_dispatch_2, &
                           call_method_generic_dispatch_3, &
                           call_method_generic_dispatch_4
        
        procedure, private :: call_method_generic_dispatch_0
        procedure, private :: call_method_generic_dispatch_1
        procedure, private :: call_method_generic_dispatch_2
        procedure, private :: call_method_generic_dispatch_3
        procedure, private :: call_method_generic_dispatch_4
        
        ! Introspection
        procedure :: length
        procedure :: ndims
        procedure :: size_dim
        
        ! Assignment Overload for Ref Counting
        generic :: assignment(=) => copy_julia_value
        procedure :: copy_julia_value
        final :: destructor
    end type JuliaValue

    interface julia_wrap_array
        module procedure julia_wrap_array_1d
        module procedure julia_wrap_array_2d
        module procedure julia_wrap_array_3d
    end interface

    interface julia_copy_array
        module procedure julia_copy_array_1d
        module procedure julia_copy_array_2d
        module procedure julia_copy_array_3d
    end interface

    interface
        function strlen(s) bind(c, name="strlen") result(res)
            import :: c_ptr, c_size_t
            type(c_ptr), value :: s
            integer(kind=c_size_t) :: res
        end function strlen
    end interface

contains

    ! --- Introspection Helpers ---
    
    function julia_range(start, stop) result(res)
        integer(kind=c_int64_t), intent(in) :: start, stop
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        raw_res = fj_make_unitrange(start, stop)
        res%ptr = fj_retain(raw_res)
    end function julia_range

    ! --- Internal Management ---
    
    subroutine copy_julia_value(dest, src)
        class(JuliaValue), intent(out) :: dest
        class(JuliaValue), intent(in) :: src
        type(c_ptr) :: dummy
        
        dest%ptr = src%ptr
        if (c_associated(dest%ptr)) then
            dummy = fj_retain(dest%ptr)
        end if
    end subroutine copy_julia_value

    subroutine destructor(self)
        type(JuliaValue), intent(inout) :: self
        if (c_associated(self%ptr)) then
            call fj_release(self%ptr)
            self%ptr = c_null_ptr
        end if
    end subroutine destructor

    ! --- Method Dispatch ---

    function call_method_generic(self, func_name, args) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: func_name
        type(JuliaValue), dimension(:), intent(in) :: args
        type(JuliaValue) :: res
        type(c_ptr), allocatable :: ptrs(:)
        type(c_ptr) :: raw_res
        integer :: i, n
        
        n = size(args)
        if (n > 0) then
            allocate(ptrs(n))
            do i = 1, n
                ptrs(i) = args(i)%ptr
            end do
            raw_res = fj_call_general(to_c_string(func_name), ptrs, int(n, c_int32_t))
            deallocate(ptrs)
        else
            raw_res = fj_call0(to_c_string(func_name))
        end if
        res%ptr = fj_retain(raw_res)
    end function call_method_generic

    function is_valid(self)
        class(JuliaValue), intent(in) :: self
        logical :: is_valid
        is_valid = c_associated(self%ptr)
    end function is_valid

    ! --- Converters ---
    
    function julia_to_integer(self) result(val)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t) :: val
        val = fj_unbox_int64(self%ptr)
    end function julia_to_integer

    function julia_to_real(self) result(val)
        class(JuliaValue), intent(in) :: self
        real(kind=c_double) :: val
        val = fj_unbox_float64(self%ptr)
    end function julia_to_real

    function julia_to_logical(self) result(val)
        class(JuliaValue), intent(in) :: self
        logical :: val
        val = (fj_unbox_bool(self%ptr) /= 0)
    end function julia_to_logical
    
    function julia_to_complex(self) result(val)
        class(JuliaValue), intent(in) :: self
        complex(kind=c_double) :: val
        real(kind=c_double) :: r, i
        r = fj_unbox_complex_real(self%ptr)
        i = fj_unbox_complex_imag(self%ptr)
        val = cmplx(r, i, c_double)
    end function julia_to_complex

    function julia_to_string(self) result(msg)
        class(JuliaValue), intent(in) :: self
        character(len=:), allocatable :: msg
        type(c_ptr) :: c_str
        character(kind=c_char), pointer :: f_char_ptr(:)
        integer :: i, length
        
        c_str = fj_unbox_string(self%ptr)
        if (.not. c_associated(c_str)) then
             msg = ""
             return
        end if
        
        length = int(strlen(c_str))
        call c_f_pointer(c_str, f_char_ptr, [length]) 
        
        allocate(character(len=length) :: msg)
        do i = 1, length
            msg(i:i) = f_char_ptr(i)
        end do
    end function julia_to_string

    ! --- Boxing (Scalars) ---

    function julia_box_real(val) result(res)
        real(kind=c_double), intent(in) :: val
        type(JuliaValue) :: res
        type(c_ptr) :: raw_ptr
        raw_ptr = fj_box_float64(val)
        res%ptr = fj_retain(raw_ptr)
    end function julia_box_real

    function julia_box_integer(val) result(res)
        integer(kind=c_int64_t), intent(in) :: val
        type(JuliaValue) :: res
        type(c_ptr) :: raw_ptr
        raw_ptr = fj_box_int64(val)
        res%ptr = fj_retain(raw_ptr)
    end function julia_box_integer
    
    function julia_box_logical(val) result(res)
        logical, intent(in) :: val
        type(JuliaValue) :: res
        type(c_ptr) :: raw_ptr
        integer(c_int) :: c_bool
        if (val) then
            c_bool = 1
        else
            c_bool = 0
        end if
        raw_ptr = fj_box_bool(c_bool)
        res%ptr = fj_retain(raw_ptr)
    end function julia_box_logical

    function julia_box_string(val) result(res)
        character(len=*), intent(in) :: val
        type(JuliaValue) :: res
        type(c_ptr) :: raw_ptr
        raw_ptr = fj_box_string(to_c_string(val))
        res%ptr = fj_retain(raw_ptr)
    end function julia_box_string

    function julia_box_complex(val) result(res)
        complex(kind=c_double), intent(in) :: val
        type(JuliaValue) :: res
        type(c_ptr) :: raw_ptr
        raw_ptr = fj_box_complex(dble(val), aimag(val))
        res%ptr = fj_retain(raw_ptr)
    end function julia_box_complex

    ! --- Array Wrappers (Zero-Copy) ---
    
    function julia_wrap_array_1d(arr, length) result(res)
        real(kind=c_double), target, intent(in) :: arr(:)
        integer(kind=c_int64_t), intent(in) :: length
        type(JuliaValue) :: res
        type(c_ptr) :: raw_ptr, data_ptr
        if (length /= size(arr, dim=1, kind=c_int64_t)) then
            write(error_unit, '(A,I0,A,I0,A)') &
                'julia_wrap_array_1d: length (', length, ') /= size(arr,1) (', &
                size(arr, dim=1, kind=c_int64_t), '); returning invalid JuliaValue'
            res%ptr = c_null_ptr
            return
        end if
        if (.not. is_contiguous(arr)) then
            write(error_unit, '(A)') &
                'julia_wrap_array_1d: arr is not contiguous; zero-copy wrap rejected; ' // &
                'returning invalid JuliaValue'
            res%ptr = c_null_ptr
            return
        end if
        data_ptr = c_loc(arr)
        raw_ptr = fj_wrap_array_1d(data_ptr, length)
        res%ptr = fj_retain(raw_ptr)
    end function julia_wrap_array_1d

    function julia_wrap_array_2d(arr, d1, d2) result(res)
        real(kind=c_double), target, intent(in) :: arr(:,:)
        integer(kind=c_int64_t), intent(in) :: d1, d2
        type(JuliaValue) :: res
        type(c_ptr) :: raw_ptr, data_ptr
        if (d1 /= size(arr, dim=1, kind=c_int64_t) .or. &
            d2 /= size(arr, dim=2, kind=c_int64_t)) then
            write(error_unit, '(A,I0,A,I0,A,I0,A,I0,A)') &
                'julia_wrap_array_2d: dims (', d1, ', ', d2, ') /= size(arr) (', &
                size(arr, dim=1, kind=c_int64_t), ', ', size(arr, dim=2, kind=c_int64_t), &
                '); returning invalid JuliaValue'
            res%ptr = c_null_ptr
            return
        end if
        if (.not. is_contiguous(arr)) then
            write(error_unit, '(A)') &
                'julia_wrap_array_2d: arr is not contiguous; zero-copy wrap rejected; ' // &
                'returning invalid JuliaValue'
            res%ptr = c_null_ptr
            return
        end if
        data_ptr = c_loc(arr)
        raw_ptr = fj_wrap_array_2d(data_ptr, d1, d2)
        res%ptr = fj_retain(raw_ptr)
    end function julia_wrap_array_2d

    function julia_wrap_array_3d(arr, d1, d2, d3) result(res)
        real(kind=c_double), target, intent(in) :: arr(:,:,:)
        integer(kind=c_int64_t), intent(in) :: d1, d2, d3
        type(JuliaValue) :: res
        type(c_ptr) :: raw_ptr, data_ptr
        if (d1 /= size(arr, dim=1, kind=c_int64_t) .or. &
            d2 /= size(arr, dim=2, kind=c_int64_t) .or. &
            d3 /= size(arr, dim=3, kind=c_int64_t)) then
            write(error_unit, '(A,I0,A,I0,A,I0,A,I0,A,I0,A)') &
                'julia_wrap_array_3d: dims (', d1, ', ', d2, ', ', d3, ') /= size(arr) (', &
                size(arr, dim=1, kind=c_int64_t), ', ', size(arr, dim=2, kind=c_int64_t), &
                ', ', size(arr, dim=3, kind=c_int64_t), '); returning invalid JuliaValue'
            res%ptr = c_null_ptr
            return
        end if
        if (.not. is_contiguous(arr)) then
            write(error_unit, '(A)') &
                'julia_wrap_array_3d: arr is not contiguous; zero-copy wrap rejected; ' // &
                'returning invalid JuliaValue'
            res%ptr = c_null_ptr
            return
        end if
        data_ptr = c_loc(arr)
        raw_ptr = fj_wrap_array_3d(data_ptr, d1, d2, d3)
        res%ptr = fj_retain(raw_ptr)
    end function julia_wrap_array_3d

    ! --- Array Deep Copies (Alloc + Memcpy) ---

    function julia_copy_array_1d(arr) result(res)
        real(c_double), target, intent(in) :: arr(:)
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        integer(kind=c_long) :: dim1
        dim1 = size(arr, kind=c_long)
        raw_res = fj_copy_array_1d(c_loc(arr), dim1)
        res%ptr = fj_retain(raw_res)
    end function julia_copy_array_1d

    function julia_copy_array_2d(arr) result(res)
        real(c_double), target, intent(in) :: arr(:,:)
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        integer(kind=c_long) :: dim1, dim2
        dim1 = size(arr, 1, kind=c_long)
        dim2 = size(arr, 2, kind=c_long)
        raw_res = fj_copy_array_2d(c_loc(arr), dim1, dim2)
        res%ptr = fj_retain(raw_res)
    end function julia_copy_array_2d

    function julia_copy_array_3d(arr) result(res)
        real(c_double), target, intent(in) :: arr(:,:,:)
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        integer(kind=c_long) :: dim1, dim2, dim3
        dim1 = size(arr, 1, kind=c_long)
        dim2 = size(arr, 2, kind=c_long)
        dim3 = size(arr, 3, kind=c_long)
        raw_res = fj_copy_array_3d(c_loc(arr), dim1, dim2, dim3)
        res%ptr = fj_retain(raw_res)
    end function julia_copy_array_3d

    ! --- Init / Shutdown / Util ---
    
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

    function julia_eval(cmd) result(res)
        character(len=*), intent(in) :: cmd
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        raw_res = fj_eval_string(to_c_string(cmd))
        res%ptr = fj_retain(raw_res)
    end function julia_eval

    function get_last_error_message() result(msg)
        character(len=:), allocatable :: msg
        type(c_ptr) :: c_str
        character(kind=c_char), pointer :: f_char_ptr(:)
        integer :: i, length
        c_str = fj_get_last_error()
        if (.not. c_associated(c_str)) then
             msg = "Unknown Error"
             return
        end if
        length = int(strlen(c_str))
        call c_f_pointer(c_str, f_char_ptr, [length]) 
        allocate(character(len=length) :: msg)
        do i = 1, length
            msg(i:i) = f_char_ptr(i)
        end do
    end function get_last_error_message

    function get_function_pointer(func_name, ret_type, arg_types) result(funptr)
        character(len=*), intent(in) :: func_name, ret_type, arg_types
        type(c_funptr) :: funptr
        funptr = fj_get_function_pointer(to_c_string(func_name), &
                                         to_c_string(ret_type), &
                                         to_c_string(arg_types))
        if (.not. c_associated(funptr)) then
            write(error_unit, '(A)') 'get_function_pointer: registration failed for "' // &
                trim(func_name) // '": ' // get_last_error_message()
        end if
    end function get_function_pointer
    
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

    ! --- Accessors ---

    function get_field(self, name) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: name
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        raw_res = fj_get_field(self%ptr, to_c_string(name))
        res%ptr = fj_retain(raw_res)
    end function get_field

    subroutine set_field(self, name, val)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: name
        type(JuliaValue), intent(in) :: val
        call fj_set_field(self%ptr, to_c_string(name), val%ptr)
    end subroutine set_field

    function at(self, idx) result(res)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t), intent(in) :: idx
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        raw_res = fj_get_index_i(self%ptr, idx)
        res%ptr = fj_retain(raw_res)
    end function at

    subroutine set_at(self, idx, val)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t), intent(in) :: idx
        type(JuliaValue), intent(in) :: val
        call fj_set_index_i(self%ptr, idx, val%ptr)
    end subroutine set_at

    function at_2d(self, i, j) result(res)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t), intent(in) :: i, j
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        raw_res = fj_get_index_ii(self%ptr, i, j)
        res%ptr = fj_retain(raw_res)
    end function at_2d

    subroutine set_at_2d(self, i, j, val)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t), intent(in) :: i, j
        type(JuliaValue), intent(in) :: val
        call fj_set_index_ii(self%ptr, i, j, val%ptr)
    end subroutine set_at_2d

    function at_3d(self, i, j, k) result(res)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t), intent(in) :: i, j, k
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        raw_res = fj_get_index_iii(self%ptr, i, j, k)
        res%ptr = fj_retain(raw_res)
    end function at_3d

    subroutine set_at_3d(self, i, j, k, val)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t), intent(in) :: i, j, k
        type(JuliaValue), intent(in) :: val
        call fj_set_index_iii(self%ptr, i, j, k, val%ptr)
    end subroutine set_at_3d

    function at_string(self, key) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: key
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        raw_res = fj_get_index_s(self%ptr, to_c_string(key))
        res%ptr = fj_retain(raw_res)
    end function at_string

    subroutine set_at_string(self, key, val)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: key
        type(JuliaValue), intent(in) :: val
        call fj_set_index_s(self%ptr, to_c_string(key), val%ptr)
    end subroutine set_at_string

    function length(self) result(res)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t) :: res
        res = fj_length(self%ptr)
    end function length

    function ndims(self) result(res)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t) :: res
        res = fj_ndims(self%ptr)
    end function ndims

    function size_dim(self, dim) result(res)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int), intent(in) :: dim
        integer(kind=c_int64_t) :: res
        res = fj_size(self%ptr, dim)
    end function size_dim

    ! --- Kwargs Support ---

    subroutine add_kwarg(self, key, val)
        class(JuliaKwargs), intent(inout) :: self
        character(len=*), intent(in) :: key
        type(JuliaValue), intent(in) :: val
        type(JuliaValue), allocatable :: new_vals(:)
        character(len=64), allocatable :: new_keys(:)
        integer :: i
        if (.not. allocated(self%keys)) then
            allocate(self%keys(1))
            allocate(self%values(1))
            self%n = 0
        else
            allocate(new_keys(self%n + 1))
            allocate(new_vals(self%n + 1))
            do i = 1, self%n
                new_keys(i) = self%keys(i)
                new_vals(i) = self%values(i)
            end do
            call move_alloc(new_keys, self%keys)
            call move_alloc(new_vals, self%values)
        end if
        self%n = self%n + 1
        self%keys(self%n) = key
        self%values(self%n) = val
    end subroutine add_kwarg

    subroutine kw_destructor(self)
        type(JuliaKwargs), intent(inout) :: self
        if (allocated(self%keys)) deallocate(self%keys)
        if (allocated(self%values)) deallocate(self%values)
        self%n = 0
    end subroutine kw_destructor

    function call_with_kwargs(self, func_name, args, kw) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: func_name
        type(JuliaValue), dimension(:), intent(in) :: args
        type(JuliaKwargs), intent(in) :: kw
        type(JuliaValue) :: res
        type(c_ptr), allocatable :: ptrs(:)
        type(c_ptr), allocatable :: kw_ptrs(:)
        type(c_ptr), allocatable :: val_ptrs(:)
        type(c_ptr) :: raw_res
        character(kind=c_char, len=65), target, allocatable :: c_keys(:)
        integer :: i, n, nkw
        n = size(args); nkw = kw%n
        allocate(ptrs(max(1,n)))
        do i = 1, n; ptrs(i) = args(i)%ptr; end do
        allocate(kw_ptrs(max(1,nkw))); allocate(val_ptrs(max(1,nkw))); allocate(c_keys(max(1,nkw)))
        do i = 1, nkw
            c_keys(i) = trim(kw%keys(i)) // c_null_char
            kw_ptrs(i) = c_loc(c_keys(i))
            val_ptrs(i) = kw%values(i)%ptr
        end do
        raw_res = fj_call_kwargs(to_c_string(func_name), ptrs, int(n, c_int32_t), &
                                 kw_ptrs, val_ptrs, int(nkw, c_int32_t))
        deallocate(ptrs); deallocate(kw_ptrs); deallocate(val_ptrs); deallocate(c_keys)
        res%ptr = fj_retain(raw_res)
    end function call_with_kwargs

! end module julia_high_level (Moved to bottom)
    ! --- Private Helper for Generic Call ---

    function box_argument(arg) result(res)
        class(*), intent(in) :: arg
        type(JuliaValue) :: res
        type(c_ptr) :: tmp_ptr
        integer(c_int) :: c_bool
        
        select type (val => arg)
        type is (integer(kind=c_int64_t))
             tmp_ptr = fj_box_int64(val)
             res%ptr = fj_retain(tmp_ptr)
        type is (integer(kind=c_int32_t))
             tmp_ptr = fj_box_int32(val)
             res%ptr = fj_retain(tmp_ptr)
        type is (real(kind=c_double))
             tmp_ptr = fj_box_float64(val)
             res%ptr = fj_retain(tmp_ptr)
        type is (real(kind=c_float))
             tmp_ptr = fj_box_float64(dble(val))
             res%ptr = fj_retain(tmp_ptr)
        type is (logical)
            if (val) then
                c_bool = 1
            else
                c_bool = 0
            end if
            tmp_ptr = fj_box_bool(c_bool)
            res%ptr = fj_retain(tmp_ptr)
        type is (character(len=*))
             tmp_ptr = fj_box_string(to_c_string(val))
             res%ptr = fj_retain(tmp_ptr)
        type is (complex(kind=c_double))
             tmp_ptr = fj_box_complex(dble(val), aimag(val))
             res%ptr = fj_retain(tmp_ptr)
        class is (JuliaValue)
             if (c_associated(val%ptr)) then
                 res%ptr = fj_retain(val%ptr)
             else
                 res%ptr = c_null_ptr
             end if
        class default
             ! Fallback or Error. For now, we produce a null pointer which might crash or error in Julia.
             ! In a production system, we should log this.
             res%ptr = c_null_ptr
        end select
    end function box_argument

    ! --- Generic Call Dispatch Implementation ---

    function call_method_generic_dispatch_0(self, func_name) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: func_name
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        
        ! Reuse existing call0 logic but consistent with this new pattern
        raw_res = fj_call0(to_c_string(func_name))
        res%ptr = fj_retain(raw_res)
    end function call_method_generic_dispatch_0

    function call_method_generic_dispatch_1(self, func_name, arg1) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: func_name
        class(*), intent(in) :: arg1
        type(JuliaValue) :: res
        
        type(JuliaValue) :: boxed_args(1)
        type(c_ptr) :: raw_args(1)
        type(c_ptr) :: raw_res
        
        boxed_args(1) = box_argument(arg1)
        raw_args(1) = boxed_args(1)%ptr
        
        raw_res = fj_call_general(to_c_string(func_name), raw_args, 1_c_int32_t)
        res%ptr = fj_retain(raw_res)
    end function call_method_generic_dispatch_1

    function call_method_generic_dispatch_2(self, func_name, arg1, arg2) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: func_name
        class(*), intent(in) :: arg1, arg2
        type(JuliaValue) :: res
        
        type(JuliaValue) :: boxed_args(2)
        type(c_ptr) :: raw_args(2)
        type(c_ptr) :: raw_res
        
        boxed_args(1) = box_argument(arg1)
        boxed_args(2) = box_argument(arg2)
        
        raw_args(1) = boxed_args(1)%ptr
        raw_args(2) = boxed_args(2)%ptr
        
        raw_res = fj_call_general(to_c_string(func_name), raw_args, 2_c_int32_t)
        res%ptr = fj_retain(raw_res)
    end function call_method_generic_dispatch_2

    function call_method_generic_dispatch_3(self, func_name, arg1, arg2, arg3) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: func_name
        class(*), intent(in) :: arg1, arg2, arg3
        type(JuliaValue) :: res
        
        type(JuliaValue) :: boxed_args(3)
        type(c_ptr) :: raw_args(3)
        type(c_ptr) :: raw_res
        
        boxed_args(1) = box_argument(arg1)
        boxed_args(2) = box_argument(arg2)
        boxed_args(3) = box_argument(arg3)
        
        raw_args(1) = boxed_args(1)%ptr
        raw_args(2) = boxed_args(2)%ptr
        raw_args(3) = boxed_args(3)%ptr
        
        raw_res = fj_call_general(to_c_string(func_name), raw_args, 3_c_int32_t)
        res%ptr = fj_retain(raw_res)
    end function call_method_generic_dispatch_3

    function call_method_generic_dispatch_4(self, func_name, arg1, arg2, arg3, arg4) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: func_name
        class(*), intent(in) :: arg1, arg2, arg3, arg4
        type(JuliaValue) :: res
        
        type(JuliaValue) :: boxed_args(4)
        type(c_ptr) :: raw_args(4)
        type(c_ptr) :: raw_res
        
        boxed_args(1) = box_argument(arg1)
        boxed_args(2) = box_argument(arg2)
        boxed_args(3) = box_argument(arg3)
        boxed_args(4) = box_argument(arg4)
        
        raw_args(1) = boxed_args(1)%ptr
        raw_args(2) = boxed_args(2)%ptr
        raw_args(3) = boxed_args(3)%ptr
        raw_args(4) = boxed_args(4)%ptr
        
        raw_res = fj_call_general(to_c_string(func_name), raw_args, 4_c_int32_t)
        res%ptr = fj_retain(raw_res)
    end function call_method_generic_dispatch_4

end module julia_high_level
