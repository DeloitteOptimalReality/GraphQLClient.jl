function build_arg(kind, type, name, description)
    return Dict{String, Any}(
        "name" => "MyArg",
        "defaultValue" =>  nothing,
        "description" =>  nothing,
        "type" => build_type(kind, name; description, type)
    )
end

function build_type(kind, name; description="", type=nothing, ofType=nothing)
    type_dict =  Dict{String, Any}(
        "kind" => kind,
        "name" => name,
        "description" => description,
    )
    !isnothing(type) && push!(type_dict, "type" => type)
    !isnothing(ofType) && push!(type_dict, "ofType" => ofType)
    return type_dict
end