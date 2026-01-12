program ex07_mpi_bootstrap
    use mpi
    use julia_high_level
    use julia_low_level
    use iso_c_binding
    implicit none

    integer :: ierr, rank, size, name_len
    character(len=MPI_MAX_PROCESSOR_NAME) :: processor_name
    
    ! Business Logic Data
    real(kind=8), target :: matrix(4,4)
    type(JuliaValue) :: mat_obj, res_obj
    type(c_ptr) :: raw_ptr, wrapped_ptr
    integer :: i

    ! 1. MPI Init
    call MPI_Init(ierr)
    call MPI_Comm_rank(MPI_COMM_WORLD, rank, ierr)
    call MPI_Comm_size(MPI_COMM_WORLD, size, ierr)
    call MPI_Get_processor_name(processor_name, name_len, ierr)

    if (rank == 0) then
        print *, "--- Example 7: MPI + Julia Bootstrap (Matrix Ops) ---"
        print *, "Total Ranks: ", size
    endif

    call MPI_Barrier(MPI_COMM_WORLD, ierr)

    ! 2. Julia Init
    if (rank == 0) print *, "[Master] Initializing Julia..."
    call julia_init() 

    ! 3. Load Logic & Setup
    call julia_eval_string('include("examples_lib.jl")')
    call julia_eval_string('using .ExamplesLib')
    call julia_eval_string('const calc_inverse = ExamplesLib.calc_inverse')

    ! 4. Local Computation (Verify Libraries work in MPI)
    matrix = 0.0d0
    do i=1,4; matrix(i,i)=real(rank+1, 8); end do ! Diagonal based on rank
    
    raw_ptr = c_loc(matrix)
    wrapped_ptr = fj_wrap_array_2d(raw_ptr, 4_8, 4_8)
    mat_obj%ptr = fj_retain(wrapped_ptr)
    
    block
        type(JuliaValue) :: args(1), dummy
        args(1) = mat_obj
        res_obj = dummy%call_method_generic("calc_inverse", args)
    end block
    
    if (res_obj%is_valid()) then
         ! Ideally verify value, but for bootstrap test, existence is enough.
         print *, "[Rank", rank, "] Success. Matrix Inversion computed."
    else
         print *, "[Rank", rank, "] Failed."
    endif

    ! 5. Shutdown
    call julia_shutdown()
    call MPI_Finalize(ierr)

end program ex07_mpi_bootstrap