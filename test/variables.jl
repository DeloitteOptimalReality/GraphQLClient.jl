@testset "get_variables_str" begin
    client = Client("url","ws"; introspect=false)

    # Simple test of field
    client.query_to_args_map["Query"] = Dict("fieldName" => "Int")
    args = Dict("fieldName" => 1)
    arg_names = Dict("fieldName" => "fieldName1")
    @test GraphQLClient.get_variables_str(client, args, arg_names, "Query") == "\$fieldName1: Int,"
    
    # Simple test of input object
    client.query_to_args_map["Query"] = Dict("fieldName" => "InputObject")
    client.input_object_fields_to_type_map["InputObject"] = Dict("subfieldName" => "Int")
    args = Dict("fieldName" => Dict("subfieldName" => 1))
    arg_names = Dict("fieldName" => Dict("subfieldName" => "subfieldName1"))
    @test GraphQLClient.get_variables_str(client, args, arg_names, "Query") == "\$subfieldName1: Int,"
    
    # Simple test of non null input object
    client.query_to_args_map["Query"] = Dict("fieldName" => "InputObject!")
    client.input_object_fields_to_type_map["InputObject"] = Dict("subfieldName" => "Int")
    args = Dict("fieldName" => Dict("subfieldName" => 1))
    arg_names = Dict("fieldName" => Dict("subfieldName" => "subfieldName1"))
    @test GraphQLClient.get_variables_str(client, args, arg_names, "Query") == "\$subfieldName1: Int,"
        
    # Simple test of vector of input objects
    client.query_to_args_map["Query"] = Dict("fieldName" => "[InputObject]")
    client.input_object_fields_to_type_map["InputObject"] = Dict("subfieldName" => "Int")
    args = Dict("fieldName" => [Dict("subfieldName" => 1), Dict("subfieldName" => 1)])
    arg_names = Dict("fieldName" => [
        Dict("subfieldName" => "subfieldName1"),
        Dict("subfieldName" => "subfieldName2")
    ])
    @test GraphQLClient.get_variables_str(client, args, arg_names, "Query") == "\$subfieldName1: Int,\$subfieldName2: Int,"
end

@testset "get_query_variables" begin
    # Simple test of field
    args = Dict("fieldName" => 1)
    arg_names = Dict("fieldName" => "fieldName1")
    variables = GraphQLClient.get_query_variables(args, arg_names)
    @test haskey(variables, "fieldName1")
    @test variables["fieldName1"] == 1

    # Simple test of input object
    args = Dict("fieldName" => Dict("subfieldName" => true))
    arg_names = Dict("fieldName" => Dict("subfieldName" => "subfieldName1"))
    variables = GraphQLClient.get_query_variables(args, arg_names)
    @test haskey(variables, "subfieldName1")
    @test variables["subfieldName1"] == true

    # Simple test of vector of input objects
    args = Dict("fieldName" => [Dict("subfieldName" => 1), Dict("subfieldName" => 2)])
    arg_names = Dict("fieldName" => [
        Dict("subfieldName" => "subfieldName1"),
        Dict("subfieldName" => "subfieldName2")
    ])
    variables = GraphQLClient.get_query_variables(args, arg_names)
    @test haskey(variables, "subfieldName1")
    @test haskey(variables, "subfieldName2")
    @test variables["subfieldName1"] == 1
    @test variables["subfieldName2"] == 2

    # Test lots of repeated fields
    args = Dict(
        "arg1" => 1,
        "arg2" => Dict(
            "arg1" => 2,
            "arg2" => [
                Dict(
                    "arg1" => 6.0,
                    "arg2" => 5.0,
                ),
                Dict(
                    "arg1" => 7.0,
                    "arg2" => 2.0,
                ),
            ]
        )
    )
    _, arg_names = GraphQLClient.get_query_args_str(args)
    variables = GraphQLClient.get_query_variables(args, arg_names)
    @test variables[arg_names["arg1"]] == 1
    @test variables[arg_names["arg2"]["arg1"]] == 2
    @test variables[arg_names["arg2"]["arg2"][1]["arg1"]] == 6.0
    @test variables[arg_names["arg2"]["arg2"][1]["arg2"]] == 5.0
    @test variables[arg_names["arg2"]["arg2"][2]["arg1"]] == 7.0
    @test variables[arg_names["arg2"]["arg2"][2]["arg2"]] == 2.0
end