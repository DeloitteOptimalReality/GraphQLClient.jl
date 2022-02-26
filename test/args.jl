@testset "initialise_arg_names" begin
    test_dict = Dict(
        "arg1" => 1,
        "arg2" => "str",
        "arg3" => [1,2,3],
        "arg4" => Dict(
            "arg1" => 2,
            "arg2" => [
                Dict(
                    "arg3" => 1,
                    "arg5" => 5.0,
                ),
                Dict(
                    "arg3" => 1,
                    "arg5" => 5.0,
                ),
            ]
        )
    )
    initialised_dict = GraphQLClient.initialise_arg_names(test_dict)
    @test keys(test_dict) == keys(initialised_dict)
    @test keys(test_dict["arg4"]) == keys(initialised_dict["arg4"])
    @test keys(test_dict["arg4"]["arg2"][1]) == keys(initialised_dict["arg4"]["arg2"][1])
    @test keys(test_dict["arg4"]["arg2"][2]) == keys(initialised_dict["arg4"]["arg2"][2])
end

@testset "get_query_args_str" begin
    # Basic test
    args = Dict(
        "A" => 1.0,
        "B" => "word"
    )
    str, arg_names = GraphQLClient.get_query_args_str(args)
    @test occursin("B:\$B,", str)
    @test occursin("A:\$A,", str)
    @test all(keys(arg_names) .== values(arg_names))
    
    # Nested dictionary
    args = Dict(
        "A" => 1.0,
        "B" => Dict("C" => true)
    )
    str, arg_names = GraphQLClient.get_query_args_str(args)
    @test occursin("A:\$A,", str)
    @test occursin("B:{C:\$C,},", str)

    # Vector of dictionaries with same keys
    args = Dict("vec" => [
        Dict(
            "A" => 1.0,
            "B" => true,
        ),
        Dict(
            "A" => 3.0,
            "B" => false,
        ),
    ])
    str, arg_names = GraphQLClient.get_query_args_str(args)
    @test length(unique(vcat(collect(values(arg_names["vec"][1])), collect(values(arg_names["vec"][2]))))) == 4 # four unique names
    @test all(key -> occursin(key, str), keys(arg_names["vec"][1]))  # Check all arg_names are in str
    @test all(key -> occursin(key, str), keys(arg_names["vec"][2]))  # Check all arg_names are in str

    # Different fields with same keys
    args = Dict(
        "arg1" => 1,
        "arg2" => Dict(
            "arg1" => 2,
            "arg2" => [
                Dict(
                    "arg1" => 6,
                    "arg2" => 5.0,
                ),
                Dict(
                    "arg1" => 5,
                    "arg2" => 2.0,
                ),
            ]
        )
    )
    str, arg_names = GraphQLClient.get_query_args_str(args)
    all_names = vcat(
        arg_names["arg1"],
        arg_names["arg2"]["arg1"],
        collect(values(arg_names["arg2"]["arg2"][1])),
        collect(values(arg_names["arg2"]["arg2"][2])),
    )
    @test length(all_names) == length(unique(all_names))
end

@testset "directly_write_query_args" begin
    @test GraphQLClient.directly_write_query_args(Dict("a"=>1)) == "a:1"
    @test GraphQLClient.directly_write_query_args(Dict("a"=>"string")) == "a:\"string\""
    @test GraphQLClient.directly_write_query_args(Dict("a"=>GQLEnum("enum"))) == "a:enum"
    @test GraphQLClient.directly_write_query_args(Dict("a"=>true)) == "a:true"
    @test GraphQLClient.directly_write_query_args(Dict("a"=>[1])) == "a:[1]"
    str = GraphQLClient.directly_write_query_args(Dict("a"=>1, "b"=>1.0))
    @test occursin("a:1", str)
    @test occursin("b:1.0", str)
    @test GraphQLClient.directly_write_query_args(Dict("a"=>Dict("b"=>[1]))) == "a:{b:[1]}"
    @test GraphQLClient.directly_write_query_args(Dict()) == ""
end