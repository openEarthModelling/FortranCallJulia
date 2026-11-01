! ==============================================================================
! Capstone example 2: GRI-Mech 3.0 ignition delay through the bridge (JIT)
!
! Standalone homogeneous ignition benchmark -- Phase B chemistry integration
! without the flow solver. Stoichiometric CH4/air at 1500 K, 1 atm,
! constant-volume adiabatic (the ChemMechSim validation setup), driven from
! Fortran through the embedded runtime:
!
!   1. init with the shared scratch env (FJ_KINETICS_PROJECT overrides the
!      default <exe>/../../scripts/sysimage_env, same probing as the
!      capstone example; JIT mode -- no sysimage involved)
!   2. FjKinetics.build_gri30_kinetics() + run_gri_ignition() in Julia
!   3. batch extraction of ts (2001), T (2001) and the key-species mole
!      fraction matrix X (4 x 2001: CH4, O2, CO2, OH) -- zero per-element
!      bridge traffic, one fcj_to_fortran per array
!   4. ignition delay computed IN FORTRAN with the validation criterion
!      (grid point after the steepest |dT/dt| segment)
!   5. figure data: the full extracted trajectory lands in
!      examples/07_capstone/output/gri_ignition.csv (same CSV convention
!      as the reacting-flow driver; consumed by figures/plot_capstone.py)
!
! Acceptance: the Fortran-computed t_ign, the extracted T_end, and two X
! spot values (CH4 at t=0, CO2 at t_end -- pinning the 4x2001 column-major
! matrix layout) must reproduce the native Julia run
! (examples/07_capstone/run_gri_native.jl, same FjKinetics call path) to a
! relative difference < 1e-8 each. Generate the reference first -- with the
! build-pinned Julia, NOT the juliaup shim (the bridge embeds libjulia
! 1.12.7; a different runtime drifts at the ignition transition and fails
! the gates below while wrongly blaming the extraction, so run_gri_native.jl
! refuses to run under one):
!
!   cd build/examples
!   julia --project=../../scripts/sysimage_env \
!       ../../examples/07_capstone/run_gri_native.jl
!   ./ex_capstone_gri_ignition
!
! (or point FJ_GRI_NATIVE at the gri_native.dat the script wrote)
! ==============================================================================
program ex_capstone_gri_ignition
    use iso_c_binding
    use, intrinsic :: iso_fortran_env, only: error_unit
    use julia_high_level
    implicit none

    integer, parameter :: NSAMPLE = 2001         ! mirrors the validation grid
    integer, parameter :: NSP_OUT = 4
    character(len=3), parameter :: SP_OUT(NSP_OUT) = ['CH4', 'O2 ', 'CO2', 'OH ']
    real(kind=c_double), parameter :: REL_TOL = 1.0e-8_c_double

    type(JuliaValue) :: dummy, res, v
    real(kind=c_double), target :: ts(NSAMPLE), T(NSAMPLE)
    ! Julia X is a 4x2001 column-major Matrix; to_fortran takes a rank-1
    ! buffer, so hold it flat and index species k of sample i linearly
    ! (column-major: sample i occupies elements (i-1)*NSP_OUT + 1 .. i*NSP_OUT)
    real(kind=c_double), target :: Xflat(NSP_OUT * NSAMPLE)
    real(kind=c_double) :: dtdt(NSAMPLE - 1)
    real(kind=c_double) :: t_ign_f, t_ign_jl, t_ign_nat, t_end_nat
    real(kind=c_double) :: x_ch4_nat, x_co2_nat, rel, rel_t, rel_x1, rel_x2
    integer(kind=c_int) :: rc
    integer :: k, imax, iostat, unit_nat, st
    logical :: lex
    character(len=512) :: project_path, native_path, cwd, outdir
    integer :: u_out
    character(len=:), allocatable :: exe_dir

    print *, "--- Capstone 2: GRI-Mech 3.0 ignition delay (bridge, JIT) ---"

    ! --- 1. Project env: same probing chain as the capstone example ------
    ! The project must carry FortranBridge AND FjKinetics AND ChemMechSim
    ! (scripts/install_sciml_env.jl develops all three into sysimage_env).
    call get_environment_variable('FJ_KINETICS_PROJECT', project_path, status=st)
    if (st /= 0) then
        exe_dir = julia_executable_dir()
        project_path = exe_dir // '/../../scripts/sysimage_env'
    end if
    if (project_path(1:1) /= '/') then
        call getcwd(cwd)               ! same intrinsic the capstone/sciml examples use
        project_path = trim(cwd) // '/' // trim(project_path)
    end if
    inquire (file=trim(project_path) // '/Project.toml', exist=lex)
    if (.not. lex) then
        write (error_unit, '(A)') 'FATAL: project env not found at ' // &
            trim(project_path) // ' (set FJ_KINETICS_PROJECT; run ' // &
            'scripts/install_sciml_env.jl first)'
        stop 1
    end if

    call julia_init_ex(project_path=trim(project_path))
    print *, 'project: ', trim(project_path)

    ! --- 2. Chemistry in Julia: one driver, called by name ---------------
    call julia_eval_string('using FjKinetics')
    ! Driver body kept in one eval so a Julia-side throw surfaces as an
    ! invalid call result with last_error set (never crosses the ABI).
    call julia_eval_string( &
        'function fj_gri_run() :: NamedTuple' // new_line('a') // &
        '    gs = FjKinetics.build_gri30_kinetics()' // new_line('a') // &
        '    return FjKinetics.run_gri_ignition(gs)' // new_line('a') // &
        'end')
    res = dummy%call('fj_gri_run')
    if (.not. res%is_valid()) &
        call fail('fj_gri_run failed: ' // get_last_error_message())
    print *, 'ignition solve done; extracting arrays...'

    ! --- 3. Batch extraction: one bulk copy per array ---------------------
    v = res%property('ts')
    if (.not. v%is_valid()) call fail('property ts: ' // get_last_error_message())
    rc = v%to_fortran(ts, int(NSAMPLE, kind=c_int64_t))
    if (rc /= 0) call fail('to_fortran ts: ' // get_last_error_message())

    v = res%property('T')
    if (.not. v%is_valid()) call fail('property T: ' // get_last_error_message())
    rc = v%to_fortran(T, int(NSAMPLE, kind=c_int64_t))
    if (rc /= 0) call fail('to_fortran T: ' // get_last_error_message())

    ! Matrix{Float64} 4x2001, bulk-copied into the flat buffer
    v = res%property('X')
    if (.not. v%is_valid()) call fail('property X: ' // get_last_error_message())
    rc = v%to_fortran(Xflat, int(NSP_OUT * NSAMPLE, kind=c_int64_t))
    if (rc /= 0) call fail('to_fortran X: ' // get_last_error_message())

    v = res%property('t_ign')
    if (.not. v%is_valid()) call fail('property t_ign: ' // get_last_error_message())
    t_ign_jl = v%as_real()

    ! --- 4. Ignition delay IN FORTRAN (validation criterion) --------------
    do k = 1, NSAMPLE - 1
        dtdt(k) = abs((T(k + 1) - T(k)) / (ts(k + 1) - ts(k)))
    end do
    imax = maxloc(dtdt, 1)          ! first occurrence, like Julia's argmax
    t_ign_f = ts(imax + 1)

    print '(A,ES12.4,A,F8.1,A)', ' t_ign (fortran) = ', t_ign_f * 1.0e3_c_double, &
        ' ms   T_end = ', T(NSAMPLE), ' K'
    print '(A,ES12.4,A)', ' t_ign (julia)   = ', t_ign_jl * 1.0e3_c_double, ' ms'
    do k = 1, NSP_OUT
        print '(A,A3,A,ES12.4,A,ES12.4)', ' ', SP_OUT(k), ': X(0ms) = ', x_at(k, 1), &
            '  X(end) = ', x_at(k, NSAMPLE)
    end do
    if (t_ign_f /= t_ign_jl) &
        call fail('fortran/julia t_ign disagree on identical arrays')

    ! --- 4.5 figure data: full trajectory CSV for figures/plot_capstone.py --
    ! same exe-relative output dir + CSV convention as the reacting-flow
    ! driver ('#' metadata lines, column-name row, full-precision values)
    outdir = output_dir()
    call execute_command_line('mkdir -p ' // trim(outdir))
    open(newunit=u_out, file=trim(outdir) // '/gri_ignition.csv', &
         status='replace', action='write')
    write(u_out, '(a)') '# GRI-Mech 3.0 ignition: stoich CH4/air, 1500 K, 1 atm, constant volume'
    write(u_out, '(a,es26.16e3,a,es26.16e3)') '# t_ign_s = ', t_ign_f, &
        ', T_end_K = ', T(NSAMPLE)
    write(u_out, '(a)') 't_s,T_K,X_CH4,X_O2,X_CO2,X_OH'
    do k = 1, NSAMPLE
        write(u_out, '(*(es26.16e3,:,","))') ts(k), T(k), &
            x_at(1, k), x_at(2, k), x_at(3, k), x_at(4, k)
    end do
    close(u_out)

    ! --- 5. Acceptance vs the native Julia run ----------------------------
    call get_environment_variable('FJ_GRI_NATIVE', native_path, status=st)
    if (st /= 0) native_path = 'gri_native.dat'
    open (newunit=unit_nat, file=trim(native_path), status='old', &
          action='read', iostat=iostat)
    if (iostat /= 0) then
        write (error_unit, '(A)') 'FATAL: native baseline not found at ' // &
            trim(native_path) // ' -- generate it first:' // new_line('a') // &
            '  julia ' // &
            '--project=../../scripts/sysimage_env ' // &
            '../../examples/07_capstone/run_gri_native.jl' // new_line('a') // &
            '  (run from build/examples with the pinned 1.12.7 binary; or ' // &
            'set FJ_GRI_NATIVE to the .dat path)'
        stop 1
    end if
    read (unit_nat, *, iostat=iostat) t_ign_nat, t_end_nat, x_ch4_nat, x_co2_nat
    close (unit_nat)
    if (iostat /= 0) call fail('reading ' // trim(native_path) // &
        ' (stale format: regenerate with the current run_gri_native.jl)')

    ! gate FOUR quantities at the same tolerance: t_ign (the validation
    ! scalar), T_end, and two X spot values that pin the layout-sensitive
    ! 4x2001 column-major matrix extraction (species row 1 at t=0, row 3
    ! at t_end)
    rel = abs(t_ign_f - t_ign_nat) / t_ign_nat
    rel_t = abs(T(NSAMPLE) - t_end_nat) / t_end_nat
    rel_x1 = abs(x_at(1, 1) - x_ch4_nat) / x_ch4_nat
    rel_x2 = abs(x_at(3, NSAMPLE) - x_co2_nat) / x_co2_nat
    print '(A,ES12.4,A,F8.1,A)', ' native t_ign     = ', t_ign_nat * 1.0e3_c_double, &
        ' ms   T_end = ', t_end_nat, ' K'
    print '(A,ES10.2,A,ES10.2,A,ES10.2,A,ES10.2,A,ES10.2,A)', &
        ' rel diff t_ign / T_end / X(ch4,0) / X(co2,end) = ', &
        rel, ' / ', rel_t, ' / ', rel_x1, ' / ', rel_x2, '  (tol ', REL_TOL, ')'
    if (rel < REL_TOL .and. rel_t < REL_TOL .and. rel_x1 < REL_TOL &
        .and. rel_x2 < REL_TOL) then
        print *, 'EX_CAPSTONE_GRI_IGNITION_PASS'
    else
        call fail('bridge vs native rel diff exceeds tolerance (t_ign ' // &
                  trim(real_to_str(rel)) // ', T_end ' // trim(real_to_str(rel_t)) // &
                  ', X spots ' // trim(real_to_str(rel_x1)) // ' / ' // &
                  trim(real_to_str(rel_x2)) // ')')
    end if

    call julia_shutdown()

contains

    ! absolute location of examples/07_capstone/output, resolved from the
    ! running executable the same way the reacting-flow driver does, so
    ! both executables of the merged capstone share one output dir
    function output_dir() result(d)
        character(len=512) :: d
        character(len=:), allocatable :: exe_dir
        character(len=512) :: cwd_
        exe_dir = julia_executable_dir()
        if (len_trim(exe_dir) == 0) error stop 'FATAL: cannot resolve executable dir for output'
        d = trim(exe_dir) // '/../../examples/07_capstone/output'
        if (d(1:1) /= '/') then
            call getcwd(cwd_)
            d = trim(cwd_) // '/' // trim(d)
        end if
    end function output_dir

    subroutine fail(reason)
        character(len=*), intent(in) :: reason
        write (error_unit, '(A)') 'FATAL: ' // trim(reason)
        stop 1
    end subroutine fail

    ! species kk (1..NSP_OUT) of grid point ii (1..NSAMPLE) from the flat copy
    real(kind=c_double) function x_at(kk, ii)
        integer, intent(in) :: kk, ii
        x_at = Xflat((ii - 1) * NSP_OUT + kk)
    end function x_at

    function real_to_str(xval) result(s)
        real(kind=c_double), intent(in) :: xval
        character(len=32) :: s
        write (s, '(ES12.4)') xval
    end function real_to_str

end program ex_capstone_gri_ignition
