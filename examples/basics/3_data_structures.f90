program ex03_data_structures
    use julia_high_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: dummy, ctx
    type(JuliaValue) :: person_obj, scores_obj
    type(JuliaValue) :: val_obj
    integer(kind=c_int64_t) :: age, score
    
    print *, "--- Example 3: Data Structures (Structs & Dicts) ---"
    call julia_init()

    ! Define a Julia Struct
    call julia_eval_string("struct Person; name::String; age::Int; end")
    
    ! 1. Create an instance in Julia
    ! We call the constructor "Person" just like a function
    person_obj = dummy%call("Person", "Alice", 30)
    
    ! 2. Access Fields using .get_field()
    print *, "[Struct] Inspecting Person object..."
    
    ! For structs, we use get_field
    val_obj = person_obj%get_field("name")
    print *, "  Name: ", val_obj%as_string()
    
    val_obj = person_obj%get_field("age")
    ! as_integer returns int64
    age = val_obj%as_integer()
    print *, "  Age:  ", age

    ! 3. Modify Fields (Note: Immutable structs cannot be modified, so we use a Dict for this example)
    print *, ""
    print *, "[Dict] Working with Dictionaries..."
    
    ! Initialize a Dict in Julia global scope
    call julia_eval_string('scores = Dict("Math" => 90, "Physics" => 85)')
    
    ! Retrieve the global variable 'scores' using julia_eval
    scores_obj = julia_eval("scores")
    
    ! Get value
    val_obj = scores_obj%at("Math")
    print *, "  Math Score: ", val_obj%as_integer()
    
    ! Set value
    print *, "  Updating Physics score..."
    ! Note: 'set_at' generic interface expects a JuliaValue object for the value.
    ! Unlike 'call', it does not auto-box yet (to keep the interface simple for now).
    ! So we manually box the integer 95.
    call scores_obj%set_at("Physics", julia_box_integer(95_8))
    
    ! Verify
    val_obj = scores_obj%at("Physics")
    print *, "  New Physics Score: ", val_obj%as_integer()

    call julia_shutdown()

end program ex03_data_structures