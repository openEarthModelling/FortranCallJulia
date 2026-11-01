program fcj_consumer
    use julia_high_level
    implicit none

    type(JuliaValue) :: res
    real(kind=8) :: x

    ! Smallest honest roundtrip: embed Julia, evaluate one expression
    ! through the bridge, convert the boxed result back, shut down clean.
    call julia_init()

    res = julia_eval("40.0 + 2.0")
    x = res%as_real()
    print *, "consumer: julia_eval('40.0 + 2.0') = ", x
    if (abs(x - 42.0d0) > 1.0d-12) error stop "bridge roundtrip mismatch"

    call julia_shutdown()
    print *, "consumer: OK"

end program fcj_consumer
