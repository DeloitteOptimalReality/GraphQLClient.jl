@testset "create_struct_AST" begin
    # Mutable
    eval(GraphQLClient.create_struct_AST(
        :NewType,
        Number,
        Dict(:field1 => Int)
    ))
    @test fieldnames(NewType) == (:field1,)
    new_type = NewType(1)
    @test ismutable(new_type) # Check mutability
    @test new_type isa Number # Check supertype
    new_type.field1 = nothing # Check Union
    @test isnothing(new_type.field1)

    # Immutable
    eval(GraphQLClient.create_struct_AST(
        :NewTypeImmutable,
        Number,
        Dict(:field1 => Int),
        mutable=false
    ))
    @test fieldnames(NewTypeImmutable) == (:field1,)
    @test !ismutable(NewTypeImmutable(1)) # Check mutability
    @test NewTypeImmutable(1) isa Number # Check supertype
end

@testset "build_name_to_type introspection" begin
    # Simple scalar types
    client = Client("url", "ws"; introspect=false)
    client.type_to_fields_map = Dict(
        "MyObject" => Dict(
            "my_scalar" => build_type(nothing, "my_scalar", type=
                build_type("SCALAR", "String")),
            "my_nonnull_scalar" => build_type("", "my_nonnull_scalar", type=
                build_type("NON_NULL", nothing, ofType=
                    build_type("SCALAR", "Boolean")))
        )
    )
    name_to_type = GraphQLClient.build_name_to_type(client, "MyObject")
    @test name_to_type[:my_nonnull_scalar] == Bool
    @test name_to_type[:my_scalar] == String

    # Custom scalar
    push!(client.type_to_fields_map, "MyObjectWithCustomScalar" => Dict(
        "my_custom_scalar_field" => build_type(nothing, "my_custom_scalar_field", type=
                build_type("SCALAR", "CustomScalarType"))
    ))
    @test_throws ArgumentError GraphQLClient.build_name_to_type(client, "MyObjectWithCustomScalar")
    name_to_type = GraphQLClient.build_name_to_type(client, "MyObjectWithCustomScalar", scalar_types=Dict("CustomScalarType" => Int8))
    @test name_to_type[:my_custom_scalar_field] == Int8

    # Object - stopped by recursion
    push!(client.type_to_fields_map, "MyTopLevelObject" => Dict(
        "object_field" => build_type(nothing, "object_field", type=
            build_type("OBJECT", "MyObject"))
    ))

    @test_logs (:warn, r"Cannot introspect field") GraphQLClient.build_name_to_type(
        client,
        "MyTopLevelObject",
        objects_being_introspected=["MyObject"],
    )

    @test_logs (:warn, r"Cannot introspect field") GraphQLClient.build_name_to_type(
        client,
        "MyTopLevelObject",
        allowed_level=1,
    )

    # Object - introspected
    name_to_type = GraphQLClient.build_name_to_type(client, "MyTopLevelObject")
    @test name_to_type[:object_field] == GraphQLClient.get_introspected_type(client, "MyObject")

    # Already introspected vector
    push!(client.type_to_fields_map, "MyTopLevelVectorObject" => Dict(
        "vector_object_field" => build_type(nothing, "vector_object_field", type=
            build_type("LIST", nothing, ofType=
                build_type("OBJECT", "MyObject")))))

    name_to_type = GraphQLClient.build_name_to_type(client, "MyTopLevelVectorObject")
    @test name_to_type[:vector_object_field] == Vector{GraphQLClient.get_introspected_type(client, "MyObject")}
end

@testset "_instrospect_object" begin
    # Object with scalar types
    client = Client("url", "ws"; introspect=false)
    client.type_to_fields_map = Dict(
        "MyObject" => Dict(
            "my_scalar" => build_type(nothing, "my_scalar", type=
                build_type("SCALAR", "String")),
            "my_nonnull_scalar" => build_type("", "my_nonnull_scalar", type=
                build_type("NON_NULL", nothing, ofType=
                    build_type("SCALAR", "Boolean")))
        )
    )
    
    T = GraphQLClient._instrospect_object(client, "MyObject")
    @test hasfield(T, :my_scalar)
    @test hasfield(T, :my_nonnull_scalar)
    @test T <: GraphQLClient.AbstractIntrospectedStruct

    # check doesn't get introspected again
    T2 = GraphQLClient._instrospect_object(client, "MyObject")
    @test T===T2
end

@testset "introspect_object" begin 
    client = Client("url", "ws"; introspect=false)
    client.type_to_fields_map = Dict(
        "MyObject" => Dict(
            "my_scalar" => build_type(nothing, "my_scalar", type=
                build_type("SCALAR", "String")),
            "my_sub_object" => build_type("", "my_sub_object", type=
                build_type("OBJECT", "MySubObject"))
        ),
        "MySubObject" => Dict(
            "my_scalar_2" => build_type(nothing, "my_scalar_2", type=
                build_type("SCALAR", "Float"))
        )
    )
    # Test objects are not re-introspected
    T1 = GraphQLClient.introspect_object(client, "MyObject")
    T1_sub = GraphQLClient.get_introspected_type(client, "MySubObject")
    T2 = GraphQLClient.introspect_object(client, "MyObject")
    T2_sub = GraphQLClient.get_introspected_type(client, "MySubObject")
    @test T1 === T2
    @test T1_sub === T2_sub
    # Test global client methods
    global_graphql_client(client)
    T2_global = GraphQLClient.introspect_object("MyObject")
    @test T1 === T2_global
    @test GraphQLClient.get_introspected_type("MySubObject") === T1_sub
    # Test that force re-introspects all objects that are requested and are subobjects and no others
    T3 = GraphQLClient.introspect_object(client, "MyObject", force=true)
    T3_sub = GraphQLClient.get_introspected_type(client, "MySubObject")
    @test T3 !== T2
    @test T3_sub !== T2_sub
    T4_sub = GraphQLClient.introspect_object(client, "MySubObject", force=true)
    T4 = GraphQLClient.get_introspected_type(client, "MyObject")
    @test T4 == T3
    @test T4_sub !== T3_sub
    # Test reset all resets all
    T5_sub = GraphQLClient.introspect_object(client, "MySubObject", reset_all=true)
    @test T5_sub !== T4_sub
    @test !haskey(client.introspected_types, "MyObject") # deleted
    
    # Test that already introspected subobject is used
    GraphQLClient.introspect_object(client, "MyObject")
    @test GraphQLClient.get_introspected_type(client, "MySubObject") === T5_sub

    # Test that mutable cascades to all sub types
    @test ismutable(GraphQLClient.initialise_introspected_struct(client, "MyObject"))
    @test ismutable(GraphQLClient.initialise_introspected_struct(client, "MySubObject"))
    GraphQLClient.introspect_object(client, "MyObject", force=true, mutable=false)
    @test !ismutable(GraphQLClient.initialise_introspected_struct(client, "MyObject"))
    @test !ismutable(GraphQLClient.initialise_introspected_struct(client, "MySubObject"))

    # Test parent types
    T4 = GraphQLClient.introspect_object(client, "MyObject", force=true, parent_type=Number)
    T4_sub = GraphQLClient.get_introspected_type(client, "MySubObject")
    @test T4 <: Number
    @test T4_sub <: GraphQLClient.AbstractIntrospectedStruct # only top level set
    T5 = GraphQLClient.introspect_object(client, "MyObject", force=true, parent_map=Dict("MyObject" => Real, "MySubObject" => AbstractString))
    T5_sub = GraphQLClient.get_introspected_type(client, "MySubObject")
    @test T5 <: Real
    @test T5_sub <: AbstractString
    @test_logs (:warn, r"Parent type for MyObject supplied in both parent_map and parent_type kwarg") GraphQLClient.introspect_object(client, "MyObject", force=true, parent_type=Number, parent_map=Dict("MyObject" => AbstractString, "MySubObject" => AbstractString))
    T6 = GraphQLClient.introspect_object(client, "MyObject", force=true, parent_type=Number, parent_map=Dict("MyObject" => AbstractString, "MySubObject" => AbstractString))
    T6_sub = GraphQLClient.get_introspected_type(client, "MySubObject")
    @test T6 <: Number
    @test T6_sub <: AbstractString

    # Test force only changes structs that are re-introspected and not others
    client.type_to_fields_map["MyNewObject"] =  Dict(
            "my_scalar" => build_type(nothing, "my_scalar", type=
                build_type("SCALAR", "String")))
    GraphQLClient.introspect_object(client, "MyNewObject", force=true)
    T7_sub = GraphQLClient.get_introspected_type(client, "MySubObject")
    @test T7_sub === T6_sub

    # Test recursion
    client = Client("url", "ws"; introspect=false)
    client.type_to_fields_map = Dict(
        "MyObject" => Dict(
            "my_sub_object" => build_type("", "my_sub_object", type=
                build_type("OBJECT", "MySubObject"))
        ),
        "MySubObject" => Dict(
            "my_object" => build_type(nothing, "my_object", type=
                build_type("OBJECT", "MyObject")),
            "my_scalar" => build_type(nothing, "my_scalar", type=
                build_type("SCALAR", "String"))
        )
    )
    GraphQLClient.introspect_object(client, "MyObject", force=true)
    T_subobject = GraphQLClient.get_introspected_type(client, "MySubObject")
    @test !hasfield(T_subobject, :my_object)

    # Test scalar type
    client = Client("url", "ws"; introspect=false)
    push!(client.type_to_fields_map, "MyObjectWithCustomScalar" => Dict(
        "my_custom_scalar_field" => build_type(nothing, "my_custom_scalar_field", type=
                build_type("SCALAR", "CustomScalarType")),
        "my_scalar_field" => build_type(nothing, "my_scalar_field", type=
                build_type("SCALAR", "String"))
    ))
    T = GraphQLClient.introspect_object(client, "MyObjectWithCustomScalar", custom_scalar_types=Dict("CustomScalarType" => Int), force=true)
    @test hasfield(T, :my_custom_scalar_field)
    @test hasfield(T, :my_scalar_field)
    @test fieldtypes(T) == (Union{Nothing, Int64}, Union{Nothing, String})
end

@testset "Initialising" begin
    client = Client("url", "ws"; introspect=false)
    client.type_to_fields_map = Dict(
        "MyObject" => Dict(
            "my_scalar" => build_type(nothing, "my_scalar", type=
                build_type("SCALAR", "String")),
            "my_sub_object" => build_type("", "my_sub_object", type=
                build_type("OBJECT", "MySubObject"))
        ),
        "MySubObject" => Dict(
            "my_scalar_2" => build_type(nothing, "my_scalar_2", type=
                build_type("SCALAR", "Float"))
        )
    )
    GraphQLClient.introspect_object(client, "MyObject")

    # Test Initialise
    my_object = GraphQLClient.initialise_introspected_struct(client, SubString("MyObject"))
    @test all(isnothing(getproperty(my_object, property)) for property in propertynames(my_object))
    my_object = GraphQLClient.initialise_introspected_struct(SubString("MyObject"))
    @test all(isnothing(getproperty(my_object, property)) for property in propertynames(my_object))

    # Test create
    my_sub_object = GraphQLClient.create_introspected_struct(
        client,
        "MySubObject",
        Dict("my_scalar_2" => 3.0)
    )

    my_object = GraphQLClient.create_introspected_struct(
        client,
        "MyObject",
        Dict("my_scalar" => "string", "my_sub_object" => my_sub_object)
    )

    @test my_object.my_sub_object.my_scalar_2 == 3.0

    # create with global client
    global_graphql_client(client)
    my_sub_object = GraphQLClient.create_introspected_struct(
        "MySubObject",
        Dict("my_scalar_2" => 3.0)
    )
    my_object = GraphQLClient.create_introspected_struct(
        "MyObject",
        Dict("my_scalar" => "string", "my_sub_object" => my_sub_object)
    )
    @test my_object.my_sub_object.my_scalar_2 == 3.0

    # Only can create for mutable
    GraphQLClient.introspect_object(client, "MyObject"; force=true, mutable=false)

    @test_throws GraphQLClient.GraphQLClientException GraphQLClient.create_introspected_struct(
        client,
        "MyObject",
        Dict("my_scalar" => "string", "my_sub_object" => my_sub_object)
    )
end