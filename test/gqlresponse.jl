@testset "GQLLocation" begin
    str = """{"line": 1, "column": 10}"""
    loc = JSON3.read(str, GraphQLClient.GQLLocation)
    @test loc.line == 1
    @test loc.column == 10
    @test sprint(show, loc) == "Line 1 Column 10"
end

@testset "GQLError" begin
    str = """{"message": "Message text"}"""
    err = JSON3.read(str, GraphQLClient.GQLError)
    @test err.message == "Message text"
    @test isnothing(err.locations)
    str = """{"message": "Message text", "locations":[{"line": 1, "column": 10}]}"""
    err = JSON3.read(str, GraphQLClient.GQLError)
    @test err.message == "Message text"
    @test !isempty(err.locations)
end

@testset "GQLResponse" begin
    # Successful query, no errors, default parametric type
    response="""
    {
        "data": {
            "queryName1": {
                "fieldName": "fieldValue"
            },
            "queryName2": {
                "fieldName": 0
            }
        }
    }
    """
    resp = JSON3.read(response, GraphQLClient.GQLResponse{Any})
    @inferred JSON3.read(response, GraphQLClient.GQLResponse{Any})
    @test isnothing(resp.errors)
    @test !isempty(resp.data)
    @test haskey(resp.data, "queryName1")
    @test haskey(resp.data, "queryName2")

    # Unuccessful query, error before execution, default parametric type
    response = """
    {
        "errors": [
            {
                "message": "Failed before execution",
                "locations": [
                    {"line": 1, "column": 10},
                    {"line": 2, "column": 12}
                ]
            },
            {
                "message": "No locations"
            }
        ]
    }
    """
    resp = JSON3.read(response, GraphQLClient.GQLResponse{Any})
    @test length(resp.errors) == 2
    @test isnothing(resp.data)

    # Unuccessful query, error during execution, default parametric type
    response = """
    {
        "errors": [
            {
                "message": "Failed before execution",
                "locations": [
                    {"line": 1, "column": 10},
                    {"line": 2, "column": 12}
                ]
            },
            {
                "message": "No locations"
            }
        ],
        "data": {
            "queryName": null
        }
    }
    """
    resp = JSON3.read(response, GraphQLClient.GQLResponse{Any})
    @test length(resp.errors) == 2
    @test !isempty(resp.data)
    @test isnothing(resp.data["queryName"])

    # Custom type
    response = """
    {
        "data": {
            "queryName": {
                "fieldName1": "fieldValue",
                "fieldName2": 1.0
            }
        }
    }"""
    struct QueryNameResponse
        fieldName1::String
        fieldName2::Float64
    end
    StructTypes.StructType(::Type{QueryNameResponse}) = StructTypes.OrderedStruct()
    resp = JSON3.read(response, GraphQLClient.GQLResponse{QueryNameResponse})
    @inferred JSON3.read(response, GraphQLClient.GQLResponse{QueryNameResponse})
    @test resp.data["queryName"] isa QueryNameResponse

    # failed custom type
    response = """{"data": {"queryName": null}}"""
    resp = JSON3.read(response, GraphQLClient.GQLResponse{QueryNameResponse})
    @test isnothing(resp.data["queryName"])
end