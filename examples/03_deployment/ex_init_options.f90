program ex_init_options
    use iso_c_binding
    use julia_high_level
    implicit none

    type(JuliaValue) :: res
    integer :: val
    integer :: nthr

    print *, "--- Example: Startup Control via julia_init_ex ---"

    ! 1. Initialize the Julia runtime with explicit startup options:
    !    - project_path: the FortranBridge package copied next to this
    !      executable by the build (exe-adjacent probe also works without it)
    !    - nthreads = 2
    !    - handle_signals = 0 ("no takeover": SIGINT/SIGTERM are reset to
    !      SIG_DFL after init; GC-critical handlers stay intact -- bridge.h)
    call julia_init_ex(project_path="FortranBridge", nthreads=2, handle_signals=0)

    ! 2. Load your Julia Code (relative to the current working directory)
    call julia_eval_string('include("examples_lib.jl")')
    call julia_eval_string('using .ExamplesLib')

    ! 3. Evaluate a trivial expression through the existing SDK
    res = julia_eval("ExamplesLib.add_numbers(40.0, 2.0)")
    val = int(res%as_real())
    print *, "init_options: add_numbers(40, 2) = ", val

    ! 4. Confirm the startup options took effect
    res = julia_eval("Threads.nthreads()")
    nthr = res%as_integer()
    print *, "init_options: Threads.nthreads() = ", nthr

    print *, "EX_INIT_OPTIONS_OK value=", val, " nthreads=", nthr

    ! 5. Shutdown
    call julia_shutdown()

end program ex_init_options
