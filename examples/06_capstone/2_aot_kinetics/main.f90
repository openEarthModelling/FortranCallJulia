program aot_kinetics_bench
    ! Capstone AOT comparison driver: run the same FjKinetics chemistry
    ! kernel the bridge drives (JIT / sysimage modes of
    ! 06_capstone/1_reacting_flow), but through the standalone compiled
    ! library's @ccallable entry -- no bridge, no eval, no project env.
    !
    ! Workload mirrors the detonation chemistry mix: burning cells
    ! (T = 17) and frozen cells (T = 1.6) interleaved, so the per-cell
    ! cost matches the real run's hot/cold split.
    use iso_c_binding
    use julia_library_interface ! init_julia / shutdown_julia (from the library)
    implicit none

    interface
        function kinetics_build(a, ea, rg, q, cv) bind(C, name="kinetics_build") &
                result(res)
            import :: c_double, c_int
            real(c_double), value :: a, ea, rg, q, cv
            integer(c_int) :: res
        end function kinetics_build

        function kinetics_step(y, t, rho, n, dt) bind(C, name="kinetics_step") &
                result(res)
            import :: c_double, c_int, c_ptr
            type(c_ptr), value :: y, t, rho
            integer(c_int), value :: n
            real(c_double), value :: dt
            integer(c_int) :: res
        end function kinetics_step
    end interface

    integer, parameter :: n = 64, niter = 400
    real(c_double), parameter :: dt = 4.0e-4_c_double
    real(c_double), target :: ybuf(n, 2), tbuf(n), rhobuf(n)
    integer(c_int) :: ret
    integer :: k
    integer(8) :: c0, c1, crate
    real(8) :: t_init, t_warm, t_loop

    call system_clock(c0, crate)
    call init_julia(0_c_int, c_null_ptr)
    call system_clock(c1)
    t_init = dble(c1 - c0)/dble(crate)

    print '(a)', 'AOT kinetics benchmark: standalone libkinetics.so'
    print '(a,es12.3,a)', 'library init: ', t_init, ' s'

    ret = kinetics_build(164180.0_c_double, 25.0_c_double, 1.0_c_double, &
                         25.0_c_double, 2.5_c_double)
    if (ret /= 2) then
        print *, 'FATAL: kinetics_build returned ', ret, '(expected 2 species)'
        stop 1
    end if

    call reset_state()
    ret = kinetics_step(c_loc(ybuf), c_loc(tbuf), c_loc(rhobuf), int(n, c_int), dt)
    if (ret /= 0) then
        print *, 'FATAL: kinetics_step returned ', ret
        stop 1
    end if
    call system_clock(c1)
    print '(a,es12.3,a)', 'build+first batched step (after init): ', &
        dble(c1 - c0)/dble(crate) - t_init, ' s'

    ! first timed call on a fresh state, then the steady loop
    call reset_state()
    call system_clock(c0)
    ret = kinetics_step(c_loc(ybuf), c_loc(tbuf), c_loc(rhobuf), int(n, c_int), dt)
    call system_clock(c1)
    t_warm = dble(c1 - c0)/dble(crate)

    call system_clock(c0)
    do k = 1, niter
        call reset_state()
        ret = kinetics_step(c_loc(ybuf), c_loc(tbuf), c_loc(rhobuf), int(n, c_int), dt)
        if (ret /= 0) then
            print *, 'FATAL: kinetics_step failed at iteration ', k
            stop 1
        end if
    end do
    call system_clock(c1)
    t_loop = dble(c1 - c0)/dble(crate)

    print '(a,i0,a,es12.3,a)', 'first batched step (', n, ' cells): ', t_warm, ' s'
    print '(a,i0,a,i0,a,es12.3,a)', 'steady loop: ', niter, ' calls x ', n, &
        ' cells in ', t_loop, ' s'
    print '(a,es12.3,a)', 'per cell-step: ', t_loop/(dble(niter)*n), ' s'
    print '(a)', 'AOT_BENCH_DONE'

    call shutdown_julia(0_c_int)

contains

    ! Restore fresh reactant everywhere and the nominal temperatures:
    ! odd cells burn (reset each iteration so every call pays the full
    ! 10-decade burn cost), even cells stay frozen.
    subroutine reset_state()
        integer :: j
        do j = 1, n
            rhobuf(j) = 1.0_c_double
            ybuf(j, 1) = 1.0_c_double
            ybuf(j, 2) = 0.0_c_double
            if (modulo(j, 2) == 1) then
                tbuf(j) = 17.0_c_double
            else
                tbuf(j) = 1.6_c_double
            end if
        end do
    end subroutine reset_state

end program aot_kinetics_bench
