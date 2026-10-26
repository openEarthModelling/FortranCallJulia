program ex_reacting_flow
    ! =========================================================================
    ! Capstone example: 1D reacting Euler flow.
    !
    !   transport : vendored Clawpack classic 1D wave-propagation kernel
    !               (third_party/clawpack1d, see SOURCES.md there)
    !   coupling  : Strang operator splitting -- chemistry dt/2, transport dt,
    !               chemistry dt/2 -- implemented HERE in the driver, because
    !               in classic the splitting lives in the time loop (step1
    !               itself never calls a source routine) and this program owns
    !               the time loop.
    !   chemistry : embedded Julia (FjKinetics via the bridge), added in a
    !               later commit. This commit validates the transport engine
    !               alone: Sod's shock tube against the exact Riemann solution
    !               (chemistry disabled, 3-equation pure Euler).
    !
    ! Modes (command line arg 1, default 'sod'):
    !   sod         : Sod tube, exact-solution validation, chemistry off
    !   detonation  : HLW-style detonation with Julia chemistry (later commit)
    !
    ! Optional args: nx (default 400), t_final (default 0.2 for sod).
    ! =========================================================================
    implicit none

    integer, parameter :: mbc = 2          ! ghost cells (clawpack classic 1D)
    integer, parameter :: meqn_max = 4     ! (rho, rhou, E) [+ rho*Y reactive]
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

    ! rp1_euler_with_efix reads gamma through this common block.
    common /cparam/ gamma

    ! --- run parameters ------------------------------------------------------
    character(len=32) :: mode
    integer :: mx, meqn, mwaves, narg, i
    double precision :: gamma, xlower, xupper, x0, dx, t_final, t, dt
    double precision :: cfl_target, cfl_used

    ! --- Sod reference data (validated against the classic setup) ------------
    double precision :: rho_l, u_l, p_l, rho_r, u_r, p_r
    double precision :: pstar, ustar, fstar_residual

    ! --- state / work arrays --------------------------------------------------
    double precision, allocatable :: q(:,:), aux(:,:), f(:,:), s(:,:)
    double precision, allocatable :: wave(:,:,:), amdq(:,:), apdq(:,:), dtdx(:)
    integer :: method(7), mthlim(mwaves_max), mthbc(2)
    logical :: use_fwave

    ! --- validation -----------------------------------------------------------
    double precision :: l1rho, l1u, l1p, sum0(3), sum1(3), mineig
    double precision :: rho_ex, u_ex, p_ex

    ! -----------------------------------------------------------------------
    ! parameters
    ! -----------------------------------------------------------------------
    narg = command_argument_count()
    mode = 'sod'
    if (narg >= 1) call get_command_argument(1, mode)
    mx = 400
    if (narg >= 2) call get_command_arg_int(2, mx)
    t_final = 0.2d0
    if (narg >= 3) call get_command_arg_real(3, t_final)

    select case (trim(mode))
    case ('sod')
        ! 3-equation pure Euler, chemistry disabled.
        meqn = 3
        mwaves = 3
        gamma = 1.4d0
        xlower = 0.0d0
        xupper = 1.0d0
        x0 = 0.5d0
        rho_l = 1.0d0;   u_l = 0.0d0;   p_l = 1.0d0
        rho_r = 0.125d0; u_r = 0.0d0;   p_r = 0.1d0
    case ('detonation')
        print *, 'detonation mode: added in a later commit (Julia chemistry)'
        stop
    case default
        print *, 'unknown mode: ', trim(mode), ' (use: sod | detonation)'
        error stop 1
    end select

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
    ! initial condition
    ! -----------------------------------------------------------------------
    do i = 1-mbc, mx+mbc
        if ((xlower + (dble(i)-0.5d0)*dx) < x0) then
            q(1,i) = rho_l
            q(2,i) = rho_l*u_l
            q(3,i) = p_l/(gamma-1.0d0) + 0.5d0*rho_l*u_l**2
        else
            q(1,i) = rho_r
            q(2,i) = rho_r*u_r
            q(3,i) = p_r/(gamma-1.0d0) + 0.5d0*rho_r*u_r**2
        end if
    end do
    if (meqn == 4) q(4,1-mbc:mx+mbc) = 0.0d0   ! reactive species (later)

    sum0 = 0.0d0
    do i = 1, mx
        sum0 = sum0 + q(1:3,i)
    end do

    ! -----------------------------------------------------------------------
    ! time loop (Strang skeleton: chemistry half-steps are no-ops in sod mode)
    ! -----------------------------------------------------------------------
    t = 0.0d0
    do while (t < t_final)
        ! dt from the max eigenvalue |u| + c of the CURRENT state (rescaling
        ! the previous dt would lag one step behind: after the first step the
        ! star-region speed |u|+c ~ 1.9 far exceeds the initial-data 1.18 and
        ! overshot the CFL), clamped so the last step lands exactly on t_final
        mineig = 0.0d0
        do i = 1, mx
            mineig = max(mineig, abs(q(2,i)/q(1,i)) + &
                         sqrt(gamma*pressure(q(1,i),q(2,i),q(3,i),gamma)/q(1,i)))
        end do
        dt = min(cfl_target*dx/mineig, t_final - t)
        ! call chemistry(dt/2)          ! chemistry OFF in this commit

        call bc1(meqn,mbc,mx,xlower,dx,q,1,aux,t,dt,mthbc)
        call step1(meqn,mwaves,mbc,1,mx,q,aux,dx,dt,method,mthlim, &
                   cfl_used,f,wave,s,amdq,apdq,dtdx,use_fwave,rp1)
        if (cfl_used > 1.0d0) then
            print *, 'WARNING: cfl =', cfl_used, 'exceeded 1 at t =', t
        end if

        ! call chemistry(dt/2)          ! chemistry OFF in this commit
        t = t + dt
    end do

    ! -----------------------------------------------------------------------
    ! validation against the exact Riemann solution
    ! -----------------------------------------------------------------------
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

contains

    function pressure(rho, rhou, E, gam)
        double precision, intent(in) :: rho, rhou, E, gam
        double precision :: pressure
        pressure = (gam-1.0d0)*(E - 0.5d0*rhou**2/rho)
    end function pressure

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
