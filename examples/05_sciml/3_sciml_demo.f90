! ==============================================================================
! Example: End-to-end SciML acceptance demo (Wave B)
!
! Fortran supplies a bind(c) harmonic-oscillator RHS
!     du1 = u2,  du2 = -u1         (analytic: u1 = cos t, u2 = -sin t)
! which fj_create_callback wraps into the Julia callable f(du, u, p, t) also
! bound to Main.FJ_CALLBACK. The ODE is then assembled by eval-ing solver code
! in Main (ODEProblem(FJ_CALLBACK, u0, tspan); solve with Tsit5), and the
! result is navigated through the Wave B extraction surface
! (%property / %element / %to_fortran) and compared against the analytic
! solution.
!
! Usage (run from build/examples):
!   ./ex_sciml_demo               JIT mode: julia_init_ex(project_path=...)
!   ./ex_sciml_demo sysimage      AOT mode: + image_path=libfj_sysimage.so
!
! Paths default to the in-tree layout relative to the CWD and can be
! overridden for other layouts:
!   FJ_SCIML_PROJECT   scratch env carrying SciMLBase + OrdinaryDiffEq
!                      (default: ../../scripts/sysimage_env)
!   FJ_SCIML_SYSIMAGE  built sysimage (default: ../../build/libfj_sysimage.so)
! ==============================================================================
module sciml_demo_rhs_mod
    use iso_c_binding
    implicit none
contains

    ! Harmonic oscillator RHS, exactly per the Fortran RHS callback contract:
    !   subroutine rhs(ctx, n, u, du, t, err) bind(c)
    subroutine rhs(ctx, n, u, du, t, err) bind(c)
        type(c_ptr), value, intent(in) :: ctx         ! unused (stateless RHS)
        integer(kind=c_int64_t), value, intent(in) :: n
        type(c_ptr), value, intent(in) :: u, du       ! raw Float64 element ptrs
        real(kind=c_double), value, intent(in) :: t
        integer(kind=c_int), intent(out) :: err

        real(kind=c_double), pointer :: u_arr(:), du_arr(:)

        err = 0_c_int
        if (n <= 0_c_int64_t) return
        call c_f_pointer(u, u_arr, [int(n)])
        call c_f_pointer(du, du_arr, [int(n)])
        du_arr(1) =  u_arr(2)
        du_arr(2) = -u_arr(1)
    end subroutine rhs

end module sciml_demo_rhs_mod

program ex_sciml_demo
    use iso_c_binding
    use, intrinsic :: iso_fortran_env, only: error_unit
    use julia_high_level
    use sciml_demo_rhs_mod, only: rhs
    implicit none

    type(JuliaValue) :: res, cb, du_boxed, u_boxed, p_boxed, t_boxed
    type(JuliaValue) :: sol, v_u, v_last, v_t, v_tf
    type(c_funptr) :: fn
    character(len=32) :: mode
    character(len=512) :: project_path, image_path
    character(len=:), allocatable :: msg
    real(kind=c_double), target :: u_f(2), du_f(2)
    real(kind=c_double) :: fbuf(2), t_final
    real(kind=c_double), parameter :: T_END = 10.0_c_double
    real(kind=c_double) :: exact1, exact2, e1, e2
    integer(kind=c_int) :: rc, st
    integer(kind=c_int64_t) :: n_u, n_t
    integer :: retcode_ok
    character(len=512) :: cwd

    mode = 'jit'
    if (command_argument_count() >= 1) call get_command_argument(1, mode)

    ! --- Path resolution: env override > CWD-relative default ---------------
    call get_environment_variable('FJ_SCIML_PROJECT', project_path, status=st)
    if (st /= 0 .or. len_trim(project_path) == 0) &
        project_path = '../../scripts/sysimage_env'
    image_path = '../../build/libfj_sysimage.so'
    call get_environment_variable('FJ_SCIML_SYSIMAGE', image_path, status=st)
    if (st /= 0 .or. len_trim(image_path) == 0) &
        image_path = '../../build/libfj_sysimage.so'

    ! Absolute paths only: jl_init_with_image_file resolves a RELATIVE
    ! sysimage path against the Julia bindir (not the process CWD), which
    ! would point outside the build tree. Prefix the process CWD so the
    ! paths are absolute (kernel-resolved .. components are fine).
    call getcwd(cwd)
    if (len_trim(cwd) > 0 .and. project_path(1:1) /= '/') &
        project_path = trim(cwd) // '/' // trim(project_path)
    if (len_trim(cwd) > 0 .and. image_path(1:1) /= '/') &
        image_path = trim(cwd) // '/' // trim(image_path)

    if (trim(adjustl(mode)) == 'sysimage') then
        print *, 'mode=sysimage image=', trim(image_path)
        call julia_init_ex(image_path=trim(image_path), project_path=trim(project_path))
    else
        print *, 'mode=jit project=', trim(project_path)
        call julia_init_ex(project_path=trim(project_path))
    end if

    ! --- Runtime sanity probe ------------------------------------------------
    res = julia_eval("1 + 1")
    if (.not. res%is_valid() .or. res%as_integer() /= 2) then
        msg = get_last_error_message()
        write (error_unit, '(A)') 'FATAL: Julia runtime init failed: ' // trim(msg)
        stop 1
    end if

    ! --- Load the SciML stack (baked into the sysimage, or env in JIT mode) --
    call julia_eval_string('import OrdinaryDiffEq')
    call julia_eval_string('import SciMLBase')
    res = julia_eval("OrdinaryDiffEq.ODEProblem")
    if (.not. res%is_valid()) then
        msg = get_last_error_message()
        write (error_unit, '(A)') 'FATAL: OrdinaryDiffEq not available: ' // trim(msg)
        stop 1
    end if

    ! --- Wrap the Fortran RHS into a Julia callable ---------------------------
    fn = c_funloc(rhs)
    cb = julia_callback(fn, c_null_ptr)
    if (.not. cb%is_valid()) then
        msg = get_last_error_message()
        write (error_unit, '(A)') 'FATAL: julia_callback failed: ' // trim(msg)
        stop 1
    end if

    ! --- Direct round-trip of the bridge before handing it to the solver -----
    !    f(du, u, p, t) with u = [1.0, 0.5] must produce du = [0.5, -1.0]
    u_f(1) = 1.0_c_double;  u_f(2) = 0.5_c_double
    du_f(1) = 0.0_c_double; du_f(2) = 0.0_c_double
    du_boxed = julia_wrap_array_1d(du_f, 2_c_int64_t)
    u_boxed  = julia_wrap_array_1d(u_f, 2_c_int64_t)
    p_boxed  = julia_box_real(0.0_c_double)
    t_boxed  = julia_box_real(0.0_c_double)
    if (.not. du_boxed%is_valid() .or. .not. u_boxed%is_valid()) then
        write (error_unit, '(A)') 'FATAL: boxing du/u failed'
        stop 1
    end if
    res = cb%call_value(du_boxed, u_boxed, p_boxed, t_boxed)
    if (abs(du_f(1) - 0.5_c_double) > 1.0e-12_c_double .or. &
        abs(du_f(2) + 1.0_c_double) > 1.0e-12_c_double) then
        write (error_unit, '(A,2ES24.16)') 'FATAL: callback round-trip mismatch: du=', du_f
        stop 1
    end if
    print *, 'DEMO_CALLBACK_OK du=[', du_f(1), ',', du_f(2), ']'

    ! --- Solve: ODEProblem(FJ_CALLBACK, u0, tspan) + Tsit5, eval-ed in Main --
    !    The assignment expression returns the solution object as a handle.
    res = julia_eval("sol = OrdinaryDiffEq.solve(" // &
                     "OrdinaryDiffEq.ODEProblem(FJ_CALLBACK, [1.0, 0.0], (0.0, 10.0)), " // &
                     "OrdinaryDiffEq.Tsit5(); reltol = 1.0e-8, abstol = 1.0e-8)")
    if (.not. res%is_valid()) then
        msg = get_last_error_message()
        write (error_unit, '(A)') 'FATAL: ODE solve failed: ' // trim(msg)
        stop 1
    end if
    sol = res

    res = julia_eval("sol.retcode == SciMLBase.ReturnCode.Success ? 1 : 0")
    if (.not. res%is_valid() .or. res%as_integer() /= 1) then
        write (error_unit, '(A)') 'FATAL: solver retcode is not Success'
        stop 1
    end if

    ! --- Navigate the solution through the extraction surface ---------------
    v_u = sol%property("u")                    ! Vector{Vector{Float64}}
    if (.not. v_u%is_valid()) then
        msg = get_last_error_message()
        write (error_unit, '(A)') 'FATAL: property("u") failed: ' // trim(msg)
        stop 1
    end if
    n_u = v_u%length()
    if (n_u < 1_c_int64_t) then
        write (error_unit, '(A)') 'FATAL: solution has no saved states'
        stop 1
    end if
    v_last = v_u%element(n_u)                  ! final saved state [u1, u2]
    if (.not. v_last%is_valid()) then
        msg = get_last_error_message()
        write (error_unit, '(A)') 'FATAL: element(n) failed: ' // trim(msg)
        stop 1
    end if
    rc = v_last%to_fortran(fbuf, 2_c_int64_t)
    if (rc /= 0) then
        msg = get_last_error_message()
        write (error_unit, '(A)') 'FATAL: to_fortran(final state) failed: ' // trim(msg)
        stop 1
    end if

    v_t = sol%property("t")                    ! saved time grid
    n_t = v_t%length()
    v_tf = v_t%element(n_t)                    ! final time
    if (.not. v_tf%is_valid()) then
        msg = get_last_error_message()
        write (error_unit, '(A)') 'FATAL: element(n) on t failed: ' // trim(msg)
        stop 1
    end if
    t_final = v_tf%as_real()

    ! --- Compare against the analytic solution -------------------------------
    exact1 = cos(t_final)
    exact2 = -sin(t_final)
    e1 = abs(fbuf(1) - exact1)
    e2 = abs(fbuf(2) - exact2)
    if (e1 > 1.0e-3_c_double .or. e2 > 1.0e-3_c_double) then
        write (error_unit, '(A,3ES24.16)') 'FATAL: u1 mismatch: got/exact/err ', &
            fbuf(1), exact1, e1
        write (error_unit, '(A,3ES24.16)') 'FATAL: u2 mismatch: got/exact/err ', &
            fbuf(2), exact2, e2
        stop 1
    end if

    print *, 'DEMO_PASS steps=', n_u, ' t_final=', t_final
    print *, 'DEMO_PASS u1=', fbuf(1), ' exact=', exact1, ' err=', e1
    print *, 'DEMO_PASS u2=', fbuf(2), ' exact=', exact2, ' err=', e2

    ! --- Shutdown -------------------------------------------------------------
    call julia_shutdown()

end program ex_sciml_demo
