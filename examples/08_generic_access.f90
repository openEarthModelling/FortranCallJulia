program ex08_generic_access
    use julia_high_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: ctx
    type(JuliaValue) :: data_obj, person_obj, scores_obj
    type(JuliaValue) :: age_obj, new_age_obj, score_val
    integer(kind=c_int64_t) :: age, score
    
    print *, "--- Example 8: Generic Access (Structs & Arrays) ---"
    call julia_init()

    ! 1. Setup Julia Data
    ! We create a NamedTuple with a Struct and an Array inside.
    print *, "Creating complex Julia data structure..."
    call julia_eval_string('struct Person; name::String; age::Int; end')
    call julia_eval_string('const MyData = (p=Person("Alice", 30), scores=[90, 85, 95])')
    
    ! 2. Get the global object
    call julia_eval_string('function get_my_data(); return MyData; end')
    data_obj = ctx%call_method_0("get_my_data")

    if (.not. data_obj%is_valid()) then
        print *, "Error getting data object."
        call julia_shutdown()
        stop
    end if

    ! 3. Drill down: data.p.age
    print *, "Accessing data.p.age..."
    person_obj = data_obj%get_field("p")
    age_obj = person_obj%get_field("age")
    
    age = age_obj%as_integer()
    print *, "Got Age: ", age
    if (age == 30) then
        print *, "SUCCESS: Age matches."
    else
        print *, "FAILURE: Age mismatch."
    end if

    ! 4. Modify Field: data.p.age = 31
    print *, "Setting data.p.age = 31..."
    
    block
        type(JuliaValue) :: val_31
        val_31 = julia_box_integer(31_8)
        call person_obj%set_field("age", val_31)
    end block
    
    ! Check for error
    if (index(get_last_error_message(), "immutable") > 0 .or. index(get_last_error_message(), "type Person") > 0) then
        print *, "Expected Error: Cannot set field of immutable struct."
    else
        print *, "Unexpected behavior (maybe it succeeded?): ", get_last_error_message()
    end if

    ! Let's try with a Mutable Struct
    print *, "Defining Mutable Person..."
    call julia_eval_string('mutable struct MutablePerson; name::String; age::Int; end')
    call julia_eval_string('const MP = MutablePerson("Bob", 40)')
    call julia_eval_string('function get_mp(); return MP; end')
    
    person_obj = ctx%call_method_0("get_mp")
    
    age_obj = person_obj%get_field("age")
    print *, "Old Age: ", age_obj%as_integer()
    
    block
        type(JuliaValue) :: val_41
        val_41 = julia_box_integer(41_8)
        call person_obj%set_field("age", val_41)
    end block
    
    new_age_obj = person_obj%get_field("age")
    print *, "New Age: ", new_age_obj%as_integer()
    
    if (new_age_obj%as_integer() == 41) then
        print *, "SUCCESS: Mutable struct modified."
    end if

    ! 5. Array Access: data.scores[2]
    print *, "Accessing data.scores[2]..."
    scores_obj = data_obj%get_field("scores")
    score_val = scores_obj%at(2_8)
    score = score_val%as_integer()
    
    print *, "Got Score[2]: ", score
    if (score == 85) then
        print *, "SUCCESS: Score matches."
    else
        print *, "FAILURE: Score mismatch."
    end if

    ! 6. Array Modification: data.scores[2] = 100
    print *, "Setting data.scores[2] = 100..."
    block
        type(JuliaValue) :: val_100
        val_100 = julia_box_integer(100_8)
        call scores_obj%set_at(2_8, val_100)
    end block
    
    score_val = scores_obj%at(2_8)
    print *, "New Score[2]: ", score_val%as_integer()
    
    if (score_val%as_integer() == 100) then
        print *, "SUCCESS: Array modified."
    end if

    call julia_shutdown()
    print *, "--- Finished ---"

end program ex08_generic_access
