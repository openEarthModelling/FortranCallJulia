program ex_reacting_flow
    ! =========================================================================
    ! Capstone example: 1D reacting Euler flow.
    !
    !   transport : vendored Clawpack classic 1D wave-propagation kernel
    !               (third_party/clawpack1d, see SOURCES.md there); the
    !               4-equation Riemann solver rp1_reacting.f90 (same
    !               directory) extends the vendored Roe+efix solver to the
    !               reactive state (rho, rho*u, E, rho*Z) -- see its header
    !               for the conservative-linearization identities.
    !   coupling  : Strang operator splitting -- chemistry dt/2, transport dt,
    !               chemistry dt/2 -- implemented HERE in the driver, because
    !               in classic the splitting lives in the time loop (step1
    !               itself never calls a source routine) and this program owns
    !               the time loop.
    !   chemistry : embedded Julia.  FjKinetics (src/FjKinetics, Catalyst +
    !               OrdinaryDiffEq) integrates the stiff Arrhenius system
    !               dF/dt = -k(T) F, dT/dt = (q/cv) k(T) F for every active
    !               cell in ONE batched call per half-step, through the
    !               persistent zero-copy wrapped buffers FJ_Y / FJ_T /
    !               FJ_RHO in Main (julia_wrap_array_2d/1d + set_field) --
    !               one julia_eval per Strang half-step, no per-cell traffic.
    !               The chemistry step conserves rho, rho*u, E: Fortran
    !               writes back only q(4) = rho * F_new (temperature and
    !               pressure rise implicitly through E).
    !
    ! Modes (command line arg 1, default 'sod'):
    !   sod         : Sod tube, exact-solution validation, chemistry off
    !   detonation  : Helmholtz-Lang-Warnecke (2000) Ex. 2: CJ detonation,
    !                 gamma=1.4, K(T)=K0*exp(-E+/T) with K0=164180, E+=25,
    !                 q0=25, R=1; CJ speed s=7.1247, validated to 2%.
    !                 Burnt driver gas left of x0, unburnt gas right.
    !
    ! Optional args: nx (sod 400 / detonation 2700), t_final (sod 0.2 /
    ! detonation 0.3), julia mode 'jit' | 'sysimage' (detonation only).
    !
    ! Paths default to the in-tree layout relative to the executable;
    ! overrides: FJ_KINETICS_PROJECT (project with FjKinetics),
    ! FJ_SCIML_SYSIMAGE (sysimage, for mode=sysimage).
    ! =========================================================================
    use iso_c_binding
    use, intrinsic :: iso_fortran_env, only: error_unit
    use julia_high_level
    implicit none

    integer, parameter :: mbc = 2          ! ghost cells (clawpack classic 1D)
    integer, parameter :: meqn_max = 4     ! (rho, rhou, E) [+ rho*Z reactive]
    integer, parameter :: mwaves_max = 4   ! 3 Euler waves [+ passive species]

    ! --- vendored classic interfaces ----------------------------------------
    interface
        subroutine step1(num_eqn,num_waves,num_ghost,num_aux,mx,q,aux,dx,dt, &
                         method,mthlim,cfl,f,wave,s,amdq,apdq,dtdx,use_fwave,rp1)
            integer :: num_eqn, num_waves, num_ghost, num_aux, mx
            integer :: method(7), mthlim(num_waves)
            double precision :: q(num_eqn,1-num_ghost:mx+num_ghost)
            double precision :: aux(num_aux,1-num_ghost:mx+num_ghost)
            double precision :: dx, dt, cfl
            double precision :: f(num_eqn,1-num_ghost:mx+num_ghost)
            double precision :: s(num_waves,1-num_ghost:mx+num_ghost)
            double precision :: wave(num_eqn,num_waves,1-num_ghost:mx+num_ghost)
            double precision :: amdq(num_eqn,1-num_ghost:mx+num_ghost)
            double precision :: apdq(num_eqn,1-num_ghost:mx+num_ghost)
            double precision :: dtdx(1-num_ghost:mx+num_ghost)
            logical :: use_fwave
            external :: rp1
        end subroutine step1

        subroutine bc1(meqn,mbc,mx,xlower,dx,q,maux,aux,t,dt,mthbc)
            integer :: meqn, mbc, mx, maux, mthbc(2)
            double precision :: xlower, dx, t, dt
            double precision :: q(meqn,1-mbc:mx+mbc)
            double precision :: aux(maux,1-mbc:mx+mbc)
        end subroutine bc1
    end interface
    ! vendored 3-eq Roe solver + entropy fix (the file is named
    ! rp1_euler_with_efix.f90 but the routine itself is called rp1)
    external :: rp1
    ! app-layer 4-eq reacting Roe solver (rp1_reacting.f90)
    external :: rp1_reacting

    ! rp1 / rp1_reacting read gamma through /cparam/; rp1_reacting also
    ! reads the heat release q0 through /rparam/.
    common /cparam/ gamma
    common /rparam/ q0

    ! --- run parameters ------------------------------------------------------
    character(len=32) :: mode, jmode
    integer :: mx, meqn, mwaves, narg, i
    double precision :: gamma, q0, xlower, xupper, x0, dx, t_final, t, dt
    double precision :: cfl_target, cfl_used

    ! --- Sod reference data (validated against the classic setup) ------------
    double precision :: rho_l, u_l, p_l, rho_r, u_r, p_r
    double precision :: z_l, z_r          ! initial unburnt mass fractions
    double precision :: pstar, ustar, fstar_residual

    ! --- detonation (HLW Ex. 2) parameters ------------------------------------
    double precision, parameter :: scj    = 7.1247d0  ! CJ detonation speed
    double precision, parameter :: rho_cj = 1.6812d0  ! CJ burnt state
    double precision, parameter :: u_cj   = 2.8867d0
    double precision, parameter :: p_cj   = 21.5672d0
    double precision :: K0, Ea, Rg       ! Arrhenius: k(T)=K0*exp(-Ea/(Rg*T))
    double precision, parameter :: t_cut = 1.5d0      ! active-set thresholds:
    double precision, parameter :: z_floor = 1.0d-12  ! frozen cells are skipped
    ! (at T <= t_cut, k(T) = 3.6d-4 and the induction time exceeds the whole
    !  simulation by orders of magnitude, so skipping them is exact to run
    !  precision; cells are only skipped while chemically inert)

    ! --- chemistry bridge state ------------------------------------------------
    logical :: chemistry_on
    type(JuliaValue) :: v_main, v_res
    double precision, allocatable, target :: ybuf(:,:), tbuf(:), rbuf(:)
    integer, allocatable :: iact(:)
    integer :: n_act, nsteps, nchem, ncells_chem, n_bridge, n_bridge_init, n_bridge_chem
    character(len=512) :: project_path, image_path, cwd, expr
    character(len=64) :: dts
    character(len=:), allocatable :: msg
    integer :: st
    logical :: lex

    ! --- detonation validation / measurement ------------------------------------
    logical :: mark_set
    double precision :: xfa, xfb, tfa, dspeed, zl_, zr_
    integer :: i_front, i_s

    ! --- performance counters (harvested by the perf report) --------------------
    integer(kind=8) :: c0, c1, crate, c_chem0
    double precision :: t_init, t_first_chem, t_chem, t_chem_last, t_total

    ! --- state / work arrays ------------------------------------------------------
    double precision, allocatable :: q(:,:), aux(:,:), f(:,:), s(:,:)
    double precision, allocatable :: wave(:,:,:), amdq(:,:), apdq(:,:), dtdx(:)
    integer :: method(7), mthlim(mwaves_max), mthbc(2)
    logical :: use_fwave

    ! --- validation (sod) -----------------------------------------------------------
    double precision :: l1rho, l1u, l1p, sum0(3), sum1(3), mineig
    double precision :: rho_ex, u_ex, p_ex

    ! -----------------------------------------------------------------------
    ! parameters
    ! -----------------------------------------------------------------------
    narg = command_argument_count()
    mode = 'sod'
    if (narg >= 1) call get_command_argument(1, mode)
    mx = 0
    if (narg >= 2) call get_command_arg_int(2, mx)
    t_final = -1.0d0
    if (narg >= 3) call get_command_arg_real(3, t_final)
    jmode = 'jit'
    if (narg >= 4) call get_command_argument(4, jmode)

    select case (trim(mode))
    case ('sod')
        ! 3-equation pure Euler, chemistry disabled.
        meqn = 3
        mwaves = 3
        gamma = 1.4d0
        q0 = 0.0d0
        xlower = 0.0d0
        xupper = 1.0d0
        x0 = 0.5d0
        if (mx == 0) mx = 400
        if (t_final < 0.0d0) t_final = 0.2d0
        rho_l = 1.0d0;   u_l = 0.0d0;   p_l = 1.0d0;   z_l = 0.0d0
        rho_r = 0.125d0; u_r = 0.0d0;   p_r = 0.1d0;   z_r = 0.0d0
    case ('detonation')
        ! 4-equation reacting Euler; E includes the chemical term q0*rho*Z.
        ! Self-similar CJ detonation: burnt driver gas left of x0 pushes a
        ! shock into the unburnt gas; everything is scaled into [0,3].
        meqn = 4
        mwaves = 4
        gamma = 1.4d0
        q0 = 25.0d0
        K0 = 164180.0d0
        Ea = 25.0d0
        Rg = 1.0d0
        xlower = 0.0d0
        xupper = 3.0d0
        x0 = 0.3d0
        if (mx == 0) mx = 2700
        if (t_final < 0.0d0) t_final = 0.3d0
        rho_l = rho_cj; u_l = u_cj; p_l = p_cj; z_l = 0.0d0
        rho_r = 1.0d0;  u_r = 0.0d0; p_r = 1.0d0; z_r = 1.0d0
    case default
        print *, 'unknown mode: ', trim(mode), ' (use: sod | detonation)'
        error stop 1
    end select

    chemistry_on = (trim(mode) == 'detonation')
    dx = (xupper - xlower) / mx
    cfl_target = 0.8d0
    use_fwave = .false.

    ! classic method vector: method(2)=2 -> second order (wave limiter
    ! corrections); method(6)=0 -> no capacity function. minmod limiter
    ! (mthlim=1) in every family.
    method = 0
    method(2) = 2
    mthlim = 1
    mthbc = 1            ! zero-order extrapolation at both ends (outflow)

    allocate(q(meqn,1-mbc:mx+mbc), aux(1,1-mbc:mx+mbc), f(meqn,1-mbc:mx+mbc), &
             s(mwaves,1-mbc:mx+mbc), wave(meqn,mwaves,1-mbc:mx+mbc), &
             amdq(meqn,1-mbc:mx+mbc), apdq(meqn,1-mbc:mx+mbc), &
             dtdx(1-mbc:mx+mbc))

    ! -----------------------------------------------------------------------
    ! embedded-Julia chemistry (detonation mode): init, import FjKinetics,
    ! build the solver, publish the persistent zero-copy buffers in Main
    ! -----------------------------------------------------------------------
    t_init = 0.0d0; t_first_chem = 0.0d0; t_chem = 0.0d0
    nchem = 0; ncells_chem = 0; nsteps = 0
    n_bridge = 0; n_bridge_init = 0; n_bridge_chem = 0
    if (chemistry_on) then
        block
            character(len=:), allocatable :: exe_dir
            exe_dir = julia_executable_dir()
            ! env override > exe-relative default (an unset variable blanks
            ! the value argument, so defaults are restored on st /= 0)
            ! the project must carry BOTH FortranBridge (the bridge loads
            ! it from the activated environment) and FjKinetics: the shared
            ! scratch env scripts/sysimage_env dev's both
            project_path = exe_dir // '/../../scripts/sysimage_env'
            image_path = exe_dir // '/../libfj_sysimage.so'
            call get_environment_variable('FJ_KINETICS_PROJECT', project_path, status=st)
            if (st /= 0) project_path = exe_dir // '/../../scripts/sysimage_env'
            call get_environment_variable('FJ_SCIML_SYSIMAGE', image_path, status=st)
            if (st /= 0) image_path = exe_dir // '/../libfj_sysimage.so'
            if (project_path(1:1) /= '/') then
                call getcwd(cwd)
                project_path = trim(cwd) // '/' // trim(project_path)
            end if
            if (image_path(1:1) /= '/') then
                call getcwd(cwd)
                image_path = trim(cwd) // '/' // trim(image_path)
            end if
            inquire(file=trim(project_path) // '/Project.toml', exist=lex)
            if (.not. lex) then
                write (error_unit, '(a)') 'FATAL: FjKinetics project not found at ' // &
                    trim(project_path) // ' (set FJ_KINETICS_PROJECT)'
                error stop 1
            end if

            call system_clock(c0, crate)
            if (trim(jmode) == 'sysimage') then
                inquire(file=trim(image_path), exist=lex)
                if (.not. lex) then
                    write (error_unit, '(a)') 'FATAL: sysimage not found at ' // &
                        trim(image_path) // ' (set FJ_SCIML_SYSIMAGE)'
                    error stop 1
                end if
                print '(a,a,a,a)', 'detonation: julia mode=sysimage image=', trim(image_path), &
                    ' project=', trim(project_path)
                call julia_init_ex(image_path=trim(image_path), project_path=trim(project_path))
            else
                print '(a,a,a)', 'detonation: julia mode=jit project=', trim(project_path)
                call julia_init_ex(project_path=trim(project_path))
            end if
            n_bridge = n_bridge + 1          ! julia_init_ex

            v_res = julia_eval('1 + 1')
            n_bridge = n_bridge + 1
            if (.not. v_res%is_valid() .or. v_res%as_integer() /= 2) then
                msg = get_last_error_message()
                write (error_unit, '(a)') 'FATAL: Julia runtime init failed: ' // trim(msg)
                error stop 1
            end if

            call julia_eval_string('import FjKinetics')
            n_bridge = n_bridge + 1
            ! cv = Rg/(gamma-1) keeps the mechanism exactly equivalent to the
            ! HLW constant-(rho,rho*u,E) chemical step (see FjKinetics.jl)
            write (expr, '(a,es24.16,a,es24.16,a,es24.16,a,es24.16,a,es24.16,a)') &
                'FJ_KS = FjKinetics.build_kinetics(A=', K0, ', Ea=', Ea, ', R_g=', Rg, &
                ', q=', q0, ', cv=', Rg/(gamma-1.0d0), ')'
            v_res = julia_eval(trim(expr))
            n_bridge = n_bridge + 1
            if (.not. v_res%is_valid()) then
                msg = get_last_error_message()
                write (error_unit, '(a)') 'FATAL: build_kinetics failed: ' // trim(msg)
                error stop 1
            end if
            v_res = julia_eval('FjKinetics.nspecies(FJ_KS)')
            n_bridge = n_bridge + 1
            if (.not. v_res%is_valid() .or. v_res%as_integer() /= 2) then
                write (error_unit, '(a)') 'FATAL: FjKinetics mechanism must have 2 species'
                error stop 1
            end if

            ! persistent zero-copy buffers: wrapped once, mutated in place by
            ! every batched step_chemistry! (no data crosses the bridge)
            allocate (ybuf(mx,2), tbuf(mx), rbuf(mx), iact(mx))
            ybuf = 0.0d0; tbuf = 0.0d0; rbuf = 0.0d0
            v_main = julia_eval('Main')
            n_bridge = n_bridge + 1
            ! Julia 1.12 forbids setproperty! creating new globals (#56933);
            ! declare the bindings first, then assign through set_field
            call julia_eval_string('global FJ_Y, FJ_T, FJ_RHO')
            n_bridge = n_bridge + 1
            v_res = julia_wrap_array_2d(ybuf, int(mx, c_int64_t), 2_c_int64_t)
            if (.not. v_res%is_valid()) error stop 'FATAL: wrap ybuf failed'
            call v_main%set_field('FJ_Y', v_res)
            n_bridge = n_bridge + 2
            v_res = julia_wrap_array_1d(tbuf, int(mx, c_int64_t))
            if (.not. v_res%is_valid()) error stop 'FATAL: wrap tbuf failed'
            call v_main%set_field('FJ_T', v_res)
            n_bridge = n_bridge + 2
            v_res = julia_wrap_array_1d(rbuf, int(mx, c_int64_t))
            if (.not. v_res%is_valid()) error stop 'FATAL: wrap rbuf failed'
            call v_main%set_field('FJ_RHO', v_res)
            n_bridge = n_bridge + 2
            n_bridge_init = n_bridge
            call system_clock(c1)
            t_init = dble(c1 - c0)/dble(crate)
            print '(a,es12.3,a)', 'julia init: ', t_init, ' s'
        end block
    end if

    ! -----------------------------------------------------------------------
    ! initial condition (E carries the chemical energy q0*rho*Z; q0 = 0 for sod)
    ! -----------------------------------------------------------------------
    do i = 1-mbc, mx+mbc
        if ((xlower + (dble(i)-0.5d0)*dx) < x0) then
            q(1,i) = rho_l
            q(2,i) = rho_l*u_l
            q(3,i) = p_l/(gamma-1.0d0) + 0.5d0*rho_l*u_l**2 + q0*rho_l*z_l
            if (meqn == 4) q(4,i) = rho_l*z_l
        else
            q(1,i) = rho_r
            q(2,i) = rho_r*u_r
            q(3,i) = p_r/(gamma-1.0d0) + 0.5d0*rho_r*u_r**2 + q0*rho_r*z_r
            if (meqn == 4) q(4,i) = rho_r*z_r
        end if
    end do

    sum0 = 0.0d0
    do i = 1, mx
        sum0 = sum0 + q(1:3,i)
    end do

    ! -----------------------------------------------------------------------
    ! time loop: Strang splitting (chemistry dt/2 - transport dt - chemistry
    ! dt/2); in sod mode chemistry() is a no-op
    ! -----------------------------------------------------------------------
    call system_clock(c0)
    t = 0.0d0
    mark_set = .false.
    do while (t < t_final)
        ! dt from the max eigenvalue |u| + c of the CURRENT state (rescaling
        ! the previous dt would lag one step behind: after the first step the
        ! star-region speed |u|+c ~ 1.9 far exceeds the initial-data 1.18 and
        ! overshot the CFL), clamped so the last step lands exactly on t_final
        mineig = 0.0d0
        do i = 1, mx
            mineig = max(mineig, abs(q(2,i)/q(1,i)) + &
                         sqrt(gamma*p_i(i)/q(1,i)))
        end do
        dt = min(cfl_target*dx/mineig, t_final - t)

        call chemistry(dt/2)
        ! t_first_chem is clocked inside chemistry() itself (c_chem0 is its
        ! entry stamp), so it covers pack + first-call JIT compilation
        if (nchem == 1 .and. t_first_chem == 0.0d0) then
            t_first_chem = t_chem_last
        end if

        call bc1(meqn,mbc,mx,xlower,dx,q,1,aux,t,dt,mthbc)
        if (meqn == 4) then
            call step1(meqn,mwaves,mbc,1,mx,q,aux,dx,dt,method,mthlim, &
                       cfl_used,f,wave,s,amdq,apdq,dtdx,use_fwave,rp1_reacting)
        else
            call step1(meqn,mwaves,mbc,1,mx,q,aux,dx,dt,method,mthlim, &
                       cfl_used,f,wave,s,amdq,apdq,dtdx,use_fwave,rp1)
        end if
        if (cfl_used > 1.0d0) then
            print *, 'WARNING: cfl =', cfl_used, 'exceeded 1 at t =', t
        end if

        call chemistry(dt/2)
        t = t + dt
        nsteps = nsteps + 1

        ! detonation-speed measurement window: second half of the run
        if (chemistry_on .and. .not. mark_set .and. t >= 0.5d0*t_final) then
            xfa = front_x()
            tfa = t
            mark_set = .true.
        end if
    end do
    call system_clock(c1)
    t_total = dble(c1 - c0)/dble(crate)

    ! -----------------------------------------------------------------------
    ! validation
    ! -----------------------------------------------------------------------
    if (.not. chemistry_on) then
        call sod_star_state(p_l, rho_l, u_l, p_r, rho_r, u_r, gamma, pstar, ustar, fstar_residual)

        l1rho = 0.0d0; l1u = 0.0d0; l1p = 0.0d0
        do i = 1, mx
            call sod_sample(p_l, rho_l, u_l, p_r, rho_r, u_r, gamma, &
                            pstar, ustar, xlower + (dble(i)-0.5d0)*dx - x0, t, &
                            rho_ex, u_ex, p_ex)
            l1rho = l1rho + abs(q(1,i) - rho_ex)
            l1u = l1u + abs(q(2,i)/q(1,i) - u_ex)
            l1p = l1p + abs(pressure(q(1,i),q(2,i),q(3,i),gamma) - p_ex)
        end do
        l1rho = l1rho/mx; l1u = l1u/mx; l1p = l1p/mx

        sum1 = 0.0d0
        do i = 1, mx
            sum1 = sum1 + q(1:3,i)
        end do

        print '(a)', '===================================================='
        print '(a,i0,a,f10.6,a,es11.3)', 'Sod validation: nx = ', mx, ', t = ', t, &
             ', star-residual = ', fstar_residual
        print '(a,3(es11.3))', 'L1 errors (rho, u, p): ', l1rho, l1u, l1p
        print '(a,es11.3)', 'mass/energy drift: ', maxval(abs([sum1(1)-sum0(1), sum1(3)-sum0(3)]))
        print '(a,es11.3,a,es11.3)', 'momentum change vs pressure impulse (pL-pR)*t: ', &
             (sum1(2)-sum0(2))*dx, ' vs ', (p_l-p_r)*t

        if (minval(q(1,1:mx)) <= 0.0d0) error stop 'FAIL: non-positive density'
        if (l1rho > 2.0d-2) error stop 'FAIL: L1(rho) too large'
        if (l1u  > 2.0d-2) error stop 'FAIL: L1(u) too large'
        if (l1p  > 1.0d-2) error stop 'FAIL: L1(p) too large'
        if (abs(fstar_residual) > 1.0d-10) error stop 'FAIL: star-state solve'
        ! mass and total energy are invariants; momentum is not (outflow
        ! boundaries exert the net pressure force): it must match the impulse
        if (abs(sum1(1)-sum0(1)) > 1.0d-9*abs(sum0(1))) error stop 'FAIL: mass drift'
        if (abs(sum1(3)-sum0(3)) > 1.0d-9*abs(sum0(3))) error stop 'FAIL: energy drift'
        if (abs((sum1(2)-sum0(2))*dx - (p_l-p_r)*t) > 1.0d-2*(p_l-p_r)*t) &
            error stop 'FAIL: momentum does not match pressure impulse'
        print '(a)', 'SOD_VALIDATION_PASS'
        print '(a)', '===================================================='
    else
        ! ---- HLW Ex. 2: CJ detonation speed and burnt state -----------------
        xfb = front_x()
        dspeed = (xfb - xfa)/(t - tfa)

        i_front = 0
        do i = mx, 1, -1
            if (q(4,i)/q(1,i) < 0.5d0) then
                i_front = i
                exit
            end if
        end do
        i_s = max(1, i_front - 100)

        print '(a)', '===================================================='
        print '(a,i0,a,f8.4)', 'Detonation validation (HLW Ex.2): nx = ', mx, ', t = ', t
        print '(a,f10.5,a,f10.5)', 'front: x(t_a) = ', xfa, '  x(t_b) = ', xfb
        print '(a,f10.5,a,f9.5,a,f7.3,a)', 'detonation speed: ', dspeed, &
            '  (exact s_CJ = ', scj, ', deviation ', 100.0d0*abs(dspeed-scj)/scj, '%)'
        print '(a,3(f10.5))', 'burnt state behind front (rho,u,p): ', &
            q(1,i_s), q(2,i_s)/q(1,i_s), p_i(i_s)
        print '(a,3(f10.5))', 'CJ reference                    : ', rho_cj, u_cj, p_cj
        print '(a,i0,a,i0)', 'steps = ', nsteps, '  chemistry half-steps = ', nchem
        print '(a,i0,a)', 'active cells processed by chemistry: ', ncells_chem, &
            ' (frozen cells skipped, see t_cut)'
        print '(a,es12.3,a,es12.3,a)', 'timing: init ', t_init, ' s, first chem half-step ', &
            t_first_chem, ' s'
        print '(a,es12.3,a,es12.3,a)', '        chemistry total ', t_chem, ' s, run total ', &
            t_total, ' s'
        print '(a,i0,a,i0,a,i0)', 'bridge calls: ', n_bridge + 1, ' (init/setup ', n_bridge_init, &
            ' + chemistry ', n_bridge_chem, ' + shutdown 1)'

        if (minval(q(1,1:mx)) <= 0.0d0) error stop 'FAIL: non-positive density'
        if (minval([(p_i(i), i=1,mx)]) <= 0.0d0) error stop 'FAIL: non-positive pressure'
        if (.not. mark_set .or. xfa <= xlower) error stop 'FAIL: front never entered window'
        if (xfb > xupper - 10.0d0*dx) error stop 'FAIL: front reached the right boundary'
        if (abs(dspeed - scj) > 2.0d-2*scj) then
            print '(a)', 'FAIL: detonation speed outside the 2% band (weak-detonation ' // &
                'under-resolution? raise nx)'
            error stop 1
        end if
        if (abs(q(1,i_s) - rho_cj) > 0.1d0*rho_cj .or. &
            abs(q(2,i_s)/q(1,i_s) - u_cj) > 0.1d0*u_cj .or. &
            abs(p_i(i_s) - p_cj) > 0.1d0*p_cj) then
            error stop 'FAIL: burnt state deviates from CJ by more than 10%'
        end if
        print '(a)', 'DETONATION_VALIDATION_PASS'
        print '(a)', '===================================================='

        call julia_shutdown()
    end if

contains

    ! pressure in cell i, q0-aware (q0 = 0 in sod mode; q(4,:) pre-zeroed)
    function p_i(i)
        integer, intent(in) :: i
        double precision :: p_i
        if (meqn == 4) then
            p_i = (gamma-1.0d0)*(q(3,i) - 0.5d0*q(2,i)**2/q(1,i) - q0*q(4,i))
        else
            p_i = (gamma-1.0d0)*(q(3,i) - 0.5d0*q(2,i)**2/q(1,i))
        end if
    end function p_i

    function pressure(rho, rhou, E, gam)
        double precision, intent(in) :: rho, rhou, E, gam
        double precision :: pressure
        pressure = (gam-1.0d0)*(E - 0.5d0*rhou**2/rho)
    end function pressure

    ! shock-front position: scan from the RIGHT for the last cell whose
    ! unburnt fraction dropped below 0.5 (everything left of it is burnt,
    ! the driver gas itself starts burnt, so a left-to-right scan would
    ! find cell 1), refined by linear interpolation of Z between the
    ! burnt cell i and the fresh cell i+1
    function front_x()
        double precision :: front_x
        integer :: i
        do i = mx, 1, -1
            if (q(4,i)/q(1,i) < 0.5d0) then
                if (i == mx) then
                    front_x = xlower + dble(mx)*dx   ! degenerate: front at edge
                    return
                end if
                zl_ = q(4,i)/q(1,i)
                zr_ = q(4,i+1)/q(1,i+1)
                if (zr_ > zl_) then
                    front_x = xlower + (dble(i)-0.5d0)*dx + (0.5d0-zl_)/(zr_-zl_)*dx
                else
                    front_x = xlower + (dble(i)-0.5d0)*dx
                end if
                return
            end if
        end do
        front_x = -1.0d0     ! no burnt cell found
    end function front_x

    ! Strang chemistry half-step.  Active cells (Z > z_floor, T > t_cut --
    ! frozen cells cannot react on run timescales, so skipping them is exact
    ! to run precision) are packed into the persistent buffers FJ_Y/FJ_T/
    ! FJ_RHO published in Main; ONE batched step_chemistry! call advances
    ! them.  The chemistry conserves (rho, rho*u, E), so only q(4) = rho*F
    ! is written back; T and p rise implicitly through E.
    subroutine chemistry(dt_half)
        double precision, intent(in) :: dt_half
        integer :: j, i
        double precision :: zi, ti
        if (.not. chemistry_on) return

        call system_clock(c_chem0)
        n_act = 0
        do i = 1, mx
            zi = q(4,i)/q(1,i)
            if (zi <= z_floor) cycle
            ti = p_i(i)/(q(1,i)*Rg)
            if (ti <= t_cut) cycle
            n_act = n_act + 1
            ybuf(n_act,1) = zi
            ybuf(n_act,2) = 1.0d0 - zi
            tbuf(n_act) = ti
            rbuf(n_act) = q(1,i)
            iact(n_act) = i
        end do
        nchem = nchem + 1
        ncells_chem = ncells_chem + n_act

        if (n_act > 0) then
            ! dt_half rides through the expression string with full Float64
            ! round-trip precision (17 significant digits)
            write (dts, '(es24.16)') dt_half
            write (expr, '(a,i0,a,i0,a,i0,a)') &
                'FjKinetics.step_chemistry!(FJ_KS, view(FJ_Y,1:', n_act, &
                ',:), view(FJ_T,1:', n_act, '), view(FJ_RHO,1:', n_act, &
                '), ' // trim(dts) // ')'
            v_res = julia_eval(trim(expr))
            n_bridge = n_bridge + 1
            n_bridge_chem = n_bridge_chem + 1
            if (.not. v_res%is_valid()) then
                msg = get_last_error_message()
                write (error_unit, '(a)') 'FATAL: step_chemistry! failed: ' // trim(msg)
                error stop 1
            end if
            do j = 1, n_act
                q(4,iact(j)) = rbuf(j)*ybuf(j,1)
            end do
        end if
        call system_clock(c1)
        t_chem_last = dble(c1 - c_chem0)/dble(crate)
        t_chem = t_chem + t_chem_last
    end subroutine chemistry

    ! f_K(p): velocity jump across a shock (p > pK) or rarefaction (p <= pK)
    ! (Toro, Riemann Solvers, Ch. 4). Monotonically increasing in p.
    function fK(p, pK, rhoK, uK, gam)
        double precision, intent(in) :: p, pK, rhoK, uK, gam
        double precision :: fK, cK, AK, BK
        cK = sqrt(gam*pK/rhoK)
        if (p > pK) then
            AK = 2.0d0/((gam+1.0d0)*rhoK)
            BK = (gam-1.0d0)/(gam+1.0d0)*pK
            fK = (p - pK)*sqrt(AK/(p + BK))
        else
            fK = 2.0d0*cK/(gam-1.0d0)*((p/pK)**((gam-1.0d0)/(2.0d0*gam)) - 1.0d0)
        end if
    end function fK

    ! Solve fL(p*) + fR(p*) + uR - uL = 0 for p* by bisection (f is monotone
    ! increasing, so bisection is robust; 200 halvings reach machine precision
    ! on any sane bracket) and set u* = (uL+uR)/2 + (fR(p*)-fL(p*))/2.
    subroutine sod_star_state(pL, rhoL, uL, pR, rhoR, uR, gam, pstar, ustar, resid)
        double precision, intent(in) :: pL, rhoL, uL, pR, rhoR, uR, gam
        double precision, intent(out) :: pstar, ustar, resid
        double precision :: plo, phi, pmid
        integer :: it
        plo = 1.0d-8*min(pL,pR)
        phi = 1.0d2*max(pL,pR)
        do it = 1, 200
            pmid = 0.5d0*(plo + phi)
            if (gfun(pmid,pL,rhoL,uL,pR,rhoR,uR,gam) > 0.0d0) then
                phi = pmid
            else
                plo = pmid
            end if
        end do
        pstar = 0.5d0*(plo + phi)
        ustar = 0.5d0*(uL + uR) + 0.5d0*(fK(pstar,pR,rhoR,uR,gam) - fK(pstar,pL,rhoL,uL,gam))
        resid = gfun(pstar,pL,rhoL,uL,pR,rhoR,uR,gam)
    end subroutine sod_star_state

    ! fL(p) + fR(p) + uR - uL -- the function bisected in sod_star_state.
    function gfun(p, pL, rhoL, uL, pR, rhoR, uR, gam)
        double precision, intent(in) :: p, pL, rhoL, uL, pR, rhoR, uR, gam
        double precision :: gfun
        gfun = fK(p,pL,rhoL,uL,gam) + fK(p,pR,rhoR,uR,gam) + uR - uL
    end function gfun

    ! Sample the exact solution at xi = x - x0, time t (Toro Ch. 4.5).
    subroutine sod_sample(pL, rhoL, uL, pR, rhoR, uR, gam, pstar, ustar, xi, t, rho, u, p)
        double precision, intent(in) :: pL, rhoL, uL, pR, rhoR, uR, gam
        double precision, intent(in) :: pstar, ustar, xi, t
        double precision, intent(out) :: rho, u, p
        double precision :: w, cL, cR, cstarL, cstarR, rhoSL, rhoSR, SL, SR, rhoLs, rhoRs
        w = xi/t
        cL = sqrt(gam*pL/rhoL)
        cR = sqrt(gam*pR/rhoR)
        cstarL = cL*(pstar/pL)**((gam-1.0d0)/(2.0d0*gam))
        cstarR = cR*(pstar/pR)**((gam-1.0d0)/(2.0d0*gam))
        ! post-shock densities (needed for the shock branches; harmless to
        ! compute even when that side is a rarefaction)
        rhoSL = rhoL*((pstar/pL) + (gam-1.0d0)/(gam+1.0d0)) / &
                    ((gam-1.0d0)/(gam+1.0d0)*(pstar/pL) + 1.0d0)
        rhoSR = rhoR*((pstar/pR) + (gam-1.0d0)/(gam+1.0d0)) / &
                    ((gam-1.0d0)/(gam+1.0d0)*(pstar/pR) + 1.0d0)

        if (w < ustar) then
            ! ----- left of the contact -----
            if (pstar > pL) then
                ! left shock
                SL = uL - cL*sqrt((gam+1.0d0)/(2.0d0*gam)*(pstar/pL) + (gam-1.0d0)/(2.0d0*gam))
                if (w < SL) then
                    rho = rhoL; u = uL; p = pL
                else
                    rho = rhoSL; u = ustar; p = pstar
                end if
            else
                ! left rarefaction
                if (w < uL - cL) then
                    rho = rhoL; u = uL; p = pL
                else if (w > ustar - cstarL) then
                    rho = rhoL*(pstar/pL)**(1.0d0/gam); u = ustar; p = pstar
                else
                    u = 2.0d0/(gam+1.0d0)*(cL + 0.5d0*(gam-1.0d0)*uL + w)
                    cstarL = cL + 0.5d0*(gam-1.0d0)*(uL - u)   ! c inside the fan
                    p = pL*(cstarL/cL)**(2.0d0*gam/(gam-1.0d0))
                    rho = rhoL*(cstarL/cL)**(2.0d0/(gam-1.0d0))
                end if
            end if
        else
            ! ----- right of the contact -----
            if (pstar > pR) then
                ! right shock
                SR = uR + cR*sqrt((gam+1.0d0)/(2.0d0*gam)*(pstar/pR) + (gam-1.0d0)/(2.0d0*gam))
                if (w > SR) then
                    rho = rhoR; u = uR; p = pR
                else
                    rho = rhoSR; u = ustar; p = pstar
                end if
            else
                ! right rarefaction
                if (w > uR + cR) then
                    rho = rhoR; u = uR; p = pR
                else if (w < ustar + cstarR) then
                    rho = rhoR*(pstar/pR)**(1.0d0/gam); u = ustar; p = pstar
                else
                    u = 2.0d0/(gam+1.0d0)*(-cR + 0.5d0*(gam-1.0d0)*uR + w)
                    cstarR = cR - 0.5d0*(gam-1.0d0)*(uR - u)   ! c inside the fan
                    p = pR*(cstarR/cR)**(2.0d0*gam/(gam-1.0d0))
                    rho = rhoR*(cstarR/cR)**(2.0d0/(gam-1.0d0))
                end if
            end if
        end if
    end subroutine sod_sample

    subroutine get_command_arg_int(idx, val)
        integer, intent(in) :: idx
        integer, intent(out) :: val
        character(len=32) :: buf
        integer :: ios
        call get_command_argument(idx, buf)
        read(buf,*,iostat=ios) val
        if (ios /= 0) error stop 'bad integer command argument'
    end subroutine get_command_arg_int

    subroutine get_command_arg_real(idx, val)
        integer, intent(in) :: idx
        double precision, intent(out) :: val
        character(len=32) :: buf
        integer :: ios
        call get_command_argument(idx, buf)
        read(buf,*,iostat=ios) val
        if (ios /= 0) error stop 'bad real command argument'
    end subroutine get_command_arg_real

end program ex_reacting_flow
