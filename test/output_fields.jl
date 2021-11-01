@testset "get_output_str" begin
    @test GraphQLClient.get_output_str("field1") == "field1,"
    @test GraphQLClient.get_output_str(Alias("alias_name", "field_name")) == "alias_name:field_name,"
    @test GraphQLClient.get_output_str(["field1"]) == "field1,"
    @test GraphQLClient.get_output_str(["field1", "field2"]) == "field1,field2,"
    @test GraphQLClient.get_output_str(Dict("field1" => "field2")) == "field1{field2,},"
    @test GraphQLClient.get_output_str(Dict("field1" => ["field2"])) == "field1{field2,},"
    @test GraphQLClient.get_output_str(Dict("field1" => ["field2", "field3"])) == "field1{field2,field3,},"
    @test GraphQLClient.get_output_str(["field1", Dict("field2" => ["field3"])]) == "field1,field2{field3,},"
end

@testset "_get_fields_str" begin
    client = Client("url", "ws"; introspect=false)

    # Not an object, list of objects or nonnull
    field = build_type(nothing, "field_name", type=build_type("SCALAR", "String"))
    @test GraphQLClient._get_field_str(client, field, [], []) == "field_name,"

    # Empty Object
    field = build_type(nothing, "object_field_name", type=build_type("OBJECT", "MyObject"))
    client.type_to_fields_map["MyObject"] = Dict()
    @test GraphQLClient._get_field_str(client, field, [], []) == ""

    # Object with two fields
    field1 = build_type(nothing, "field1", type=build_type("SCALAR", "String"))
    field2 = build_type(nothing, "field2", type=build_type("SCALAR", "Float"))
    client.type_to_fields_map["MyObject"] = Dict(
        "field1" => field1,
        "field2" => field2,
    )
    @test GraphQLClient._get_field_str(client, field, [], []) == "object_field_name{field1,field2,}"

    # List of scalars
    field = build_type(nothing, "scalar_field_name",
        type=build_type("LIST", nothing,
            ofType=build_type("SCALAR", "String")))
    @test GraphQLClient._get_field_str(client, field, [], []) == "scalar_field_name,"

    # List of objects with two fields
    field = build_type(nothing, "object_field_name",
        type=build_type("LIST", nothing,
            ofType=build_type("OBJECT", "MyObject")))
    @test GraphQLClient._get_field_str(client, field, [], []) == "object_field_name{field1,field2,}"

    # Nonnull scalar, enum and list of enums
    field = build_type(nothing, "field_name",
        type=build_type("NON_NULL", nothing,
            ofType=build_type("SCALAR", "String")))
    @test GraphQLClient._get_field_str(client, field, [], []) == "field_name,"
    field = build_type(nothing, "enum_field_name", 
        type=build_type("NON_NULL", nothing,
            ofType = build_type("ENUM", "MyEnum")))
    @test GraphQLClient._get_field_str(client, field, [], []) == "enum_field_name,"
    field = build_type(nothing, "enum_field_name",
        type=build_type("NON_NULL", nothing,
            ofType=build_type("LIST", nothing,
                ofType=build_type("ENUM", "MyEnum"))))
    @test GraphQLClient._get_field_str(client, field, [], []) == "enum_field_name,"
    field = build_type(nothing, "enum_field_name",
        type=build_type("NON_NULL", nothing,
            ofType=build_type("LIST", nothing,
                ofType=build_type("LIST", nothing,
                    ofType=build_type("ENUM", "MyEnum")))))
    @test GraphQLClient._get_field_str(client, field, [], []) == "enum_field_name,"

    # Nonnull object
    field = build_type(nothing, "object_field_name",
    type=build_type("NON_NULL", nothing,
            ofType=build_type("OBJECT", "MyObject")))
    @test GraphQLClient._get_field_str(client, field, [], []) == "object_field_name{field1,field2,}"

    # Nonnull list of objects
    field = build_type(nothing, "object_field_name",
        type=build_type("NON_NULL", nothing,
            ofType=build_type("LIST", nothing,
                ofType=build_type("OBJECT", "MyObject"))))
    @test GraphQLClient._get_field_str(client, field, [], []) == "object_field_name{field1,field2,}"

    # Recursion in objects should warn
    field1 = build_type(nothing, "field1", type=build_type("SCALAR", "String"))
    recursive_object = build_type(nothing, "object_field_name", type=build_type("OBJECT", "MyRecursiveObject"))
    client.type_to_fields_map["MyRecursiveObject"] = Dict(
        "field1" => field1,
        "field2" => recursive_object,
    )
    objects_that_recurse = String[]
    @test GraphQLClient._get_field_str(client, recursive_object, [], objects_that_recurse) == "object_field_name{field1,}"
    @test in("MyRecursiveObject", objects_that_recurse)

    # Same when object is nonnull
    recursive_object = build_type(nothing, "object_field_name",
        type=build_type("NON_NULL", nothing,
            ofType=build_type("OBJECT", "MyRecursiveObject")))
    objects_that_recurse = String[]
    @test GraphQLClient._get_field_str(client, recursive_object, [], objects_that_recurse) == "object_field_name{field1,}"
    @test in("MyRecursiveObject", objects_that_recurse)

    # Same when object is list
    recursive_object = build_type(nothing, "object_field_name",
        type=build_type("LIST", nothing,
            ofType=build_type("OBJECT", "MyRecursiveObject")))
    objects_that_recurse = String[]
    @test GraphQLClient._get_field_str(client, recursive_object, [], objects_that_recurse) == "object_field_name{field1,}"
    @test in("MyRecursiveObject", objects_that_recurse)

    # Unknown type
    field = build_type(nothing, "field_name", type=build_type("UNION", "String"))
    @test_throws GraphQLClient.GraphQLClientException GraphQLClient._get_field_str(client, field, [], [])
    # Unknown NON_NULLtype
    field = build_type(nothing, "field_name",
        type=build_type("NON_NULL", nothing,
            ofType=build_type("UNION", "String")))
    @test_throws GraphQLClient.GraphQLClientException GraphQLClient._get_field_str(client, field, [], [])
end

@testset "get_all_output_fields_str" begin
    # type_to_fields_map
    client = Client("url", "ws"; introspect=false)
    type = "MyType"
    client.type_to_fields_map[type] = Dict(
        "field1" => build_type(nothing, "field1", type=build_type("SCALAR", "Boolean")),
        "field2" => build_type(nothing, "field2", type=build_type("OBJECT", "MyObject")),
    )
    client.type_to_fields_map["MyObject"] = Dict(
        "field2" => build_type(nothing, "field2", type=build_type("SCALAR", "Float")),
    )
    @test GraphQLClient.get_field_names_string(client, type, [], []) == "field1,field2{field2,}"

    # Type with no fields
    type = "MyEmptyType"
    client.type_to_fields_map[type] = Dict()
    @test GraphQLClient.get_field_names_string(client, type, [], []) == ""

    # get_all_output_fields_str
    query_name = "myQuery"
    client.query_to_type_map[query_name] = "MyType"
    @test GraphQLClient.get_all_output_fields_str(client, query_name, []) == "field1,field2{field2,}"
    query_name = "myQuery"
    client.query_to_type_map[query_name] = "MyEmptyType"
    @test GraphQLClient.get_all_output_fields_str(client, query_name, []) == ""

    # test objects_to_ignore is working
    type = "MyRecursiveType"
    client.type_to_fields_map[type] = Dict(
        "field1" => build_type(nothing, "field1", type=build_type("SCALAR", "Boolean")),
        "field2" => build_type(nothing, "field2", type=build_type("OBJECT", "MyRecursiveType")),
    )
    client.query_to_type_map[query_name] = "MyRecursiveType"
    @test GraphQLClient.get_all_output_fields_str(client, query_name, []) == "field1,"
    @test_logs (:warn, Regex("Can't query all output fields due to recursion of these object\\(s\\):")) GraphQLClient.get_all_output_fields_str(client, query_name, [])
end

@testset "issue #7" begin
    output_fields=[
        Dict(
            "level1" =>Dict(
                "level2" => Dict(
                    "level3" => Dict(
                        "level4_1" => [
                            "level4_1_1",
                        ],
                        "level4_2" => [
                            "level4_2_1",
                        ],
                    ) 
                )
            )
        )
    ]
    output_str = GraphQLClient.get_output_str(output_fields)
    @test occursin("level4_1{level4_1_1,}" , output_str)
    @test occursin("level4_2{level4_2_1,}" , output_str)
end