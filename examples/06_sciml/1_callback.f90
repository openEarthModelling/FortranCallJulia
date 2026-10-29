! ==============================================================================
! Example: SciML-style Julia callback into Fortran (Wave B)
!
! julia_callback wraps a bind(c) Fortran RHS into a Julia callable
! f(du, u, p, t) -- the signature DifferentialEquations.jl solvers
! expect. The callable is exercised through Julia via the 4-argument
! call_value generic (dispatches to the private specific
! call_value_4) with boxed arguments; du and u are zero-copy Float64
! arrays, so the writes performed by the Fortran RHS land directly in
! local Fortran memory.
!
! Fortran RHS contract (must match src/FortranBridge/src/Callbacks.jl):
!   subroutine rhs(ctx, n, u, du, t, err) bind(c)
!     ctx  : type(c_ptr), value           -- user context (ignored here)
!     n    : integer(c_int64_t), value    -- number of elements
!     u,du : type(c_ptr), value           -- raw Float64 element pointers
!                                         -- into Julia heap memory (n each)
!     t    : real(c_double), value        -- time
!     err  : integer(c_int), intent(out)  -- err /= 0 => Julia side throws
! ==============================================================================
module callback_mod
    use iso_c_binding
    implicit none
    ! Decay coefficient of du/dt = -k * u
    real(kind=c_double), parameter :: K_DECAY = 2.0_c_double

contains

    ! Stateless exponential-decay RHS: du = -k * u
    subroutine rhs(ctx, n, u, du, t, err) bind(c)
        type(c_ptr), value, intent(in) :: ctx        ! unused (stateless RHS)
        integer(kind=c_int64_t), value, intent(in) :: n
        type(c_ptr), value, intent(in) :: u, du
        real(kind=c_double), value, intent(in) :: t  ! unused (autonomous RHS)
        integer(kind=c_int), intent(out) :: err

        real(kind=c_double), pointer :: u_arr(:), du_arr(:)
        integer :: i

        err = 0_c_int
        if (n <= 0_c_int64_t) return
        call c_f_pointer(u, u_arr, [int(n)])
        call c_f_pointer(du, du_arr, [int(n)])
        do i = 1, int(n)
            du_arr(i) = -K_DECAY * u_arr(i)
        end do
    end subroutine rhs

end module callback_mod

program ex_sciml_callback
    use iso_c_binding
    use, intrinsic :: iso_fortran_env, only: error_unit
    use julia_high_level
    use callback_mod, only: rhs, K_DECAY
    implicit none

    type(JuliaValue) :: cb, du_boxed, u_boxed, p_boxed, t_boxed, res
    type(c_funptr) :: fn
    real(kind=c_double), target :: u_f(1), du_f(1)
    real(kind=c_double) :: expected

    print *, "--- Example: SciML-style Fortran RHS callback ---"

    ! 1. Initialize with the default exe-adjacent package probe
    call julia_init_ex()

    ! 2. Wrap the bind(c) RHS into a Julia callable (already retained)
    fn = c_funloc(rhs)
    cb = julia_callback(fn, c_null_ptr)
    if (.not. cb%is_valid()) then
        write (error_unit, '(A)') 'FATAL: julia_callback failed: ' // get_last_error_message()
        stop 1
    end if

    ! 3. Box f's arguments: du (Float64 vector workspace, zero-copy),
    !    u = [1.0], p = 0.0, t = 0.0 (p is ignored by the bridge closure)
    du_f(1) = 0.0_c_double
    u_f(1) = 1.0_c_double
    du_boxed = julia_wrap_array(du_f)
    u_boxed = julia_wrap_array(u_f)
    p_boxed = julia_box_real(0.0_c_double)
    t_boxed = julia_box_real(0.0_c_double)
    if (.not. du_boxed%is_valid() .or. .not. u_boxed%is_valid()) then
        write (error_unit, '(A)') 'FATAL: boxing du/u failed'
        stop 1
    end if

    ! 4. Invoke the Julia callable f(du, u, p, t); it ccalls back into
    !    rhs, which writes du in place.
    res = cb%call_value(du_boxed, u_boxed, p_boxed, t_boxed)

    ! 5. Verify du(1) == -k * 1.0
    expected = -K_DECAY * u_f(1)
    if (abs(du_f(1) - expected) > 1.0e-12_c_double) then
        write (error_unit, '(A,ES24.16,A,ES24.16)') &
            'FATAL: du(1) = ', du_f(1), ', expected ', expected
        stop 1
    end if

    write (*, '(A,F12.6)') 'EX_CALLBACK_OK du=', du_f(1)

    ! 6. Shutdown
    call julia_shutdown()

end program ex_sciml_callback
