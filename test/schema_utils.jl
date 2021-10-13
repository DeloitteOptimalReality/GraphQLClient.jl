@testset "getsubfield" begin
    type_field = Dict("type" => "type_field")
    @test GraphQLClient.getsubfield(type_field) == "type_field"
    ofType_field = Dict("type" => "ofType_field")
    @test GraphQLClient.getsubfield(ofType_field) == "ofType_field"
    not_a_field = Dict()
    @test_throws GraphQLClient.GraphQLClientException GraphQLClient.getsubfield(not_a_field)
end

@testset "is tests" begin
    # istype
    generic_field = Dict("type" => Dict("kind" => "CUSTOM_TYPE"))
    @test GraphQLClient.istype(generic_field, "CUSTOM_TYPE")
    @test !GraphQLClient.istype(generic_field, "NOT_CUSTOM_TYPE")
    generic_field = Dict("ofType" => Dict("kind" => "CUSTOM_TYPE"))
    @test GraphQLClient.istype(generic_field, "CUSTOM_TYPE")
    @test !GraphQLClient.istype(generic_field, "NOT_CUSTOM_TYPE")

    # specific, not nested
    object = Dict("type" => Dict("kind" => "OBJECT"))
    @test GraphQLClient.isobject(object)
    non_null = Dict("type" => Dict("kind" => "NON_NULL"))
    @test GraphQLClient.isnonnull(non_null)
    list = Dict("type" => Dict("kind" => "LIST"))
    @test GraphQLClient.islist(list)
    scalar = Dict("type" => Dict("kind" => "SCALAR"))
    @test GraphQLClient.isscalar(scalar)
    input_object = Dict("type" => Dict("kind" => "INPUT_OBJECT"))
    @test GraphQLClient.isinputobject(input_object)
    enum = Dict("type" => Dict("kind" => "ENUM"))
    @test GraphQLClient.isenum(enum)

    # specific and nested
    nonnull_input_object = Dict(
        "type" => Dict(
            "kind" => "NON_NULL",
            "ofType" => Dict("kind" => "INPUT_OBJECT")
        )
    )
    @test GraphQLClient.is_nonnull_input_object(nonnull_input_object)
    not_a_nonnull_input_object = Dict(
        "type" => Dict(
            "kind" => "NON_NULL",
            "ofType" => Dict("kind" => "SCALAR")
        )
    )
    @test !GraphQLClient.is_nonnull_input_object(not_a_nonnull_input_object)
    @test GraphQLClient.isroottypescalar(not_a_nonnull_input_object)
    listofobjects = Dict(
        "type" => Dict(
            "kind" => "LIST",
            "ofType" => Dict("kind" => "OBJECT")
        )
    )
    @test GraphQLClient.isroottypeobject(listofobjects)
    @test !GraphQLClient.isroottypeenum(listofobjects)
    listofenums = Dict(
        "type" => Dict(
            "kind" => "LIST",
            "ofType" => Dict("kind" => "ENUM")
        )
    )
    @test GraphQLClient.isroottypeenum(listofenums)
    @test !GraphQLClient.isroottypeobject(listofenums)
    nonnull_enum_list = build_type("kind", "Fieldname",
        type=build_type("NON_NULL", "",
            ofType=build_type("LIST", "",
                ofType=build_type("ENUM",""))))
    @test GraphQLClient.isroottypeenum(nonnull_enum_list)
    nonnull_object_list = build_type("kind", "Fieldname",
        type=build_type("NON_NULL", "",
            ofType=build_type("LIST", "",
                ofType=build_type("OBJECT",""))))
    @test GraphQLClient.isroottypeobject(nonnull_object_list)
end

@testset "get_field_type_string and getjuliatype" begin
    # SCALAR
    arg = build_arg("SCALAR", nothing, "String", nothing)
    @test GraphQLClient.get_field_type_string(arg) == "String"
    @test GraphQLClient.getroottype(arg) == "String"
    @test GraphQLClient.getjuliatype(arg) == String
    
    # Custom scalar
    scalar_dict = merge(
        GraphQLClient.GQL_DEFAULT_SCALAR_TO_JULIA_TYPE,
        Dict("CUSTOM_FLOAT_32" => Float32),
    )
    arg = build_arg("SCALAR", nothing, "CUSTOM_FLOAT_32", nothing)
    @test GraphQLClient.get_field_type_string(arg) == "CUSTOM_FLOAT_32"
    @test GraphQLClient.getroottype(arg) == "CUSTOM_FLOAT_32"
    @test GraphQLClient.getjuliatype(arg; scalar_types=scalar_dict) == Float32

    # INPUT_OBJECT
    arg = build_arg("INPUT_OBJECT", nothing, "MyObject", nothing)
    @test GraphQLClient.get_field_type_string(arg) == "MyObject"
    @test GraphQLClient.getroottype(arg) == "MyObject"
    @test GraphQLClient.getjuliatype(arg) == GraphQLClient.InputObject
    
    # ENUM
    arg = build_arg("ENUM", nothing, "MyEnum", nothing)
    @test GraphQLClient.get_field_type_string(arg) == "MyEnum"
    @test GraphQLClient.getroottype(arg) == "MyEnum"
    @test GraphQLClient.getjuliatype(arg) == String
    
    # NON_NULL
    arg = Dict(
        "name" => "MyArg",
        "defaultValue" =>  nothing,
        "description" =>  nothing,
        "type" => build_type("NON_NULL", nothing; ofType=build_type("SCALAR", "String"))
    )
    @test GraphQLClient.get_field_type_string(arg) == "String!"
    @test GraphQLClient.getroottype(arg) == "String"
    @test GraphQLClient.getjuliatype(arg) == String

    # LIST
    arg = Dict(
        "name" => "MyArg",
        "defaultValue" =>  nothing,
        "description" =>  nothing,
        "type" => build_type("LIST", nothing; ofType=build_type("SCALAR", "Float"))
    )
    @test GraphQLClient.get_field_type_string(arg) == "[Float]"
    @test GraphQLClient.getroottype(arg) == "Float"
    @test GraphQLClient.getjuliatype(arg) == Vector{Float64}

    # NESTED NON-NULL LIST
    arg = Dict(
        "name" => "MyArg",
        "defaultValue" =>  nothing,
        "description" =>  nothing,
        "type" => build_type("NON_NULL", nothing; 
            ofType=build_type("LIST", nothing,
                ofType=build_type("LIST", nothing,
                    ofType=build_type("ENUM", "MyEnum")))))
    @test GraphQLClient.get_field_type_string(arg) == "[[MyEnum]]!"
    @test GraphQLClient.getroottype(arg) == "MyEnum"
    @test GraphQLClient.getjuliatype(arg) == Vector{Vector{String}}

    # OBJECT
    arg = build_arg("OBJECT", nothing, "MyObject", nothing)
    @test GraphQLClient.get_field_type_string(arg) == "MyObject"
    @test GraphQLClient.getroottype(arg) == "MyObject"
    @test GraphQLClient.getjuliatype(arg) == GraphQLClient.Object

    # Errors - not handled types
    arg = build_arg("UNION", nothing, "MyEnum", nothing)
    @test_throws GraphQLClient.GraphQLClientException GraphQLClient.get_field_type_string(arg)
    @test_throws GraphQLClient.GraphQLClientException GraphQLClient.getjuliatype(arg)
    arg = build_arg("INTERFACE", nothing, "MyEnum", nothing)
    @test_throws GraphQLClient.GraphQLClientException GraphQLClient.get_field_type_string(arg)
    @test_throws GraphQLClient.GraphQLClientException GraphQLClient.getjuliatype(arg)

    # Errors - unrecognised scalars
    arg = build_arg("SCALAR", nothing, "NOT_A_DEFAULT", nothing)
    @test_throws ArgumentError GraphQLClient.getjuliatype(arg)
    arg = build_arg("SCALAR", nothing, "NOT_IN_CUSTOM_DICT", nothing)
    @test_throws ArgumentError GraphQLClient.getjuliatype(arg; scalar_types=scalar_dict)
end

@testset "getroottypefield" begin
    type = build_type("NON_NULL", "name",
        type=build_type("LIST", nothing,
            ofType=build_type("LIST", nothing,
                ofType=build_type("SCALAR", "Boolean"))))
    @test GraphQLClient.getroottypefield(type) == build_type("SCALAR", "Boolean")
    type = build_type("LIST", "name",
        type=build_type("LIST", nothing,
            ofType=build_type("LIST", nothing,
                ofType=build_type("SCALAR", "Boolean"))))
    @test GraphQLClient.getroottypefield(type) == build_type("SCALAR", "Boolean")
    type = build_type("LIST", "name", type=build_type("SCALAR", "Boolean"))
    @test GraphQLClient.getroottypefield(type) == build_type("SCALAR", "Boolean")
end

@testset "getroottypefield" begin
    type = build_type("NON_NULL", "name",
        type=build_type("LIST", nothing,
            ofType=build_type("LIST", nothing,
                ofType=build_type("SCALAR", "Boolean"))))
    @test GraphQLClient.getroottypefield(type) == build_type("SCALAR", "Boolean")
    type = build_type("LIST", "name",
        type=build_type("LIST", nothing,
            ofType=build_type("LIST", nothing,
                ofType=build_type("SCALAR", "Boolean"))))
    @test GraphQLClient.getroottypefield(type) == build_type("SCALAR", "Boolean")
    type = build_type("LIST", "name", type=build_type("SCALAR", "Boolean"))
    @test GraphQLClient.getroottypefield(type) == build_type("SCALAR", "Boolean")
end