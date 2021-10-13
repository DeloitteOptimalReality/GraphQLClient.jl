"""
    full_introspection!(client::Client)

Performs a full instrospection of the GraphQL schema of the `client`. The results are stored
in the client struct.

See also: [`Client`](@ref)
"""
function full_introspection!(client::Client)
    query_str = """
    query IntrospectionQuery {
        __schema {
            queryType {
                name
            }
            mutationType {
                name
            }
            subscriptionType {
                name
            }
            types {
                ...FullType
            }
            directives {
                name
                description
                locations
                args {
                    ...InputValue
                }
            }
        }
    }

    fragment FullType on __Type {
        kind
        name
        description
        fields(includeDeprecated: true) {
            name
            description
            args {
                ...InputValue
            }
            type {
                ...TypeRef
            }
            isDeprecated
            deprecationReason
        }
        inputFields {
            ...InputValue
        }
        interfaces {
            ...TypeRef
        }
        enumValues(includeDeprecated: true) {
            name
            description
            isDeprecated
            deprecationReason
        }
        possibleTypes {
            ...TypeRef
        }
    }
    fragment InputValue on __InputValue {
        name
        description
        type {
            ...TypeRef
        }
        defaultValue
    }
    fragment TypeRef on __Type {
        kind
        name
        ofType {
            kind
            name
            ofType {
                kind
                name
                ofType {
                    kind
                    name
                    ofType {
                        kind
                        name
                        ofType {
                            kind
                            name
                            ofType {
                                kind
                                name
                                ofType {
                                    kind
                                    name
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    """

    # Execute introspection query and extract schema
    body = execute(client, query_str)
    schema = body.data["__schema"]

    keys_to_include = ["queryType"]
    query_type = schema["queryType"]["name"]
    server_has_mutations = !isnothing(schema["mutationType"])
    server_has_subs = !isnothing(schema["subscriptionType"])
    if server_has_mutations
        mutation_type = schema["mutationType"]["name"]
        push!(keys_to_include, "mutationType")
    end
    if server_has_subs
        subscription_type = schema["subscriptionType"]["name"]
        push!(keys_to_include, "subscriptionType")
    end
    gql_types = [schema[k]["name"] for k in keys_to_include]

    # Populate input_object_fields_to_type_map
    empty!(client.input_object_fields_to_type_map) # Reset
    for gql_type in schema["types"]
        if gql_type["kind"] == "INPUT_OBJECT"
            field_to_type_map = Dict()
            for field in gql_type["inputFields"]
                field_to_type_map[field["name"]] = get_field_type_string(field)
            end
            client.input_object_fields_to_type_map[gql_type["name"]] = field_to_type_map
        end
    end

    # Populate query_to_type_map
    empty!(client.query_to_type_map) # Reset
    for gql_type in schema["types"]
        if gql_type["name"] in gql_types
            for field in gql_type["fields"]
                field_type = _recursive_get_value(
                    field["type"],
                    "ofType"
                )["name"]
                client.query_to_type_map[field["name"]] = field_type
                gql_type["name"] == query_type && push!(client.queries, field["name"])
                server_has_mutations && gql_type["name"] == mutation_type && push!(client.mutations, field["name"])
                server_has_subs && gql_type["name"] == subscription_type && push!(client.subscriptions, field["name"])
            end
        end
    end

    # Populate query_to_args_map
    empty!(client.query_to_args_map) # Reset
    for gql_type in schema["types"]
        if gql_type["name"] in gql_types
            for field in gql_type["fields"]
                for arg in field["args"]
                    get!(client.query_to_args_map, field["name"], Dict{String, String}()) # Add if it doesn't exist
                    client.query_to_args_map[field["name"]][arg["name"]] = get_field_type_string(arg)
                end
            end
        end
    end

    # Populate type_to_fields_map
    empty!(client.type_to_fields_map) # Reset
    for gql_type in schema["types"]
        if get(gql_type, "fields", nothing) !== nothing
            client.type_to_fields_map[gql_type["name"]] = Dict(f["name"] => f for f in gql_type["fields"])
        elseif get(gql_type, "inputFields", nothing) !== nothing
            client.type_to_fields_map[gql_type["name"]] = Dict(f["name"] => f for f in gql_type["inputFields"])# [f["name"] for f in gql_type["inputFields"]]
        end
    end

    client.schema = schema
    client.introspection_complete = true

    return client
end

"""
    introspect_node(node)

Introspect single node in GQL schema.
"""
function introspect_node(client::Client, node)
    query_str = "{
            __type(name:\"$node\") {
                name
                fields {
                    description
                    type {
                        name
                        kind
                        ofType {
                            name
                        }
                    }
                }
            }
        }"
    body = execute(client, query_str)
    fields = [field["description"] for field in body["data"]["__type"]["fields"]]
    return fields
end

"""
    _recursive_get_value(dict, key)

Recursively iterate through a dict until value of key is nothing.
"""
function _recursive_get_value(dict, key)
    if dict[key] !== nothing
        return _recursive_get_value(dict[key], key)
    else
        return dict
    end
end