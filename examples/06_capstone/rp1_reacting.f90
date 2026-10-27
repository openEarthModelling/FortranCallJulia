! =========================================================================
! rp1_reacting: approximate Riemann solver for the 1D REACTING Euler
! equations, derived from the vendored third_party/clawpack1d
! rp1_euler_with_efix.f90 (Roe solver + entropy fix) by the substitution
!
!     ets = E - q0 * rho*Z        (sensible + kinetic energy)
!
! where E is the TOTAL energy (including chemical) carried in q(3) and
! rho*Z the unburnt-gas mass in q(4).  The Euler flux never sees the
! chemical term, so waves 1..3 are the vendored Roe waves of the
! (rho, rho*u, ets) subsystem; delta(3) below is the ets jump.
!
! Species row (exact Roe linearization of the passive scalar rho*Z).
! With sqrt(rho)-weighted Roe averages
!     ubar = (sqrt(rhoL)uL + sqrt(rhoR)uR) / (sqrt(rhoL)+sqrt(rhoR)),
!     Zbar = (sqrt(rhoL)ZL + sqrt(rhoR)ZR) / (sqrt(rhoL)+sqrt(rhoR)),
! the four species waves
!     wave(4,mw) = Zbar * wave(1,mw)      (mw = 1..3, on Euler families)
!     wave(4,4)  = d(rho*Z) - Zbar*d(rho) (4th family at speed ubar)
! reproduce the flux difference d(u*rho*Z) = sum_mw s(mw)*wave(4,mw)
! EXACTLY (expand in a=sqrt(rhoL), b=sqrt(rhoR): all cross terms cancel).
! Because u*(ets+p) + q0*u*rho*Z is the conserved-energy flux, the same
! identity fixes the energy components of the waves:
!     wave(3,mw) = ets-wave(mw) + q0*wave(4,mw)   (mw = 1..3)
!     wave(3,4)  = q0*wave(4,4)
! so sum_mw s(mw)*wave(m,mw) = dF(m) exactly for ALL FOUR components and
! step1's Godunov update stays conservative -- no spurious splitting
! source inside the Riemann solve.
!
! gamma arrives through /cparam/ (same block the vendored solver reads),
! q0 (heat release) through /rparam/.
! =========================================================================
subroutine rp1_reacting(maxmx,meqn,mwaves,maux,mbc,mx,ql,qr,auxl,auxr, &
                        wave,s,amdq,apdq)
    implicit none

    integer, intent(in) :: maxmx, meqn, mwaves, maux, mbc, mx
    real(kind=8), intent(in) :: ql(meqn,1-mbc:maxmx+mbc)
    real(kind=8), intent(in) :: qr(meqn,1-mbc:maxmx+mbc)
    real(kind=8), intent(in) :: auxl(maux,1-mbc:maxmx+mbc)
    real(kind=8), intent(in) :: auxr(maux,1-mbc:maxmx+mbc)

    real(kind=8), intent(out) :: s(mwaves,1-mbc:maxmx+mbc)
    real(kind=8), intent(out) :: wave(meqn, mwaves,1-mbc:maxmx+mbc)
    real(kind=8), intent(out) :: amdq(meqn,1-mbc:maxmx+mbc)
    real(kind=8), intent(out) :: apdq(meqn,1-mbc:maxmx+mbc)

    real(kind=8) :: delta(3), etsl, etsr, dpsi
    real(kind=8) :: u(1-mbc:maxmx+mbc), enth(1-mbc:maxmx+mbc)
    real(kind=8) :: a(1-mbc:maxmx+mbc)
    real(kind=8) :: zb(1-mbc:maxmx+mbc)   ! sqrt(rho)-weighted Roe avg of Z
    logical, parameter :: efix = .true.   ! entropy fix for transonic rarefactions
    real(kind=8) :: gamma, gamma1, q0
    real(kind=8) :: rhsqrtl, rhsqrtr, pl, pr, rhsq2, a1, a2, a3
    real(kind=8) :: zl, zr
    real(kind=8) :: rhoim1, pim1, cim1, s0, rho1, rhou1, ets1, p1, c1, s1, sfract
    real(kind=8) :: rhoi, pi, ci, s3, rho2, rhou2, ets2, p2, c2, s2, df
    integer :: i, m, mw

    common /cparam/  gamma
    common /rparam/  q0

    gamma1 = gamma - 1.d0

    !     # Compute Roe-averaged quantities (ets replaces E everywhere):
    do i = 2-mbc, mx+mbc
        rhsqrtl = dsqrt(qr(1,i-1))
        rhsqrtr = dsqrt(ql(1,i))
        etsl = qr(3,i-1) - q0*qr(4,i-1)
        etsr = ql(3,i)   - q0*ql(4,i)
        pl = gamma1*(etsl - 0.5d0*(qr(2,i-1)**2)/qr(1,i-1))
        pr = gamma1*(etsr - 0.5d0*(ql(2,i)**2)/ql(1,i))
        rhsq2 = rhsqrtl + rhsqrtr
        u(i) = (qr(2,i-1)/rhsqrtl + ql(2,i)/rhsqrtr) / rhsq2
        enth(i) = (((etsl+pl)/rhsqrtl + (etsr+pr)/rhsqrtr)) / rhsq2
        a2 = gamma1*(enth(i) - .5d0*u(i)**2)
        a(i) = dsqrt(a2)
        zl = qr(4,i-1)/qr(1,i-1)
        zr = ql(4,i)/ql(1,i)
        zb(i) = (rhsqrtl*zl + rhsqrtr*zr) / rhsq2
    end do

    do i = 2-mbc, mx+mbc

        !        # a1 thru a3: eigenvector coefficients of the 3 Euler families
        !        (delta(3) is the ets jump)
        delta(1) = ql(1,i) - qr(1,i-1)
        delta(2) = ql(2,i) - qr(2,i-1)
        delta(3) = (ql(3,i) - q0*ql(4,i)) - (qr(3,i-1) - q0*qr(4,i-1))
        dpsi     = ql(4,i) - qr(4,i-1)
        a2 = gamma1/a(i)**2 * ((enth(i)-u(i)**2)*delta(1) &
        + u(i)*delta(2) - delta(3))
        a3 = (delta(2) + (a(i)-u(i))*delta(1) - a(i)*a2) / (2.d0*a(i))
        a1 = delta(1) - a2 - a3

        !        # Compute the waves.  Components 1,2 as in the vendored solver;
        !        # species and energy rows follow the identities in the header.
        wave(1,1,i) = a1
        wave(2,1,i) = a1*(u(i)-a(i))
        s(1,i) = u(i)-a(i)

        wave(1,2,i) = a2
        wave(2,2,i) = a2*u(i)
        s(2,i) = u(i)

        wave(1,3,i) = a3
        wave(2,3,i) = a3*(u(i)+a(i))
        s(3,i) = u(i)+a(i)

        wave(4,1,i) = zb(i)*wave(1,1,i)
        wave(4,2,i) = zb(i)*wave(1,2,i)
        wave(4,3,i) = zb(i)*wave(1,3,i)
        wave(4,4,i) = dpsi - zb(i)*delta(1)
        s(4,i) = u(i)

        wave(3,1,i) = a1*(enth(i) - u(i)*a(i)) + q0*wave(4,1,i)
        wave(3,2,i) = a2*0.5d0*u(i)**2                  + q0*wave(4,2,i)
        wave(3,3,i) = a3*(enth(i) + u(i)*a(i)) + q0*wave(4,3,i)
        wave(3,4,i) = q0*wave(4,4,i)
    end do

    !     # With entropy fix (efix = .true.): amdq = sum of s*wave over
    !     # left-going waves, with a modified fraction of wave 1 / wave 3
    !     # where the wave speed should change sign.  States around the
    !     # rarefaction are reconstructed with ets (see header).
    do i = 2-mbc, mx+mbc

        !        # check 1-wave:
        rhoim1 = qr(1,i-1)
        pim1 = gamma1*(qr(3,i-1) - q0*qr(4,i-1) &
                       - 0.5d0*qr(2,i-1)**2/rhoim1)
        cim1 = dsqrt(gamma*pim1/rhoim1)
        s0 = qr(2,i-1)/rhoim1 - cim1     !# u-c in left state (cell i-1)

        !        # check for fully supersonic case:
        if (s0 >= 0.d0 .AND. s(1,i) > 0.d0)  then
            !            # everything is right-going
            do m = 1, meqn
                amdq(m,i) = 0.d0
            end do
            cycle
        endif

        rho1  = qr(1,i-1) + wave(1,1,i)
        rhou1 = qr(2,i-1) + wave(2,1,i)
        ! ets to the right of the 1-wave: E and psi jump by the wave's
        ! energy / species components
        ets1 = (qr(3,i-1) + wave(3,1,i)) - q0*(qr(4,i-1) + wave(4,1,i))
        p1 = gamma1*(ets1 - 0.5d0*rhou1**2/rho1)
        c1 = dsqrt(gamma*p1/rho1)
        s1 = rhou1/rho1 - c1  !# u-c to right of 1-wave
        if (s0 < 0.d0 .AND. s1 > 0.d0) then
            !            # transonic rarefaction in the 1-wave
            sfract = s0 * (s1-s(1,i)) / (s1-s0)
        else if (s(1,i) < 0.d0) then
            !            # 1-wave is leftgoing
            sfract = s(1,i)
        else
            !            # 1-wave is rightgoing
            sfract = 0.d0   !# this shouldn't happen since s0 < 0
        endif
        do m = 1, meqn
            amdq(m,i) = sfract*wave(m,1,i)
        end do

        !        # check 2-wave (and, with it, the 4th/species family,
        !        # which travels at the same Roe speed u):
        if (s(2,i) >= 0.d0) cycle   !# 2-wave is rightgoing
        do m = 1, meqn
            amdq(m,i) = amdq(m,i) + s(2,i)*wave(m,2,i)
        end do
        ! s(4) == s(2) by construction (the species contact rides the
        ! 2-wave's Roe speed), so this branch fires exactly when the 2-wave
        ! branch above does; kept separate for clarity, not correctness.
        if (s(4,i) < 0.d0) then
            do m = 1, meqn
                amdq(m,i) = amdq(m,i) + s(4,i)*wave(m,4,i)
            end do
        end if

        !        # check 3-wave:
        rhoi = ql(1,i)
        pi = gamma1*(ql(3,i) - q0*ql(4,i) - 0.5d0*ql(2,i)**2/rhoi)
        ci = dsqrt(gamma*pi/rhoi)
        s3 = ql(2,i)/rhoi + ci     !# u+c in right state  (cell i)

        rho2  = ql(1,i) - wave(1,3,i)
        rhou2 = ql(2,i) - wave(2,3,i)
        ets2 = (ql(3,i) - wave(3,3,i)) - q0*(ql(4,i) - wave(4,3,i))
        p2 = gamma1*(ets2 - 0.5d0*rhou2**2/rho2)
        c2 = dsqrt(gamma*p2/rho2)
        s2 = rhou2/rho2 + c2   !# u+c to left of 3-wave
        if (s2 < 0.d0 .AND. s3 > 0.d0) then
            !            # transonic rarefaction in the 3-wave
            sfract = s2 * (s3-s(3,i)) / (s3-s2)
        else if (s(3,i) < 0.d0) then
            !            # 3-wave is leftgoing
            sfract = s(3,i)
        else
            !            # 3-wave is rightgoing
            cycle
        endif

        do m = 1, meqn
            amdq(m,i) = amdq(m,i) + sfract*wave(m,3,i)
        end do
    end do

    !     # rightgoing flux differences: df = SUM s*wave is the total flux
    !     difference and apdq = df - amdq
    do m = 1, meqn
        do i = 2-mbc, mx+mbc
            df = 0.d0
            do mw = 1, mwaves
                df = df + s(mw,i)*wave(m,mw,i)
            end do
            apdq(m,i) = df - amdq(m,i)
        end do
    end do

    return
end subroutine rp1_reacting
