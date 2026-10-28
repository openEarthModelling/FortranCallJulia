! ==============================================================================
! Example: SciML-style batch data extraction (Wave B)
!
! Exercises the JuliaValue extraction surface added in Wave B:
!   %element(i)         -- 1-based element access (retained handle)
!   %property(key)      -- getproperty (retained handle)
!   %to_fortran(buf, n) -- bulk copy of a dense Float64 / ComplexF64
!                          array into a Fortran buffer (real / complex
!                          overloads resolve by the buffer type)
! Plus the failure path: an out-of-bounds element access returns a
! NULL handle and populates last_error.
! ==============================================================================
program ex_sciml_batch_data
    use iso_c_binding
    use, intrinsic :: iso_fortran_env, only: error_unit
    use julia_high_level
    implicit none

    type(JuliaValue) :: nested, el1, d, a, cx, el_oob
    real(kind=c_double) :: rbuf(3)
    complex(kind=c_double) :: cbuf(3)
    integer(kind=c_int) :: rc
    integer :: i
    character(len=:), allocatable :: msg

    print *, "--- Example: SciML-style batch data extraction ---"

    ! 1. Initialize with the default exe-adjacent package probe
    call julia_init_ex()

    ! 2. Nested vector-of-vectors: %element + %to_fortran (real buffer)
    nested = julia_eval("[ [1.0,2.0], [3.0,4.0] ]")
    if (.not. nested%is_valid()) &
        call fail('julia_eval nested failed')
    el1 = nested%element(1_c_int64_t)
    if (.not. el1%is_valid()) &
        call fail('element(1) failed: ' // get_last_error_message())
    rc = el1%to_fortran(rbuf, 2_c_int64_t)
    if (rc /= 0) &
        call fail('to_fortran on nested element failed: ' // get_last_error_message())
    if (abs(rbuf(1) - 1.0_c_double) > 1.0e-12_c_double .or. &
        abs(rbuf(2) - 2.0_c_double) > 1.0e-12_c_double) then
        call fail('nested element values mismatch')
    end if
    print *, 'EX_BATCH_OK_NESTED rbuf=', rbuf(1), rbuf(2)

    ! 3. NamedTuple property: nt.a via %property + %to_fortran (real buffer)
    d = julia_eval(' (a = [7.0,8.0,9.0],) ')
    if (.not. d%is_valid()) &
        call fail('julia_eval NamedTuple failed')
    a = d%property("a")
    if (.not. a%is_valid()) &
        call fail('property("a") failed: ' // get_last_error_message())
    rc = a%to_fortran(rbuf, 3_c_int64_t)
    if (rc /= 0) &
        call fail('to_fortran on NamedTuple property failed: ' // get_last_error_message())
    do i = 1, 3
        if (abs(rbuf(i) - real(i + 6, kind=c_double)) > 1.0e-12_c_double) then
            call fail('NamedTuple property values mismatch')
        end if
    end do
    print *, 'EX_BATCH_OK_NT rbuf=', rbuf(1), rbuf(2), rbuf(3)

    ! 4. Complex array: %to_fortran into a complex(c_double) buffer
    cx = julia_eval("ComplexF64[1.0im, 2.0im, 3.0im]")
    if (.not. cx%is_valid()) &
        call fail('julia_eval complex failed')
    rc = cx%to_fortran(cbuf, 3_c_int64_t)
    if (rc /= 0) &
        call fail('to_fortran on complex array failed: ' // get_last_error_message())
    do i = 1, 3
        if (abs(real(cbuf(i), kind=c_double)) > 1.0e-12_c_double .or. &
            abs(aimag(cbuf(i)) - real(i, kind=c_double)) > 1.0e-12_c_double) then
            call fail('complex values mismatch')
        end if
    end do
    print *, 'EX_BATCH_OK_COMPLEX cbuf=', cbuf

    ! 5. Failure path: out-of-bounds element must yield a NULL handle
    !    and a non-empty last_error.
    el_oob = nested%element(5_c_int64_t)
    if (el_oob%is_valid()) &
        call fail('element(5) unexpectedly returned a valid handle')
    msg = get_last_error_message()
    if (len_trim(msg) == 0 .or. trim(msg) == 'Unknown Error') then
        call fail('last_error empty after out-of-bounds element access')
    end if
    print *, 'EX_BATCH_OK_OOB last_error=', trim(msg)

    ! 6. Shutdown
    call julia_shutdown()

contains

    subroutine fail(reason)
        character(len=*), intent(in) :: reason
        write (error_unit, '(A)') 'FATAL: ' // trim(reason)
        stop 1
    end subroutine fail

end program ex_sciml_batch_data
