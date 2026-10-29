module julia_high_level
    use iso_c_binding
    use, intrinsic :: iso_fortran_env, only: error_unit
    use julia_low_level
    implicit none
    private :: copy_jv

    type :: JuliaKwargs
        integer :: n = 0
        character(len=64), allocatable :: keys(:)
        type(JuliaValue), allocatable :: values(:)
    contains
        procedure :: add => add_kwarg
        final :: kw_destructor
    end type JuliaKwargs

    ! JuliaValue ownership rule: assignment (=) is a retaining copy
    ! (copy_jv: fcj_retain + pointer copy, pure C via the root set, no
    ! Julia round trip). The finalizer releases each owned reference
    ! exactly once.
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

        ! Fast real element accessors (no JuliaValue temp, no retain per element)
        procedure :: at_real_1d
        procedure :: at_real_2d
        procedure :: at_real_3d
        procedure :: set_at_real_1d
        procedure :: set_at_real_2d
        procedure :: set_at_real_3d
        generic :: at_real => at_real_1d, at_real_2d, at_real_3d
        generic :: set_at_real => set_at_real_1d, set_at_real_2d, set_at_real_3d

        ! SciML-style batch extraction (Wave B). to_fortran bulk copies
        ! a dense Float64 / ComplexF64 array into a Fortran buffer (the
        ! real / complex specifics resolve by the buffer type). element
        ! and property return handles already retained on the C side
        ! (fcj_get_element / fcj_get_property): on failure the handle is
        ! c_null_ptr (check is_valid / c_associated).
        generic :: to_fortran => to_fortran_real, to_fortran_complex
        procedure, private :: to_fortran_real
        procedure, private :: to_fortran_complex
        procedure :: element
        procedure :: property

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

        ! Cached Function-Object Calls
        generic :: call_value => call_value_0, call_value_1, call_value_2, call_value_3, call_value_4
        procedure, private :: call_value_0
        procedure, private :: call_value_1
        procedure, private :: call_value_2
        procedure, private :: call_value_3
        procedure, private :: call_value_4
        
        ! Introspection
        procedure :: length
        procedure :: ndims
        procedure :: size_dim
        
        ! Assignment Overload for Retaining-Copy Ref Counting
        generic :: assignment(=) => copy_julia_value
        procedure :: copy_julia_value
        final :: destructor
    end type JuliaValue

    ! julia_wrap_array / julia_copy_array are single rank-generic (assumed-
    ! rank) functions: dimensions are derived from size(arr, dim=k), so there
    ! are no caller-supplied extents to get wrong. Both accept any rank
    ! 1..FCJ_MAX_NDIM (16, mirrored from the C side) of contiguous Float64.

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
        raw_res = fcj_make_unitrange(start, stop)
        res%ptr = fcj_retain(raw_res)
    end function julia_range

    ! --- Internal Management ---
    
    ! Defined assignment = retaining copy via the C-side root set
! (fcj_retain is a pure C operation, no Julia round trip). Standard
! Fortran requires INTENT(IN) for the second dummy of a defined
! assignment, so true move semantics cannot be expressed here.
subroutine copy_julia_value(dest, src)
class(JuliaValue), intent(out) :: dest
class(JuliaValue), intent(in) :: src
call copy_jv(dest, src)
end subroutine copy_julia_value

    ! Real (retaining) copy of a JuliaValue reference.
    subroutine copy_jv(dst, src)
class(JuliaValue), intent(out) :: dst
class(JuliaValue), intent(in) :: src
if (c_associated(src%ptr)) then
dst%ptr = fcj_retain(src%ptr)
else
dst%ptr = c_null_ptr
end if
end subroutine copy_jv

    subroutine destructor(self)
        type(JuliaValue), intent(inout) :: self
        if (c_associated(self%ptr)) then
            call fcj_release(self%ptr)
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
            raw_res = fcj_call_general(to_c_string(func_name), ptrs, int(n, c_int32_t))
            deallocate(ptrs)
        else
            raw_res = fcj_call0(to_c_string(func_name))
        end if
        res%ptr = fcj_retain(raw_res)
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
        val = fcj_unbox_int64(self%ptr)
    end function julia_to_integer

    function julia_to_real(self) result(val)
        class(JuliaValue), intent(in) :: self
        real(kind=c_double) :: val
        val = fcj_unbox_float64(self%ptr)
    end function julia_to_real

    function julia_to_logical(self) result(val)
        class(JuliaValue), intent(in) :: self
        logical :: val
        val = (fcj_unbox_bool(self%ptr) /= 0)
    end function julia_to_logical
    
    function julia_to_complex(self) result(val)
        class(JuliaValue), intent(in) :: self
        complex(kind=c_double) :: val
        real(kind=c_double) :: r, i
        r = fcj_unbox_complex_real(self%ptr)
        i = fcj_unbox_complex_imag(self%ptr)
        val = cmplx(r, i, c_double)
    end function julia_to_complex

    function julia_to_string(self) result(msg)
        class(JuliaValue), intent(in) :: self
        character(len=:), allocatable :: msg
        type(c_ptr) :: c_str
        character(kind=c_char), pointer :: f_char_ptr(:)
        integer :: i, length
        
        c_str = fcj_unbox_string(self%ptr)
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
        raw_ptr = fcj_box_float64(val)
        res%ptr = fcj_retain(raw_ptr)
    end function julia_box_real

    function julia_box_integer(val) result(res)
        integer(kind=c_int64_t), intent(in) :: val
        type(JuliaValue) :: res
        type(c_ptr) :: raw_ptr
        raw_ptr = fcj_box_int64(val)
        res%ptr = fcj_retain(raw_ptr)
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
        raw_ptr = fcj_box_bool(c_bool)
        res%ptr = fcj_retain(raw_ptr)
    end function julia_box_logical

    function julia_box_string(val) result(res)
        character(len=*), intent(in) :: val
        type(JuliaValue) :: res
        type(c_ptr) :: raw_ptr
        raw_ptr = fcj_box_string(to_c_string(val))
        res%ptr = fcj_retain(raw_ptr)
    end function julia_box_string

    function julia_box_complex(val) result(res)
        complex(kind=c_double), intent(in) :: val
        type(JuliaValue) :: res
        type(c_ptr) :: raw_ptr
        raw_ptr = fcj_box_complex(dble(val), aimag(val))
        res%ptr = fcj_retain(raw_ptr)
    end function julia_box_complex

    ! --- Array Wrapper & Deep Copy (Zero-Copy / Alloc+Memcpy, rank-generic) ---

    ! Rank-generic zero-copy wrap of contiguous Float64 memory, any rank
    ! 1..16. Extents are derived from size(arr, dim=k) -- there is no
    ! caller-supplied length to disagree with the array any more. Rejected
    ! loudly (invalid JuliaValue, diagnostic on error_unit) when the rank
    ! exceeds the C-side soft cap, when any extent is zero (c_loc on a
    ! zero-sized array is illegal), or when arr is not contiguous.
    function julia_wrap_array(arr) result(res)
        real(kind=c_double), target, intent(in) :: arr(..)
        type(JuliaValue) :: res
        type(c_ptr) :: raw_ptr
        integer :: nd, k
        integer(kind=c_long) :: dims(16)
        nd = rank(arr)
        if (nd < 1 .or. nd > 16) then
            write(error_unit, '(A,I0,A)') &
                'julia_wrap_array: rank (', nd, ') outside supported [1, 16]; ' // &
                'returning invalid JuliaValue'
            res%ptr = c_null_ptr
            return
        end if
        if (any([(size(arr, dim=k), k = 1, nd)] == 0)) then
            write(error_unit, '(A)') &
                'julia_wrap_array: zero-sized dimension; c_loc is illegal on ' // &
                'zero-sized arrays; returning invalid JuliaValue'
            res%ptr = c_null_ptr
            return
        end if
        if (.not. is_contiguous(arr)) then
            write(error_unit, '(A)') &
                'julia_wrap_array: arr is not contiguous; zero-copy wrap rejected; ' // &
                'returning invalid JuliaValue'
            res%ptr = c_null_ptr
            return
        end if
        do k = 1, nd
            dims(k) = size(arr, dim=k, kind=c_long)
        end do
        raw_ptr = fcj_wrap_array(c_loc(arr), int(nd, kind=c_long), dims)
        res%ptr = fcj_retain(raw_ptr)
    end function julia_wrap_array

    ! Rank-generic deep copy: Julia allocates a fresh Array{Float64,rank(arr)}
    ! with the same extents and memcpy's the data. Same rank/zero-size/contig
    ! guards as julia_wrap_array (contiguity is required to memcpy in Fortran
    ! storage order; a non-contiguous input is rejected, not silently packed).
    function julia_copy_array(arr) result(res)
        real(kind=c_double), target, intent(in) :: arr(..)
        type(JuliaValue) :: res
        type(c_ptr) :: raw_ptr
        integer :: nd, k
        integer(kind=c_long) :: dims(16)
        nd = rank(arr)
        if (nd < 1 .or. nd > 16) then
            write(error_unit, '(A,I0,A)') &
                'julia_copy_array: rank (', nd, ') outside supported [1, 16]; ' // &
                'returning invalid JuliaValue'
            res%ptr = c_null_ptr
            return
        end if
        if (any([(size(arr, dim=k), k = 1, nd)] == 0)) then
            write(error_unit, '(A)') &
                'julia_copy_array: zero-sized dimension; returning invalid JuliaValue'
            res%ptr = c_null_ptr
            return
        end if
        if (.not. is_contiguous(arr)) then
            write(error_unit, '(A)') &
                'julia_copy_array: arr is not contiguous; deep copy would read ' // &
                'strided memory as dense; returning invalid JuliaValue'
            res%ptr = c_null_ptr
            return
        end if
        do k = 1, nd
            dims(k) = size(arr, dim=k, kind=c_long)
        end do
        raw_ptr = fcj_copy_array(c_loc(arr), int(nd, kind=c_long), dims)
        res%ptr = fcj_retain(raw_ptr)
    end function julia_copy_array

    ! --- Init / Shutdown / Util ---
    
    subroutine julia_init()
        call fcj_init(c_null_ptr)
    end subroutine julia_init

    subroutine julia_init_with_image(image_path)
        character(len=*), intent(in) :: image_path
        character(kind=c_char, len=len_trim(image_path)+1), target :: c_path
        c_path = trim(image_path) // c_null_char
        call fcj_init(c_loc(c_path))
    end subroutine julia_init_with_image

    ! Startup control: mirrors C fcj_init_ex (bridge.h). An omitted argument
    ! selects the C-side default (c_null_ptr for paths, 0 threads = Julia
    ! default, handle_signals = 0 = "no takeover": after a successful init,
    ! SIGINT/SIGTERM are reset to SIG_DFL; jl_options.handle_signals is
    ! never touched). The legacy julia_init / julia_init_with_image wrappers
    ! go through C fcj_init, which pins handle_signals = 1, so their
    ! historical behavior is unchanged.
    !
    ! Paths are copied into fixed character(len=4096) buffers handed to the
    ! C side as raw pointers. A provided path that does not fit (together
    ! with its trailing c_null_char, i.e. len_trim >= 4096) would be
    ! silently truncated by the assignment; it is rejected instead: a
    ! diagnostic goes to error_unit and the routine returns WITHOUT
    ! initializing the runtime (fcj_init_ex is never called).
    subroutine julia_init_ex(image_path, project_path, nthreads, handle_signals)
        character(len=*), intent(in), optional :: image_path
        character(len=*), intent(in), optional :: project_path
        integer, intent(in), optional :: nthreads
        integer, intent(in), optional :: handle_signals

        type(FjOptions), target :: opts
        character(kind=c_char, len=4096), target :: c_image_path
        character(kind=c_char, len=4096), target :: c_project_path
        integer :: path_len

        opts%sysimage_path = c_null_ptr
        opts%project_path = c_null_ptr
        opts%nthreads = 0_c_int
        opts%handle_signals = 0_c_int

        if (present(image_path)) then
            path_len = len_trim(image_path)
            if (path_len >= len(c_image_path)) then
                ! Does not fit (path + c_null_char): reject, do not truncate.
                write(error_unit, '(a,i0,a)') &
                    'julia_init_ex: image_path too long (max ', &
                    len(c_image_path) - 1, ' chars), not initializing: ' // trim(image_path)
                return
            end if
            c_image_path = to_c_string(image_path)
            opts%sysimage_path = c_loc(c_image_path)
        end if
        if (present(project_path)) then
            path_len = len_trim(project_path)
            if (path_len >= len(c_project_path)) then
                ! Does not fit (path + c_null_char): reject, do not truncate.
                write(error_unit, '(a,i0,a)') &
                    'julia_init_ex: project_path too long (max ', &
                    len(c_project_path) - 1, ' chars), not initializing: ' // trim(project_path)
                return
            end if
            c_project_path = to_c_string(project_path)
            opts%project_path = c_loc(c_project_path)
        end if
        if (present(nthreads)) opts%nthreads = int(nthreads, kind=c_int)
        if (present(handle_signals)) opts%handle_signals = int(handle_signals, kind=c_int)

        call fcj_init_ex(c_loc(opts))
    end subroutine julia_init_ex

    subroutine julia_shutdown()
        call fcj_shutdown()
    end subroutine julia_shutdown

    subroutine julia_clear_function_cache()
        ! Explicitly drop the function-name cache and (when the loaded
        ! FortranBridge provides clear_kw_cache!) the Julia-side kwargs
        ! cache. Normally not needed: every julia_eval_string call (which
        ! includes the julia_include* helpers) invalidates them
        ! automatically on both outcome paths. Needed after rebinding
        ! names by other means: set_field on a module, calling include()
        ! or a reload helper by name, Julia-side evals.
        call fcj_clear_function_cache()
    end subroutine julia_clear_function_cache

    subroutine julia_eval_string(cmd)
        character(len=*), intent(in) :: cmd
        type(c_ptr) :: raw_res
        raw_res = fcj_eval_string(to_c_string(cmd))
        if (.not. c_associated(raw_res)) then
            ! Do not swallow the failure: eval errors used to vanish here and
            ! downstream unbox calls silently returned 0 (wrong answers that
            ! looked like success). Report loudly and keep the process alive
            ! -- the caller decides whether to stop.
            write(error_unit, '(a)') 'julia_eval_string: evaluation failed: ' // trim(cmd)
            write(error_unit, '(a)') 'julia_eval_string: ' // trim(get_last_error_message())
        end if
    end subroutine julia_eval_string

    ! Absolute directory of the running executable (no trailing slash), or
    ! an empty string if it cannot be resolved (see fcj_get_last_error).
    function julia_executable_dir() result(dir)
        character(len=:), allocatable :: dir
        character(kind=c_char), dimension(4096) :: buf
        type(c_ptr) :: ok
        integer :: i, nul
        ok = fcj_get_executable_dir(buf, int(size(buf), kind=c_size_t))
        if (.not. c_associated(ok)) then
            dir = ''
            return
        end if
        nul = 0
        do i = 1, size(buf)
            if (buf(i) == c_null_char) then
                nul = i - 1
                exit
            end if
        end do
        allocate(character(len=max(nul, 0)) :: dir)
        do i = 1, nul
            dir(i:i) = buf(i)
        end do
    end function julia_executable_dir

    ! Include a Julia source file located next to the running executable --
    ! the same anchor fcj_init_ex uses to probe for the FortranBridge
    ! package. Examples load examples_lib.jl through this so they behave
    ! identically from any working directory. A leading '/' in relname is
    ! treated as an absolute path and passed through unchanged.
    subroutine julia_include_exe_relative(relname)
        character(len=*), intent(in) :: relname
        character(len=:), allocatable :: dir, path
        if (len_trim(relname) == 0) then
            write(error_unit, '(a)') 'julia_include_exe_relative: empty file name'
            return
        end if
        if (relname(1:1) == '/') then
            path = trim(relname)
        else
            dir = julia_executable_dir()
            if (len(dir) == 0) then
                write(error_unit, '(a)') 'julia_include_exe_relative: cannot resolve executable directory: ' // &
                    trim(get_last_error_message())
                return
            end if
            path = dir // '/' // trim(relname)
        end if
        call julia_eval_string('include("' // path // '")')
    end subroutine julia_include_exe_relative

    function julia_eval(cmd) result(res)
        character(len=*), intent(in) :: cmd
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        raw_res = fcj_eval_string(to_c_string(cmd))
        res%ptr = fcj_retain(raw_res)
    end function julia_eval

    function get_last_error_message() result(msg)
        character(len=:), allocatable :: msg
        type(c_ptr) :: c_str
        character(kind=c_char), pointer :: f_char_ptr(:)
        integer :: i, length
        c_str = fcj_get_last_error()
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

    ! Fast path (register_f2_string): returns a raw @cfunction pointer for
    ! direct calls at native speed. The registry keeps the CFunction alive
    ! (rooted in Main), so GC lifetime is safe, but the contract has hard
    ! edges -- misuse crashes the process with no Julia-side diagnostic:
    !   1. the trampoline captures the function OBJECT at registration:
    !      same-name method redefinition is observed through old pointers,
    !      but rebinding the name to a new object (closure) leaves old
    !      pointers calling the captured object -- register after the final
    !      definition or rebinding;
    !   2. re-registering a name invalidates earlier pointers for that name
    !      (the old CFunction becomes collectable) -- discard them;
    !   3. the called function must not throw (an exception unwinds through
    !      the C trampoline frame: undefined behavior, typically a segfault);
    !   4. ret_type/arg_types must exactly match the signature (bitstypes
    !      only); nothing is validated at registration;
    !   5. pointers are invalid after julia_shutdown.
    function get_function_pointer(func_name, ret_type, arg_types) result(funptr)
        character(len=*), intent(in) :: func_name, ret_type, arg_types
        type(c_funptr) :: funptr
        funptr = fcj_get_function_pointer(to_c_string(func_name), &
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
        raw_res = fcj_call0(to_c_string(func_name))
        res%ptr = fcj_retain(raw_res)
    end function call_method_0

    function call_method_1_real(self, func_name, arg1) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: func_name
        real(kind=c_double), intent(in) :: arg1
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        raw_res = fcj_call1_float64(to_c_string(func_name), arg1)
        res%ptr = fcj_retain(raw_res)
    end function call_method_1_real

    function call_method_1_obj(self, func_name, arg_obj) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: func_name
        type(JuliaValue), intent(in) :: arg_obj
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        raw_res = fcj_call1_obj(to_c_string(func_name), arg_obj%ptr)
        res%ptr = fcj_retain(raw_res)
    end function call_method_1_obj

    function call_method_2_obj_real(self, func_name, arg_obj, arg2) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: func_name
        type(JuliaValue), intent(in) :: arg_obj
        real(kind=c_double), intent(in) :: arg2
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        raw_res = fcj_call2_obj_double(to_c_string(func_name), arg_obj%ptr, arg2)
        res%ptr = fcj_retain(raw_res)
    end function call_method_2_obj_real

    ! --- Accessors ---

    function get_field(self, name) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: name
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        raw_res = fcj_get_field(self%ptr, to_c_string(name))
        res%ptr = fcj_retain(raw_res)
    end function get_field

    subroutine set_field(self, name, val)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: name
        type(JuliaValue), intent(in) :: val
        call fcj_set_field(self%ptr, to_c_string(name), val%ptr)
    end subroutine set_field

    function at(self, idx) result(res)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t), intent(in) :: idx
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        raw_res = fcj_get_index_i(self%ptr, idx)
        res%ptr = fcj_retain(raw_res)
    end function at

    subroutine set_at(self, idx, val)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t), intent(in) :: idx
        type(JuliaValue), intent(in) :: val
        call fcj_set_index_i(self%ptr, idx, val%ptr)
    end subroutine set_at

    function at_2d(self, i, j) result(res)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t), intent(in) :: i, j
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        raw_res = fcj_get_index_ii(self%ptr, i, j)
        res%ptr = fcj_retain(raw_res)
    end function at_2d

    subroutine set_at_2d(self, i, j, val)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t), intent(in) :: i, j
        type(JuliaValue), intent(in) :: val
        call fcj_set_index_ii(self%ptr, i, j, val%ptr)
    end subroutine set_at_2d

    function at_3d(self, i, j, k) result(res)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t), intent(in) :: i, j, k
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        raw_res = fcj_get_index_iii(self%ptr, i, j, k)
        res%ptr = fcj_retain(raw_res)
    end function at_3d

    subroutine set_at_3d(self, i, j, k, val)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t), intent(in) :: i, j, k
        type(JuliaValue), intent(in) :: val
        call fcj_set_index_iii(self%ptr, i, j, k, val%ptr)
    end subroutine set_at_3d

    function at_string(self, key) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: key
        type(JuliaValue) :: res
        type(c_ptr) :: raw_res
        raw_res = fcj_get_index_s(self%ptr, to_c_string(key))
        res%ptr = fcj_retain(raw_res)
    end function at_string

    subroutine set_at_string(self, key, val)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: key
        type(JuliaValue), intent(in) :: val
        call fcj_set_index_s(self%ptr, to_c_string(key), val%ptr)
    end subroutine set_at_string

    ! --- Fast Real Element Accessors ---

    function at_real_1d(self, idx) result(val)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t), intent(in) :: idx
        real(kind=c_double) :: val
        val = fcj_get_real(self%ptr, idx)
    end function at_real_1d

    subroutine set_at_real_1d(self, idx, val)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t), intent(in) :: idx
        real(kind=c_double), intent(in) :: val
        call fcj_set_real(self%ptr, idx, val)
    end subroutine set_at_real_1d

    function at_real_2d(self, i, j) result(val)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t), intent(in) :: i, j
        real(kind=c_double) :: val
        val = fcj_get_real2(self%ptr, i, j)
    end function at_real_2d

    subroutine set_at_real_2d(self, i, j, val)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t), intent(in) :: i, j
        real(kind=c_double), intent(in) :: val
        call fcj_set_real2(self%ptr, i, j, val)
    end subroutine set_at_real_2d

    function at_real_3d(self, i, j, k) result(val)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t), intent(in) :: i, j, k
        real(kind=c_double) :: val
        val = fcj_get_real3(self%ptr, i, j, k)
    end function at_real_3d

    subroutine set_at_real_3d(self, i, j, k, val)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t), intent(in) :: i, j, k
        real(kind=c_double), intent(in) :: val
        call fcj_set_real3(self%ptr, i, j, k, val)
    end subroutine set_at_real_3d

    ! --- SciML Batch Extraction (Wave B) ---

    function to_fortran_real(self, dest, n) result(rc)
        class(JuliaValue), intent(in) :: self
        real(kind=c_double), intent(out), target :: dest(*)
        integer(kind=c_int64_t), intent(in) :: n
        integer(kind=c_int) :: rc
        rc = fcj_to_fortran(self%ptr, c_loc(dest), n)
    end function to_fortran_real

    function to_fortran_complex(self, dest, n) result(rc)
        class(JuliaValue), intent(in) :: self
        complex(kind=c_double), intent(out), target :: dest(*)
        integer(kind=c_int64_t), intent(in) :: n
        integer(kind=c_int) :: rc
        rc = fcj_to_fortran(self%ptr, c_loc(dest), n)
    end function to_fortran_complex

    function element(self, idx) result(v)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t), intent(in) :: idx
        type(JuliaValue) :: v
        ! fcj_get_element returns a RETAINED handle; do not retain again.
        v%ptr = fcj_get_element(self%ptr, idx)
    end function element

    function property(self, name) result(v)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: name
        type(JuliaValue) :: v
        ! fcj_get_property returns a RETAINED handle; do not retain again.
        v%ptr = fcj_get_property(self%ptr, to_c_string(name))
    end function property

    function length(self) result(res)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t) :: res
        res = fcj_length(self%ptr)
    end function length

    function ndims(self) result(res)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int64_t) :: res
        res = fcj_ndims(self%ptr)
    end function ndims

    function size_dim(self, dim) result(res)
        class(JuliaValue), intent(in) :: self
        integer(kind=c_int), intent(in) :: dim
        integer(kind=c_int64_t) :: res
        res = fcj_size(self%ptr, dim)
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
            ! Copy elements into the new arrays (retaining via the C
            ! root set); move_alloc then swaps them in. The old array's
            ! finalizers release the old references.
            do i = 1, self%n
                new_keys(i) = self%keys(i)
                new_vals(i) = self%values(i)
            end do
            call move_alloc(new_keys, self%keys)
            call move_alloc(new_vals, self%values)
        end if
        self%n = self%n + 1
        self%keys(self%n) = key
        ! Explicit copy: plain assignment would MOVE the caller's value.
        call copy_jv(self%values(self%n), val)
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
        raw_res = fcj_call_kwargs(to_c_string(func_name), ptrs, int(n, c_int32_t), &
                                 kw_ptrs, val_ptrs, int(nkw, c_int32_t))
        deallocate(ptrs); deallocate(kw_ptrs); deallocate(val_ptrs); deallocate(c_keys)
        res%ptr = fcj_retain(raw_res)
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
             tmp_ptr = fcj_box_int64(val)
             res%ptr = fcj_retain(tmp_ptr)
        type is (integer(kind=c_int32_t))
             tmp_ptr = fcj_box_int32(val)
             res%ptr = fcj_retain(tmp_ptr)
        type is (real(kind=c_double))
             tmp_ptr = fcj_box_float64(val)
             res%ptr = fcj_retain(tmp_ptr)
        type is (real(kind=c_float))
             tmp_ptr = fcj_box_float64(dble(val))
             res%ptr = fcj_retain(tmp_ptr)
        type is (logical)
            if (val) then
                c_bool = 1
            else
                c_bool = 0
            end if
            tmp_ptr = fcj_box_bool(c_bool)
            res%ptr = fcj_retain(tmp_ptr)
        type is (character(len=*))
             tmp_ptr = fcj_box_string(to_c_string(val))
             res%ptr = fcj_retain(tmp_ptr)
        type is (complex(kind=c_double))
             tmp_ptr = fcj_box_complex(dble(val), aimag(val))
             res%ptr = fcj_retain(tmp_ptr)
        class is (JuliaValue)
             if (c_associated(val%ptr)) then
                 res%ptr = fcj_retain(val%ptr)
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
        ! %call on a function object is a true method call: func_name is
        ! ignored (kept only for signature compatibility) and the call is
        ! dispatched through call_value.
        if (c_associated(self%ptr)) then
            if (fcj_is_function(self%ptr) /= 0) then
                res = self%call_value_0()
                return
            end if
        end if
        raw_res = fcj_call0(to_c_string(func_name))
        res%ptr = fcj_retain(raw_res)
    end function call_method_generic_dispatch_0

    function call_method_generic_dispatch_1(self, func_name, arg1) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: func_name
        class(*), intent(in) :: arg1
        type(JuliaValue) :: res
        
        type(JuliaValue) :: boxed_args(1)
        type(c_ptr) :: raw_args(1)
        type(c_ptr) :: raw_res
        
        ! %call on a function object is a true method call: func_name is
        ! ignored (kept only for signature compatibility) and the call is
        ! dispatched through call_value.
        if (c_associated(self%ptr)) then
            if (fcj_is_function(self%ptr) /= 0) then
                res = self%call_value_1(arg1)
                return
            end if
        end if
        boxed_args(1) = box_argument(arg1)
        raw_args(1) = boxed_args(1)%ptr
        
        raw_res = fcj_call_general(to_c_string(func_name), raw_args, 1_c_int32_t)
        res%ptr = fcj_retain(raw_res)
    end function call_method_generic_dispatch_1

    function call_method_generic_dispatch_2(self, func_name, arg1, arg2) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: func_name
        class(*), intent(in) :: arg1, arg2
        type(JuliaValue) :: res
        
        type(JuliaValue) :: boxed_args(2)
        type(c_ptr) :: raw_args(2)
        type(c_ptr) :: raw_res
        
        ! %call on a function object is a true method call: func_name is
        ! ignored (kept only for signature compatibility) and the call is
        ! dispatched through call_value.
        if (c_associated(self%ptr)) then
            if (fcj_is_function(self%ptr) /= 0) then
                res = self%call_value_2(arg1, arg2)
                return
            end if
        end if
        boxed_args(1) = box_argument(arg1)
        boxed_args(2) = box_argument(arg2)
        
        raw_args(1) = boxed_args(1)%ptr
        raw_args(2) = boxed_args(2)%ptr
        
        raw_res = fcj_call_general(to_c_string(func_name), raw_args, 2_c_int32_t)
        res%ptr = fcj_retain(raw_res)
    end function call_method_generic_dispatch_2

    function call_method_generic_dispatch_3(self, func_name, arg1, arg2, arg3) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: func_name
        class(*), intent(in) :: arg1, arg2, arg3
        type(JuliaValue) :: res
        
        type(JuliaValue) :: boxed_args(3)
        type(c_ptr) :: raw_args(3)
        type(c_ptr) :: raw_res
        
        ! %call on a function object is a true method call: func_name is
        ! ignored (kept only for signature compatibility) and the call is
        ! dispatched through call_value.
        if (c_associated(self%ptr)) then
            if (fcj_is_function(self%ptr) /= 0) then
                res = self%call_value_3(arg1, arg2, arg3)
                return
            end if
        end if
        boxed_args(1) = box_argument(arg1)
        boxed_args(2) = box_argument(arg2)
        boxed_args(3) = box_argument(arg3)
        
        raw_args(1) = boxed_args(1)%ptr
        raw_args(2) = boxed_args(2)%ptr
        raw_args(3) = boxed_args(3)%ptr
        
        raw_res = fcj_call_general(to_c_string(func_name), raw_args, 3_c_int32_t)
        res%ptr = fcj_retain(raw_res)
    end function call_method_generic_dispatch_3

    function call_method_generic_dispatch_4(self, func_name, arg1, arg2, arg3, arg4) result(res)
        class(JuliaValue), intent(in) :: self
        character(len=*), intent(in) :: func_name
        class(*), intent(in) :: arg1, arg2, arg3, arg4
        type(JuliaValue) :: res
        
        type(JuliaValue) :: boxed_args(4)
        type(c_ptr) :: raw_args(4)
        type(c_ptr) :: raw_res
        
        ! %call on a function object is a true method call: func_name is
        ! ignored (kept only for signature compatibility) and the call is
        ! dispatched through call_value.
        if (c_associated(self%ptr)) then
            if (fcj_is_function(self%ptr) /= 0) then
                res = self%call_value_4(arg1, arg2, arg3, arg4)
                return
            end if
        end if
        boxed_args(1) = box_argument(arg1)
        boxed_args(2) = box_argument(arg2)
        boxed_args(3) = box_argument(arg3)
        boxed_args(4) = box_argument(arg4)
        
        raw_args(1) = boxed_args(1)%ptr
        raw_args(2) = boxed_args(2)%ptr
        raw_args(3) = boxed_args(3)%ptr
        raw_args(4) = boxed_args(4)%ptr
        
        raw_res = fcj_call_general(to_c_string(func_name), raw_args, 4_c_int32_t)
        res%ptr = fcj_retain(raw_res)
    end function call_method_generic_dispatch_4

    ! --- Cached Function Handles ---

    function julia_function(func_name) result(v)
        character(len=*), intent(in) :: func_name
        type(JuliaValue) :: v
        ! fcj_resolve_function returns an owned (retained) reference; do not retain again.
        v%ptr = fcj_resolve_function(to_c_string(func_name))
    end function julia_function

    ! --- SciML Callbacks (Wave B) ---

    function julia_callback(fnptr, ctx) result(v)
        type(c_funptr), intent(in) :: fnptr
        type(c_ptr), intent(in) :: ctx
        type(JuliaValue) :: v
        ! fcj_create_callback returns an owned (retained) reference
        ! routed through fcj_retain (C-side root set); do not retain
        ! again, same pattern as julia_function. The C side also binds
        ! the callable to Main.FJ_CALLBACK for eval-ed solver code.
        ! c_funptr and c_ptr share the same representation, so the
        ! transfer adapts c_funloc(fn) to the C void* parameter.
        v%ptr = fcj_create_callback(transfer(fnptr, c_null_ptr), ctx)
    end function julia_callback

    function call_value_0(self) result(res)
        class(JuliaValue), intent(in) :: self
        type(JuliaValue) :: res
        type(c_ptr) :: no_args(1)
        type(c_ptr) :: raw_res

        no_args(1) = c_null_ptr
        raw_res = fcj_call_function(self%ptr, no_args, 0_c_int32_t)
        res%ptr = fcj_retain(raw_res)
    end function call_value_0

    function call_value_1(self, arg1) result(res)
        class(JuliaValue), intent(in) :: self
        class(*), intent(in) :: arg1
        type(JuliaValue) :: res

        type(JuliaValue) :: boxed_args(1)
        type(c_ptr) :: raw_args(1)
        type(c_ptr) :: raw_res

        boxed_args(1) = box_argument(arg1)
        raw_args(1) = boxed_args(1)%ptr

        raw_res = fcj_call_function(self%ptr, raw_args, 1_c_int32_t)
        res%ptr = fcj_retain(raw_res)
    end function call_value_1

    function call_value_2(self, arg1, arg2) result(res)
        class(JuliaValue), intent(in) :: self
        class(*), intent(in) :: arg1, arg2
        type(JuliaValue) :: res

        type(JuliaValue) :: boxed_args(2)
        type(c_ptr) :: raw_args(2)
        type(c_ptr) :: raw_res

        boxed_args(1) = box_argument(arg1)
        boxed_args(2) = box_argument(arg2)

        raw_args(1) = boxed_args(1)%ptr
        raw_args(2) = boxed_args(2)%ptr

        raw_res = fcj_call_function(self%ptr, raw_args, 2_c_int32_t)
        res%ptr = fcj_retain(raw_res)
    end function call_value_2

    function call_value_3(self, arg1, arg2, arg3) result(res)
        class(JuliaValue), intent(in) :: self
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

        raw_res = fcj_call_function(self%ptr, raw_args, 3_c_int32_t)
        res%ptr = fcj_retain(raw_res)
    end function call_value_3

    function call_value_4(self, arg1, arg2, arg3, arg4) result(res)
        class(JuliaValue), intent(in) :: self
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

        raw_res = fcj_call_function(self%ptr, raw_args, 4_c_int32_t)
        res%ptr = fcj_retain(raw_res)
    end function call_value_4

end module julia_high_level
